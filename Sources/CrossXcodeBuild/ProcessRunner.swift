import Foundation

public struct ProcessResult: Sendable {
  public let exitCode: Int32
  public let stdout: String
  public let stderr: String
}

public enum ProcessRunnerError: Error, LocalizedError {
  case executableNotFound(String)
  case commandFailed(command: String, exitCode: Int32, output: String)

  public var errorDescription: String? {
    switch self {
    case .executableNotFound(let name):
      return "Required executable '\(name)' was not found in PATH"
    case .commandFailed(let command, let code, let output):
      let tail = output.split(separator: "\n").suffix(40).joined(separator: "\n")
      return "Command failed (exit \(code)): \(command)\n\(tail)"
    }
  }
}

public enum ProcessRunner {
  public static func writeStdout(_ text: String) {
    guard !text.isEmpty else { return }
    try? FileHandle.standardOutput.write(contentsOf: Data(text.utf8))
  }

  public static func writeStdoutLine(_ line: String) {
    writeStdout(line + "\n")
  }

  public static func writeStderr(_ text: String) {
    guard !text.isEmpty else { return }
    try? FileHandle.standardError.write(contentsOf: Data(text.utf8))
  }

  public static func run(
    executable: URL,
    arguments: [String],
    workingDirectory: URL? = nil,
    environmentOverrides: [String: String] = [:],
    logFile: URL? = nil,
    echoOutput: Bool = false,
    onOutput: (@Sendable (Data, Bool) -> Void)? = nil
  ) throws -> ProcessResult {
    try runImpl(
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      environmentOverrides: environmentOverrides,
      logFile: logFile,
      echoOutput: echoOutput,
      onOutput: onOutput,
      postExitIdleTimeout: 2.0
    )
  }

