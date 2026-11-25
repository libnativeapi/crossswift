import Foundation
import XCTest

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

@testable import CrossXcodeBuild

final class WasmHotReloadTests: XCTestCase {
  func testWriteIfChangedPreservesMtimeWhenUnchangedAndUpdatesWhenChanged() throws {
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appendingPathComponent("crossswift-wic-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let fileURL = tmp.appendingPathComponent("Generated.swift")
    let wroteFirst = try IncrementalFileWriter.writeIfChanged(text: "let x = 1\n", to: fileURL)
    XCTAssertTrue(wroteFirst)

    // Backdate mtime so any rewrite is unambiguously distinguishable even on 1-second filesystems.
    let pastDate = Date(timeIntervalSince1970: 1_700_000_000)
    try fm.setAttributes([.modificationDate: pastDate], ofItemAtPath: fileURL.path)
    let mtimeBefore = try fm.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date
    XCTAssertEqual(mtimeBefore, pastDate)

    // Writing identical content must be a no-op and preserve mtime.
    let wroteSame = try IncrementalFileWriter.writeIfChanged(text: "let x = 1\n", to: fileURL)
    XCTAssertFalse(wroteSame)
    let mtimeAfterSame = try fm.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date
    XCTAssertEqual(mtimeAfterSame, pastDate)

    // Writing modified content must update both content and mtime.
    let wroteChanged = try IncrementalFileWriter.writeIfChanged(text: "let x = 2\n", to: fileURL)
    XCTAssertTrue(wroteChanged)
    let mtimeAfterChange = try XCTUnwrap(
      fm.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date
    )
    XCTAssertGreaterThan(mtimeAfterChange, pastDate)
    XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "let x = 2\n")
  }

