import Foundation

#if !os(Windows) && canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// Configuration for the local Wasm Hot-Reload HTTP + SSE dev server.
public struct WasmDevServerConfiguration: Sendable, Equatable {
  public var host: String
  public var port: UInt16
  public var hmrEndpoint: String
  public var injectHMR: Bool

  public init(
    host: String = "127.0.0.1",
    port: UInt16 = 8000,
    hmrEndpoint: String = "/__crossswift_hmr",
    injectHMR: Bool = true
  ) {
    self.host = host
    self.port = port
    self.hmrEndpoint = hmrEndpoint
    self.injectHMR = injectHMR
  }
}

/// Server-Sent Event payloads broadcast from the dev server to `Web/index.html`.
public enum WasmHMREvent: Sendable, Equatable {
  case status(state: String, message: String?)
  case resources(version: Int)
  case wasm(version: Int)

  public func toJSON() -> String {
    let payload: [String: Any]
    switch self {
    case .status(let state, let message):
      if let message, !message.isEmpty {
        payload = ["type": "status", "state": state, "message": message]
      } else {
        payload = ["type": "status", "state": state]
      }
    case .resources(let version):
      payload = ["type": "resources", "version": version]
    case .wasm(let version):
      payload = ["type": "wasm", "version": version]
    }
    guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
          let text = String(data: data, encoding: .utf8)
    else {
      return "{\"type\":\"status\",\"state\":\"ready\"}"
    }
    return text
  }
}

public enum WasmDevServerError: Error, LocalizedError {
  case unsupportedPlatform
  case socketFailed(String)
  case bindFailed(host: String, port: UInt16, errno: Int32)
  case listenFailed(errno: Int32)

  public var errorDescription: String? {
    switch self {
    case .unsupportedPlatform:
      return "WasmDevServer is supported on macOS and Linux."
    case .socketFailed(let detail):
      return "Failed to initialize dev server socket: \(detail)"
    case .bindFailed(let host, let port, let code):
      return "Failed to bind dev server to \(host):\(port) (errno \(code))"
    case .listenFailed(let code):
      return "Failed to listen on dev server socket (errno \(code))"
    }
  }
}

/// Zero-dependency HTTP/1.1 static file + SSE dev server for Wasm hot reload.
public final class WasmDevServer: @unchecked Sendable {
  public let rootDirectory: URL
  public let configuration: WasmDevServerConfiguration

  private let lock = NSLock()
  private var listenFD: Int32 = -1
  private var isRunning = false
  private var sseClients: Set<Int32> = []
  private var lastStatusEvent: WasmHMREvent?
  private var keepaliveTimer: DispatchSourceTimer?
  private let acceptQueue = DispatchQueue(label: "dev.crossswift.wasmserver.accept", qos: .userInitiated)
  private let clientQueue = DispatchQueue(
    label: "dev.crossswift.wasmserver.client",
    qos: .userInitiated,
    attributes: .concurrent
  )

  public private(set) var boundPort: UInt16 = 0

  public var baseURL: String {
    "http://\(configuration.host):\(boundPort)"
  }