  internal static func runImpl(
    executable: URL,
    arguments: [String],
    workingDirectory: URL? = nil,
    environmentOverrides: [String: String] = [:],
    logFile: URL? = nil,
    echoOutput: Bool = false,
    onOutput: (@Sendable (Data, Bool) -> Void)? = nil,
    postExitIdleTimeout: TimeInterval = 2.0
  ) throws -> ProcessResult {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    if let workingDirectory {
      process.currentDirectoryURL = workingDirectory
    }
    var env = ProcessInfo.processInfo.environment
    for (k, v) in environmentOverrides {
      #if os(Windows)
        for existingKey in env.keys where existingKey.caseInsensitiveCompare(k) == .orderedSame && existingKey != k {
          env.removeValue(forKey: existingKey)
        }
      #endif
      env[k] = v
    }
    process.environment = env
    process.standardInput = FileHandle.nullDevice

    let logHandle: FileHandle?
    if let logFile {
      try FileManager.default.createDirectory(
        at: logFile.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      _ = FileManager.default.createFile(atPath: logFile.path, contents: nil)
      logHandle = try FileHandle(forWritingTo: logFile)
    } else {
      logHandle = nil
    }

    final class StreamState: @unchecked Sendable {
      let lock = NSLock()
      var stdout = Data()
      var stderr = Data()
      var combined = Data()
      var logHandle: FileHandle?
      var lastActivity = Date()
      var finished = false
      let echoOutput: Bool
      let onOutput: (@Sendable (Data, Bool) -> Void)?

      init(
        logHandle: FileHandle?,
        echoOutput: Bool,
        onOutput: (@Sendable (Data, Bool) -> Void)?
      ) {
        self.logHandle = logHandle
        self.echoOutput = echoOutput
        self.onOutput = onOutput
      }

      func append(_ chunk: Data, isStderr: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        lastActivity = Date()
        if isStderr {
          stderr.append(chunk)
        } else {
          stdout.append(chunk)
        }
        if let logHandle {
          combined.append(chunk)
          try? logHandle.write(contentsOf: chunk)
        }
        if echoOutput {
          let target = isStderr ? FileHandle.standardError : FileHandle.standardOutput
          try? target.write(contentsOf: chunk)
        }
        onOutput?(chunk, isStderr)
      }

      func markProcessExited() {
        lock.lock()
        lastActivity = Date()
        lock.unlock()
      }

      func secondsSinceLastActivity() -> TimeInterval {
        lock.lock()
        let elapsed = Date().timeIntervalSince(lastActivity)
        lock.unlock()
        return elapsed
      }

      func finish() -> (stdout: Data, stderr: Data, combined: Data) {
        lock.lock()
        defer { lock.unlock() }
        finished = true
        try? logHandle?.close()
        logHandle = nil
        return (stdout, stderr, combined)
      }
    }

    let state = StreamState(
      logHandle: logHandle,
      echoOutput: echoOutput,
      onOutput: onOutput
    )
    defer { _ = state.finish() }

    let outPipe = Pipe()
    let errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe
    try process.run()

    let group = DispatchGroup()
    func drain(_ handle: FileHandle, isStderr: Bool) {
      group.enter()
      DispatchQueue.global().async {
        defer { group.leave() }
        while true {
          let chunk = readAvailableData(from: handle)
          if chunk.isEmpty { break }
          state.append(chunk, isStderr: isStderr)
        }
      }
    }

    drain(outPipe.fileHandleForReading, isStderr: false)
    drain(errPipe.fileHandleForReading, isStderr: true)

    process.waitUntilExit()
    state.markProcessExited()
    while group.wait(timeout: .now() + .milliseconds(50)) == .timedOut {
      if state.secondsSinceLastActivity() >= postExitIdleTimeout {
        break
      }
    }

    let captured = state.finish()
    if logFile != nil {
      let combined = String(decoding: captured.combined, as: UTF8.self)
      return ProcessResult(exitCode: process.terminationStatus, stdout: combined, stderr: "")
    }

    let stdout = String(decoding: captured.stdout, as: UTF8.self)
    let stderr = String(decoding: captured.stderr, as: UTF8.self)
    return ProcessResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
  }

  private static func readAvailableData(from handle: FileHandle) -> Data {
    #if canImport(ObjectiveC)
      return autoreleasepool { handle.availableData }
    #else
      return handle.availableData
    #endif
  }

  public static func environmentValue(_ key: String) -> String? {
    let env = ProcessInfo.processInfo.environment
    if let exact = env[key] { return exact }
    #if os(Windows)
      return env.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    #else
      return nil
    #endif
  }

  public static func findExecutable(
    named candidates: [String],
    extraDirectories: [URL] = []
  ) -> URL? {
    let fm = FileManager.default
    let pathEnv = environmentValue("PATH") ?? ""
    #if os(Windows)
      let separator: Character = ";"
      let pathExts = ["", ".exe", ".cmd", ".bat"]
    #else
      let separator: Character = ":"
      let pathExts = [""]
    #endif

    let searchDirs = extraDirectories + pathEnv.split(separator: separator).map {
      URL(fileURLWithPath: String($0))
    }

    for name in candidates {
      if name.contains("/") || name.contains("\\") {
        let direct = URL(fileURLWithPath: name)
        if fm.isExecutableFile(atPath: direct.path) || fm.fileExists(atPath: direct.path) {
          return direct
        }
      }
      for dir in searchDirs {
        for ext in pathExts {
          let fileName = (ext.isEmpty || name.lowercased().hasSuffix(ext)) ? name : name + ext
          let candidate = dir.appendingPathComponent(fileName)
          #if os(Windows)
            if fm.fileExists(atPath: candidate.path) {
              return candidate
            }
          #else
            if fm.isExecutableFile(atPath: candidate.path) {
              return candidate
            }
          #endif
        }
      }
    }
    return nil
  }

  public static func fnv1aHex(_ input: String) -> String {
    var hash: UInt64 = 14695981039346656037
    for byte in input.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 1099511628211
    }
    return String(format: "%08x", UInt32(truncatingIfNeeded: hash))
  }

  public static func sanitizedSlug(_ name: String) -> String {
    let chars = name.unicodeScalars.map { s -> Character in
      if CharacterSet.alphanumerics.contains(s) { return Character(s) }
      return "-"
    }
    let collapsed = String(chars).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return collapsed.isEmpty ? "app" : collapsed
  }
}