  func testSyncDirectoryPreservesExcludedEntriesAndPrunesStaleFiles() throws {
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appendingPathComponent("crossswift-syncdir-\(UUID().uuidString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let src = tmp.appendingPathComponent("src")
    let dst = tmp.appendingPathComponent("dst")
    try fm.createDirectory(at: src, withIntermediateDirectories: true)
    try fm.createDirectory(at: dst.appendingPathComponent("node_modules/pkg"), withIntermediateDirectories: true)

    try "console.log('v1')".write(to: src.appendingPathComponent("index.js"), atomically: true, encoding: .utf8)
    try "keep-me".write(
      to: dst.appendingPathComponent("node_modules/pkg/index.js"),
      atomically: true,
      encoding: .utf8
    )
    try "stale".write(to: dst.appendingPathComponent("old.js"), atomically: true, encoding: .utf8)

    try IncrementalFileWriter.syncDirectory(from: src, to: dst, excluding: ["node_modules"])

    XCTAssertTrue(fm.fileExists(atPath: dst.appendingPathComponent("node_modules/pkg/index.js").path))
    XCTAssertFalse(fm.fileExists(atPath: dst.appendingPathComponent("old.js").path))
    XCTAssertEqual(
      try String(contentsOf: dst.appendingPathComponent("index.js"), encoding: .utf8),
      "console.log('v1')"
    )

    // Backdate synced file and verify unchanged sync preserves mtime.
    let pastDate = Date(timeIntervalSince1970: 1_700_000_000)
    let dstIndex = dst.appendingPathComponent("index.js")
    try fm.setAttributes([.modificationDate: pastDate], ofItemAtPath: dstIndex.path)
    try IncrementalFileWriter.syncDirectory(from: src, to: dst, excluding: ["node_modules"])
    let mtimeAfter = try fm.attributesOfItem(atPath: dstIndex.path)[.modificationDate] as? Date
    XCTAssertEqual(mtimeAfter, pastDate)
  }

  func testProjectChangeClassifierDistinguishesSwiftResourcesConfigAndIgnored() {
    XCTAssertEqual(
      ProjectChangeClassifier.classify(path: "/repo/App/ContentView.swift"),
      .swiftSource
    )
    XCTAssertEqual(
      ProjectChangeClassifier.classify(path: "/repo/App/Helper.c"),
      .swiftSource
    )
    XCTAssertEqual(
      ProjectChangeClassifier.classify(path: "/repo/App/Localizable.xcstrings"),
      .resourceOnly
    )
    XCTAssertEqual(
      ProjectChangeClassifier.classify(path: "/repo/App/Assets.xcassets/HeroBadge.imageset/badge.svg"),
      .resourceOnly
    )
    XCTAssertEqual(
      ProjectChangeClassifier.classify(path: "/repo/App/Assets.xcassets/BrandAccent.colorset/Contents.json"),
      .resourceOnly
    )
    XCTAssertEqual(
      ProjectChangeClassifier.classify(path: "/repo/App/en.lproj/Localizable.strings"),
      .resourceOnly
    )
    XCTAssertEqual(
      ProjectChangeClassifier.classify(path: "/repo/App/Info.plist"),
      .resourceOnly
    )
    XCTAssertEqual(
      ProjectChangeClassifier.classify(path: "/repo/App.xcodeproj/project.pbxproj"),
      .projectConfig
    )
    XCTAssertEqual(
      ProjectChangeClassifier.classify(path: "/repo/App.xcodeproj/project.xcproj"),
      .projectConfig
    )
    XCTAssertEqual(
      ProjectChangeClassifier.classify(path: "/repo/Config/Debug.xcconfig"),
      .projectConfig
    )
    XCTAssertEqual(
      ProjectChangeClassifier.classify(path: "/repo/Package.swift"),
      .projectConfig
    )

    // Ignored files and build directories
    XCTAssertEqual(ProjectChangeClassifier.classify(path: "/repo/.git/HEAD"), .ignored)
    XCTAssertEqual(ProjectChangeClassifier.classify(path: "/repo/.build/debug/App.wasm"), .ignored)
    XCTAssertEqual(ProjectChangeClassifier.classify(path: "/repo/build/Build/Products/Debug/App/index.html"), .ignored)
    XCTAssertEqual(ProjectChangeClassifier.classify(path: "/repo/node_modules/pkg/index.js"), .ignored)
    XCTAssertEqual(ProjectChangeClassifier.classify(path: "/repo/App/.DS_Store"), .ignored)
    XCTAssertEqual(ProjectChangeClassifier.classify(path: "/repo/App/ContentView.swift.swp"), .ignored)
    XCTAssertEqual(ProjectChangeClassifier.classify(path: "/repo/App/ContentView.swift~"), .ignored)
    XCTAssertEqual(
      ProjectChangeClassifier.classify(path: "/repo/App.xcodeproj/project.xcworkspace/xcuserdata/me.xcuserdatad/UserInterfaceState.xcuserstate"),
      .ignored
    )

    // Batch severity precedence: projectConfig > swiftSource > resourceOnly > ignored
    XCTAssertEqual(
      ProjectChangeClassifier.classify(paths: [
        "/repo/App/.DS_Store",
        "/repo/App/Localizable.xcstrings",
      ]),
      .resourceOnly
    )
    XCTAssertEqual(
      ProjectChangeClassifier.classify(paths: [
        "/repo/App/Localizable.xcstrings",
        "/repo/App/ContentView.swift",
      ]),
      .swiftSource
    )
    XCTAssertEqual(
      ProjectChangeClassifier.classify(paths: [
        "/repo/App/ContentView.swift",
        "/repo/App.xcodeproj/project.pbxproj",
      ]),
      .projectConfig
    )
  }

  func testProjectFileWatcherDetectsChangesAndIgnoresExcludedDirectories() throws {
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appendingPathComponent("crossswift-watch-\(UUID().uuidString)")
    let srcDir = tmp.appendingPathComponent("App")
    let excludedDir = tmp.appendingPathComponent("custom-derived")
    try fm.createDirectory(at: srcDir, withIntermediateDirectories: true)
    try fm.createDirectory(at: excludedDir, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let swiftFile = srcDir.appendingPathComponent("ContentView.swift")
    try "struct ContentView {}".write(to: swiftFile, atomically: true, encoding: .utf8)

    final class Box: @unchecked Sendable {
      let lock = NSLock()
      var batches: [ProjectChangeBatch] = []
      let sem = DispatchSemaphore(value: 0)
    }
    let box = Box()

    let watcher = ProjectFileWatcher(
      roots: [tmp],
      excludedDirectories: [excludedDir],
      pollInterval: 0.05,
      debounceInterval: 0.05
    ) { batch in
      box.lock.lock()
      box.batches.append(batch)
      box.lock.unlock()
      box.sem.signal()
    }
    watcher.start()
    defer { watcher.stop() }

    // Write into excluded dir — should NOT trigger a batch.
    try "let ignored = 1".write(
      to: excludedDir.appendingPathComponent("Excluded.swift"),
      atomically: true,
      encoding: .utf8
    )

    // Modify watched Swift file — should trigger a .swiftSource batch.
    Thread.sleep(forTimeInterval: 0.08)
    try "struct ContentView { let v = 2 }".write(to: swiftFile, atomically: true, encoding: .utf8)

    let waitResult = box.sem.wait(timeout: .now() + .seconds(3))
    XCTAssertEqual(waitResult, .success)

    box.lock.lock()
    let received = box.batches
    box.lock.unlock()
    XCTAssertFalse(received.isEmpty)
    XCTAssertEqual(received.first?.kind, .swiftSource)
    XCTAssertTrue(received.first?.changedPaths.contains(swiftFile.standardizedFileURL.path) == true)
    XCTAssertFalse(received.flatMap(\.changedPaths).contains { $0.contains("custom-derived") })
  }

  func testCLIParserSupportsDevActionWatchPortAndHostFlags() throws {
    let demoDir = FileManager.default.temporaryDirectory
    let devOutcome = try XcodeBuildCLIParser.parse(
      arguments: [
        "-destination", "generic/platform=Wasm",
        "--port", "9090",
        "--host", "0.0.0.0",
        "dev",
      ],
      currentDirectory: demoDir
    )
    guard case .run(let devOpts) = devOutcome else {
      XCTFail("Expected .run")
      return
    }
    XCTAssertEqual(devOpts.mode, .actions([.dev]))
    XCTAssertEqual(devOpts.devPort, 9090)
    XCTAssertEqual(devOpts.devHost, "0.0.0.0")
    XCTAssertEqual(devOpts.destination, "generic/platform=Wasm")

    let watchOutcome = try XcodeBuildCLIParser.parse(
      arguments: [
        "-destination", "generic/platform=Wasm",
        "--watch",
        "-port", "8123",
      ],
      currentDirectory: demoDir
    )
    guard case .run(let watchOpts) = watchOutcome else {
      XCTFail("Expected .run")
      return
    }
    XCTAssertTrue(watchOpts.watch)
    XCTAssertEqual(watchOpts.mode, .actions([.dev]))
    XCTAssertEqual(watchOpts.devPort, 8123)
    XCTAssertEqual(watchOpts.devHost, "127.0.0.1")

    let serveAliasOutcome = try XcodeBuildCLIParser.parse(
      arguments: ["-destination", "generic/platform=Wasm", "serve"],
      currentDirectory: demoDir
    )
    guard case .run(let serveOpts) = serveAliasOutcome else {
      XCTFail("Expected .run")
      return
    }
    XCTAssertEqual(serveOpts.mode, .actions([.dev]))

    XCTAssertThrowsError(
      try XcodeBuildCLIParser.parse(arguments: ["--port", "not-a-number"], currentDirectory: demoDir)
    )
  }

  #if !os(Windows)
    func testWasmDevServerStaticMimeTypesNoStoreHMRInjectionAndSSEBroadcast() throws {
      let fm = FileManager.default
      let tmp = fm.temporaryDirectory.appendingPathComponent("crossswift-devsrv-\(UUID().uuidString)")
      try fm.createDirectory(at: tmp.appendingPathComponent("app"), withIntermediateDirectories: true)
      try fm.createDirectory(at: tmp.appendingPathComponent("Resources"), withIntermediateDirectories: true)
      defer { try? fm.removeItem(at: tmp) }

      let indexHTML = """
      <!doctype html>
      <html>
      <head>
        <title>TestApp</title>
      </head>
      <body>
        <main id="swiftui-root"></main>
        <script type="module">
          const hmr = document.querySelector('meta[name="crossswift-hmr"]')?.getAttribute("content");
        </script>
      </body>
      </html>
      """
      try indexHTML.write(to: tmp.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
      try Data([0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00]).write(
        to: tmp.appendingPathComponent("app/App.wasm")
      )
      try "export function init() {}".write(
        to: tmp.appendingPathComponent("app/index.js"),
        atomically: true,
        encoding: .utf8
      )
      try "{\"images\":{},\"xcstrings\":[]}".write(
        to: tmp.appendingPathComponent("Resources/web-manifest.json"),
        atomically: true,
        encoding: .utf8
      )
      try "<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>".write(
        to: tmp.appendingPathComponent("Resources/badge.svg"),
        atomically: true,
        encoding: .utf8
      )

      let server = WasmDevServer(
        rootDirectory: tmp,
        configuration: WasmDevServerConfiguration(host: "127.0.0.1", port: 0)
      )
      try server.start()
      defer { server.stop() }
      XCTAssertGreaterThan(server.boundPort, 0)

      // 1. Root index.html gets HMR meta injected and Cache-Control: no-store
      let indexResp = try httpGet(port: server.boundPort, path: "/")
      XCTAssertEqual(indexResp.statusCode, 200)
      XCTAssertEqual(indexResp.headers["content-type"], "text/html; charset=utf-8")
      XCTAssertEqual(indexResp.headers["cache-control"], "no-store")
      let indexBody = String(decoding: indexResp.body, as: UTF8.self)
      XCTAssertTrue(indexBody.contains("<meta name=\"crossswift-hmr\" content=\"/__crossswift_hmr\">"))
      // Verify file on disk was NOT mutated
      let onDiskHTML = try String(contentsOf: tmp.appendingPathComponent("index.html"), encoding: .utf8)
      XCTAssertFalse(onDiskHTML.contains("<meta name=\"crossswift-hmr\""))

      // Calling injectHMRMeta a second time on already-injected HTML must be idempotent
      let injectedOnce = WasmDevServer.injectHMRMeta(into: indexHTML, endpoint: "/__crossswift_hmr")
      let injectedTwice = WasmDevServer.injectHMRMeta(into: injectedOnce, endpoint: "/__crossswift_hmr")
      XCTAssertTrue(injectedOnce.contains("<meta name=\"crossswift-hmr\" content=\"/__crossswift_hmr\">"))
      XCTAssertEqual(injectedOnce, injectedTwice)

      // 2. .wasm with query-string cache-buster returns application/wasm + exact bytes
      let wasmResp = try httpGet(port: server.boundPort, path: "/app/App.wasm?t=42")
      XCTAssertEqual(wasmResp.statusCode, 200)
      XCTAssertEqual(wasmResp.headers["content-type"], "application/wasm")
      XCTAssertEqual(wasmResp.headers["cache-control"], "no-store")
      XCTAssertEqual(wasmResp.body, Data([0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00]))

      // 3. .js, .json, .svg MIME types
      let jsResp = try httpGet(port: server.boundPort, path: "/app/index.js?t=7")
      XCTAssertEqual(jsResp.statusCode, 200)
      XCTAssertEqual(jsResp.headers["content-type"], "text/javascript; charset=utf-8")

      let jsonResp = try httpGet(port: server.boundPort, path: "/Resources/web-manifest.json?t=7")
      XCTAssertEqual(jsonResp.statusCode, 200)
      XCTAssertEqual(jsonResp.headers["content-type"], "application/json; charset=utf-8")

      let svgResp = try httpGet(port: server.boundPort, path: "/Resources/badge.svg")
      XCTAssertEqual(svgResp.statusCode, 200)
      XCTAssertEqual(svgResp.headers["content-type"], "image/svg+xml")

      // 4. 404 for missing file and 403 for path traversal
      let missingResp = try httpGet(port: server.boundPort, path: "/does-not-exist.wasm")
      XCTAssertEqual(missingResp.statusCode, 404)
      let traversalResp = try httpGet(port: server.boundPort, path: "/../../etc/passwd")
      XCTAssertEqual(traversalResp.statusCode, 403)

      // 5. SSE endpoint receives initial status + broadcast resources, error, and wasm events
      server.broadcast(.status(state: "ready", message: nil))
      let sseFD = try openRawSocket(port: server.boundPort)
      defer { _ = close(sseFD) }

      let req = "GET /__crossswift_hmr HTTP/1.1\r\nHost: 127.0.0.1\r\nAccept: text/event-stream\r\n\r\n"
      _ = req.withCString { ptr in
        send(sseFD, ptr, strlen(ptr), 0)
      }

      // Wait briefly for server to register SSE client and send headers + initial status.
      let deadline = Date().addingTimeInterval(2.0)
      while server.connectedSSEClientCount == 0 && Date() < deadline {
        Thread.sleep(forTimeInterval: 0.02)
      }
      XCTAssertEqual(server.connectedSSEClientCount, 1)

      server.broadcast(.status(state: "building", message: "Rebuilding Wasm..."))
      server.broadcast(.resources(version: 2))
      server.broadcast(.wasm(version: 3))
      server.broadcast(.status(state: "error", message: "ContentView.swift:12: error: expected '}'"))

      let sseOutput = readAvailableText(from: sseFD, timeoutSeconds: 1.5, expectedSubstring: "\"state\":\"error\"")
      XCTAssertTrue(sseOutput.contains("Content-Type: text/event-stream; charset=utf-8"))
      XCTAssertTrue(sseOutput.contains("Cache-Control: no-cache, no-store"))
      XCTAssertTrue(sseOutput.contains("data: {\"state\":\"ready\",\"type\":\"status\"}\n\n"))
      XCTAssertTrue(sseOutput.contains("data: {\"message\":\"Rebuilding Wasm...\",\"state\":\"building\",\"type\":\"status\"}\n\n"))
      XCTAssertTrue(sseOutput.contains("data: {\"type\":\"resources\",\"version\":2}\n\n"))
      XCTAssertTrue(sseOutput.contains("data: {\"type\":\"wasm\",\"version\":3}\n\n"))
      XCTAssertTrue(sseOutput.contains("ContentView.swift:12: error: expected '}'"))
    }

    private struct RawHTTPResponse {
      let statusCode: Int
      let headers: [String: String]
      let body: Data
    }

    private func openRawSocket(port: UInt16) throws -> Int32 {
      #if os(Linux)
        let sockType = Int32(SOCK_STREAM.rawValue)
      #else
        let sockType = SOCK_STREAM
      #endif
      let fd = socket(AF_INET, sockType, 0)
      XCTAssertGreaterThanOrEqual(fd, 0)

      var addr = sockaddr_in()
      #if canImport(Darwin)
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
      #endif
      addr.sin_family = sa_family_t(AF_INET)
      addr.sin_port = port.bigEndian
      var ip = in_addr()
      _ = "127.0.0.1".withCString { inet_pton(AF_INET, $0, &ip) }
      addr.sin_addr = ip

      let res = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
          connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
      }
      if res != 0 {
        _ = close(fd)
        throw NSError(domain: "WasmHotReloadTests", code: Int(errno))
      }
      return fd
    }

    private func httpGet(port: UInt16, path: String) throws -> RawHTTPResponse {
      let fd = try openRawSocket(port: port)
      defer { _ = close(fd) }

      var tv = timeval(tv_sec: 3, tv_usec: 0)
      _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

      let request = "GET \(path) HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\nConnection: close\r\n\r\n"
      _ = request.withCString { ptr in
        send(fd, ptr, strlen(ptr), 0)
      }

      var raw = Data()
      var buf = [UInt8](repeating: 0, count: 8192)
      while true {
        let n = recv(fd, &buf, buf.count, 0)
        if n > 0 {
          raw.append(contentsOf: buf[0..<n])
        } else {
          break
        }
      }

      let sep = Data([0x0D, 0x0A, 0x0D, 0x0A])
      guard let range = raw.range(of: sep) else {
        XCTFail("Malformed HTTP response: \(String(decoding: raw, as: UTF8.self))")
        return RawHTTPResponse(statusCode: 0, headers: [:], body: Data())
      }
      let headText = String(decoding: raw[..<range.lowerBound], as: UTF8.self)
      let body = Data(raw[range.upperBound...])
      let lines = headText.components(separatedBy: "\r\n")
      let statusParts = (lines.first ?? "").split(separator: " ")
      let statusCode = statusParts.count >= 2 ? (Int(statusParts[1]) ?? 0) : 0
      var headers: [String: String] = [:]
      for line in lines.dropFirst() {
        if let colon = line.firstIndex(of: ":") {
          let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
          let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
          headers[key] = value
        }
      }
      return RawHTTPResponse(statusCode: statusCode, headers: headers, body: body)
    }

    private func readAvailableText(
      from fd: Int32,
      timeoutSeconds: TimeInterval,
      expectedSubstring: String
    ) -> String {
      var tv = timeval(tv_sec: 0, tv_usec: 200_000)
      _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

      let deadline = Date().addingTimeInterval(timeoutSeconds)
      var collected = Data()
      var buf = [UInt8](repeating: 0, count: 4096)
      while Date() < deadline {
        let n = recv(fd, &buf, buf.count, 0)
        if n > 0 {
          collected.append(contentsOf: buf[0..<n])
          let text = String(decoding: collected, as: UTF8.self)
          if text.contains(expectedSubstring) {
            return text
          }
        }
      }
      return String(decoding: collected, as: UTF8.self)
    }
  #endif
}