  public var connectedSSEClientCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return sseClients.count
  }

  public init(
    rootDirectory: URL,
    configuration: WasmDevServerConfiguration = WasmDevServerConfiguration()
  ) {
    self.rootDirectory = rootDirectory.standardizedFileURL
    self.configuration = configuration
  }

  deinit {
    stop()
  }

  public func start() throws {
    #if os(Windows)
      throw WasmDevServerError.unsupportedPlatform
    #else
      lock.lock()
      if isRunning {
        lock.unlock()
        return
      }
      lock.unlock()

      // Prevent broken browser tabs / closed SSE streams from terminating the process.
      _ = signal(SIGPIPE, SIG_IGN)

      #if os(Linux)
        let sockType = Int32(SOCK_STREAM.rawValue)
      #else
        let sockType = SOCK_STREAM
      #endif
      let fd = socket(AF_INET, sockType, 0)
      guard fd >= 0 else {
        throw WasmDevServerError.socketFailed("socket() returned errno \(errno)")
      }

      var reuse: Int32 = 1
      _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

      var addr = sockaddr_in()
      #if canImport(Darwin)
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
      #endif
      addr.sin_family = sa_family_t(AF_INET)
      addr.sin_port = configuration.port.bigEndian
      if configuration.host == "0.0.0.0" || configuration.host.isEmpty {
        addr.sin_addr = in_addr(s_addr: 0)
      } else {
        var parsed = in_addr()
        let ok = configuration.host.withCString { cstr in
          inet_pton(AF_INET, cstr, &parsed)
        }
        if ok == 1 {
          addr.sin_addr = parsed
        } else {
          // Fall back to loopback if host is e.g. "localhost".
          _ = "127.0.0.1".withCString { cstr in
            inet_pton(AF_INET, cstr, &parsed)
          }
          addr.sin_addr = parsed
        }
      }

      let bindResult = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
          bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
      }
      guard bindResult == 0 else {
        let err = errno
        close(fd)
        throw WasmDevServerError.bindFailed(host: configuration.host, port: configuration.port, errno: err)
      }

      guard listen(fd, 128) == 0 else {
        let err = errno
        close(fd)
        throw WasmDevServerError.listenFailed(errno: err)
      }

      var actualAddr = sockaddr_in()
      var actualLen = socklen_t(MemoryLayout<sockaddr_in>.size)
      let nameResult = withUnsafeMutablePointer(to: &actualAddr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
          getsockname(fd, sockPtr, &actualLen)
        }
      }
      let resolvedPort: UInt16 = (nameResult == 0) ? UInt16(bigEndian: actualAddr.sin_port) : configuration.port

      lock.lock()
      self.listenFD = fd
      self.boundPort = resolvedPort
      self.isRunning = true

      let heartbeat = DispatchSource.makeTimerSource(queue: clientQueue)
      heartbeat.schedule(deadline: .now() + .seconds(15), repeating: .seconds(15))
      heartbeat.setEventHandler { [weak self] in
        self?.sendSSEFrame(": keepalive\n\n")
      }
      self.keepaliveTimer = heartbeat
      lock.unlock()
      heartbeat.resume()

      acceptQueue.async { [weak self] in
        self?.acceptLoop(listenFD: fd)
      }
    #endif
  }

  public func stop() {
    #if !os(Windows)
      lock.lock()
      let wasRunning = isRunning
      isRunning = false
      let fd = listenFD
      listenFD = -1
      let clients = sseClients
      sseClients.removeAll()
      let timer = keepaliveTimer
      keepaliveTimer = nil
      lock.unlock()

      timer?.cancel()
      guard wasRunning || fd >= 0 || !clients.isEmpty else { return }

      if fd >= 0 {
        #if os(Linux)
          _ = shutdown(fd, Int32(SHUT_RDWR))
        #else
          _ = shutdown(fd, SHUT_RDWR)
        #endif
        _ = close(fd)
      }
      for clientFD in clients {
        #if os(Linux)
          _ = shutdown(clientFD, Int32(SHUT_RDWR))
        #else
          _ = shutdown(clientFD, SHUT_RDWR)
        #endif
        _ = close(clientFD)
      }
    #endif
  }

  /// Broadcasts an HMR event to all connected SSE clients.
  public func broadcast(_ event: WasmHMREvent) {
    if case .status = event {
      lock.lock()
      lastStatusEvent = event
      lock.unlock()
    }
    #if !os(Windows)
      sendSSEFrame("data: \(event.toJSON())\n\n")
    #endif
  }

  /// Resolves the HTTP Content-Type header for a file path.
  public static func mimeType(forPath path: String) -> String {
    let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
    switch ext {
    case "wasm": return "application/wasm"
    case "js", "mjs": return "text/javascript; charset=utf-8"
    case "html", "htm": return "text/html; charset=utf-8"
    case "css": return "text/css; charset=utf-8"
    case "json", "xcstrings", "map": return "application/json; charset=utf-8"
    case "svg": return "image/svg+xml"
    case "png": return "image/png"
    case "jpg", "jpeg": return "image/jpeg"
    case "webp": return "image/webp"
    case "gif": return "image/gif"
    case "ico": return "image/x-icon"
    case "woff2": return "font/woff2"
    case "woff": return "font/woff"
    case "ttf": return "font/ttf"
    case "otf": return "font/otf"
    case "txt", "md": return "text/plain; charset=utf-8"
    case "pdf": return "application/pdf"
    case "plist", "xml": return "application/xml; charset=utf-8"
    default: return "application/octet-stream"
    }
  }

  /// Injects `<meta name="crossswift-hmr" content="...">` into an HTML document's `<head>`.
  public static func injectHMRMeta(into html: String, endpoint: String) -> String {
    let existingMetaPattern = #"<meta\b[^>]*\bname\s*=\s*["']crossswift-hmr["']"#
    if html.range(of: existingMetaPattern, options: [.regularExpression, .caseInsensitive]) != nil {
      return html
    }
    let metaTag = "  <meta name=\"crossswift-hmr\" content=\"\(endpoint)\">\n"
    if let range = html.range(of: "</head>", options: .caseInsensitive) {
      var modified = html
      modified.insert(contentsOf: metaTag, at: range.lowerBound)
      return modified
    }
    return metaTag + html
  }

  #if !os(Windows)
    private func acceptLoop(listenFD: Int32) {
      while true {
        var clientAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
          ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
            accept(listenFD, sockPtr, &addrLen)
          }
        }
        if clientFD < 0 {
          if errno == EINTR { continue }
          lock.lock()
          let stillRunning = isRunning
          lock.unlock()
          if !stillRunning { break }
          continue
        }

        #if canImport(Darwin)
          var noSigPipe: Int32 = 1
          _ = setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        #endif

        clientQueue.async { [weak self] in
          self?.handleClient(fd: clientFD)
        }
      }
    }

    private func handleClient(fd: Int32) {
      guard let requestHead = readHTTPRequestHeader(from: fd) else {
        _ = close(fd)
        return
      }

      guard let firstLine = requestHead.split(separator: "\r\n", maxSplits: 1).first
        ?? requestHead.split(separator: "\n", maxSplits: 1).first
      else {
        sendSimpleResponse(fd: fd, status: "400 Bad Request", body: "Bad Request")
        _ = close(fd)
        return
      }

      let parts = firstLine.split(separator: " ")
      guard parts.count >= 2 else {
        sendSimpleResponse(fd: fd, status: "400 Bad Request", body: "Bad Request")
        _ = close(fd)
        return
      }

      let method = String(parts[0]).uppercased()
      let rawTarget = String(parts[1])

      guard method == "GET" || method == "HEAD" else {
        sendSimpleResponse(fd: fd, status: "405 Method Not Allowed", body: "Method Not Allowed")
        _ = close(fd)
        return
      }

      // Strip query string (?t=...) and fragment before resolving routes or files on disk.
      let withoutFragment = rawTarget.split(separator: "#", maxSplits: 1).first.map(String.init) ?? rawTarget
      let rawPath = withoutFragment.split(separator: "?", maxSplits: 1).first.map(String.init) ?? withoutFragment
      let decodedPath = rawPath.removingPercentEncoding ?? rawPath

      if decodedPath == configuration.hmrEndpoint {
        handleSSEClient(fd: fd)
        return
      }

      serveStaticFile(requestPath: decodedPath, headOnly: method == "HEAD", fd: fd)
      _ = close(fd)
    }

    private func handleSSEClient(fd: Int32) {
      let headers = [
        "HTTP/1.1 200 OK",
        "Content-Type: text/event-stream; charset=utf-8",
        "Cache-Control: no-cache, no-store",
        "Connection: keep-alive",
        "Access-Control-Allow-Origin: *",
        "",
        "",
      ].joined(separator: "\r\n")

      guard sendAll(fd: fd, data: Data(headers.utf8)) else {
        _ = close(fd)
        return
      }

      lock.lock()
      let initialStatus = lastStatusEvent
      if isRunning {
        sseClients.insert(fd)
      } else {
        lock.unlock()
        _ = close(fd)
        return
      }
      lock.unlock()

      var initialPayload = ": connected\n\n"
      if let initialStatus {
        initialPayload += "data: \(initialStatus.toJSON())\n\n"
      }
      if !sendAll(fd: fd, data: Data(initialPayload.utf8)) {
        removeSSEClient(fd: fd)
      }
    }

    private func removeSSEClient(fd: Int32) {
      lock.lock()
      let removed = sseClients.remove(fd) != nil
      lock.unlock()
      if removed {
        _ = close(fd)
      }
    }

    private func sendSSEFrame(_ frame: String) {
      let data = Data(frame.utf8)
      lock.lock()
      let clients = Array(sseClients)
      lock.unlock()
      guard !clients.isEmpty else { return }

      var dead: [Int32] = []
      for clientFD in clients {
        if !sendAll(fd: clientFD, data: data) {
          dead.append(clientFD)
        }
      }
      if !dead.isEmpty {
        lock.lock()
        for clientFD in dead {
          if sseClients.remove(clientFD) != nil {
            _ = close(clientFD)
          }
        }
        lock.unlock()
      }
    }

    private func serveStaticFile(requestPath: String, headOnly: Bool, fd: Int32) {
      let fm = FileManager.default
      let trimmed = requestPath.hasPrefix("/") ? String(requestPath.dropFirst()) : requestPath
      let relative = trimmed.isEmpty ? "index.html" : trimmed

      let candidate = rootDirectory.appendingPathComponent(relative).standardizedFileURL
      let rootPath = rootDirectory.path
      let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
      guard candidate.path == rootPath || candidate.path.hasPrefix(rootPrefix) else {
        sendSimpleResponse(fd: fd, status: "403 Forbidden", body: "Forbidden")
        return
      }

      var fileURL = candidate
      var isDir: ObjCBool = false
      if fm.fileExists(atPath: fileURL.path, isDirectory: &isDir), isDir.boolValue {
        fileURL = fileURL.appendingPathComponent("index.html")
      }

      guard fm.fileExists(atPath: fileURL.path, isDirectory: &isDir), !isDir.boolValue,
            var bodyData = try? Data(contentsOf: fileURL)
      else {
        sendSimpleResponse(fd: fd, status: "404 Not Found", body: "Not Found")
        return
      }

      let rootIndexURL = rootDirectory.appendingPathComponent("index.html").standardizedFileURL
      if configuration.injectHMR,
         fileURL.standardizedFileURL == rootIndexURL,
         let html = String(data: bodyData, encoding: .utf8)
      {
        let injected = Self.injectHMRMeta(into: html, endpoint: configuration.hmrEndpoint)
        bodyData = Data(injected.utf8)
      }

      let mime = Self.mimeType(forPath: fileURL.path)
      let headerText = [
        "HTTP/1.1 200 OK",
        "Content-Type: \(mime)",
        "Content-Length: \(bodyData.count)",
        "Cache-Control: no-store",
        "Connection: close",
        "",
        "",
      ].joined(separator: "\r\n")

      guard sendAll(fd: fd, data: Data(headerText.utf8)) else { return }
      if !headOnly && !bodyData.isEmpty {
        _ = sendAll(fd: fd, data: bodyData)
      }
    }

    private func sendSimpleResponse(fd: Int32, status: String, body: String) {
      let bodyData = Data(body.utf8)
      let headerText = [
        "HTTP/1.1 \(status)",
        "Content-Type: text/plain; charset=utf-8",
        "Content-Length: \(bodyData.count)",
        "Cache-Control: no-store",
        "Connection: close",
        "",
        "",
      ].joined(separator: "\r\n")
      _ = sendAll(fd: fd, data: Data(headerText.utf8))
      _ = sendAll(fd: fd, data: bodyData)
    }

    private func readHTTPRequestHeader(from fd: Int32) -> String? {
      var timeout = timeval(tv_sec: 5, tv_usec: 0)
      _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

      var buffer = Data()
      var chunk = [UInt8](repeating: 0, count: 4096)
      let terminator = Data([0x0D, 0x0A, 0x0D, 0x0A])
      let lfTerminator = Data([0x0A, 0x0A])

      while buffer.count < 65_536 {
        let n = recv(fd, &chunk, chunk.count, 0)
        if n > 0 {
          buffer.append(contentsOf: chunk[0..<n])
          if buffer.range(of: terminator) != nil || buffer.range(of: lfTerminator) != nil {
            break
          }
        } else if n == 0 {
          break
        } else {
          if errno == EINTR { continue }
          return nil
        }
      }
      guard !buffer.isEmpty else { return nil }
      return String(decoding: buffer, as: UTF8.self)
    }

    private func sendAll(fd: Int32, data: Data) -> Bool {
      #if os(Linux)
        let sendFlags = Int32(MSG_NOSIGNAL)
      #else
        let sendFlags: Int32 = 0
      #endif
      return data.withUnsafeBytes { rawBuf -> Bool in
        guard let basePtr = rawBuf.baseAddress else { return true }
        var totalSent = 0
        let count = rawBuf.count
        while totalSent < count {
          let sent = send(fd, basePtr.advanced(by: totalSent), count - totalSent, sendFlags)
          if sent > 0 {
            totalSent += sent
          } else if sent < 0 {
            let err = errno
            if err == EINTR { continue }
            if err == EAGAIN || err == EWOULDBLOCK {
              usleep(1000)
              continue
            }
            return false
          } else {
            return false
          }
        }
        return true
      }
    }
  #endif
}
