import Foundation

#if !os(Windows) && canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// Orchestrates incremental Wasm builds, fast resource-only updates, file watching,
/// and the local HTTP + SSE dev server for stateful SwiftUI Wasm hot reload.
public final class WasmDevSession: @unchecked Sendable {
  public let projectURL: URL
  public let configuration: BuildConfiguration
  public let options: XcodeBuildOptions
  public let serverConfiguration: WasmDevServerConfiguration

  private let loader = XcodeProjectLoader()
  private let buildBackend = SwiftPMBackend()
  private let stager = ApplicationStager()
  private let assetCompiler = AssetAndIconCompiler()

  private let stateLock = NSLock()
  private var isRunning = false
  private var isBuilding = false
  private var pendingKind: ProjectChangeKind = .ignored
  private var pendingPaths = Set<String>()
  private var version: Int = 0

  private var currentProject: ResolvedXcodeProject?
  private var currentBuilt: BuiltTargetArtifacts?
  private var currentStaged: StagedApplication?
  private var derivedDataURL: URL?
  private var builtProductsDir: URL?

  public private(set) var server: WasmDevServer?
  private var watcher: ProjectFileWatcher?
  private let rebuildQueue = DispatchQueue(label: "dev.crossswift.wasmdev.rebuild", qos: .userInitiated)

  public init(
    projectURL: URL,
    configuration: BuildConfiguration = .debug,
    options: XcodeBuildOptions,
    serverConfiguration: WasmDevServerConfiguration = WasmDevServerConfiguration()
  ) {
    self.projectURL = projectURL.standardizedFileURL
    self.configuration = configuration
    self.options = options
    self.serverConfiguration = serverConfiguration
  }

  deinit {
    stop()
  }

  /// Performs the initial build, stages the Wasm app, starts the HTTP/SSE dev server,
  /// and begins watching project files for incremental rebuilds.
  @discardableResult
  public func start() throws -> StagedApplication {
    let initialStart = Date()
    let project = try loader.load(
      from: projectURL,
      configuration: configuration,
      targetName: options.targetName,
      schemeName: options.schemeName,
      buildSettingOverrides: options.buildSettingOverrides
    )
    let derivedData = XcodeBuildDriver.resolveDerivedDataURL(
      options: options,
      projectRootURL: project.projectRootURL
    )
    let effectiveSettings = XcodeBuildDriver.computeEffectiveBuildSettings(
      project: project,
      platform: .wasm,
      derivedDataURL: derivedData
    )
    let productsDir = URL(
      fileURLWithPath: effectiveSettings["BUILT_PRODUCTS_DIR"]
        ?? derivedData.appendingPathComponent("Build/Products/\(configuration.rawValue)").path
    ).standardizedFileURL

    if !options.quiet {
      ProcessRunner.writeStdoutLine(
        "[hot-reload] Building \(project.mainTarget.name) (\(configuration.rawValue), wasm)..."
      )
    }

    let built = try buildBackend.build(
      project: project,
      platform: .wasm,
      configuration: configuration,
      derivedDataURL: derivedData,
      options: options
    )
    let staged = try stager.stage(
      project: project,
      built: built,
      builtProductsDirectory: productsDir,
      quiet: options.quiet
    )
    let elapsed = Date().timeIntervalSince(initialStart)

    let devServer = WasmDevServer(
      rootDirectory: staged.appBundleDirectory,
      configuration: serverConfiguration
    )
    try devServer.start()
    devServer.broadcast(.status(state: "ready", message: nil))

    let watchRoots = Self.computeWatchRoots(project: project)
    var excludedDirs: [URL] = [
      derivedData,
      built.buildDirectory,
      staged.stageRootDirectory,
    ]
    if let explicitScratch = options.scratchDirectory {
      excludedDirs.append(explicitScratch)
    }

    let fileWatcher = ProjectFileWatcher(
      roots: watchRoots,
      excludedDirectories: excludedDirs
    ) { [weak self] batch in
      self?.handleFileChanges(batch)
    }

    stateLock.lock()
    self.isRunning = true
    self.currentProject = project
    self.currentBuilt = built
    self.currentStaged = staged
    self.derivedDataURL = derivedData
    self.builtProductsDir = productsDir
    self.server = devServer
    self.watcher = fileWatcher
    stateLock.unlock()

    fileWatcher.start()

    if !options.quiet {
      ProcessRunner.writeStdoutLine("[hot-reload] Built wasm in \(Self.formatDuration(elapsed))")
      ProcessRunner.writeStdoutLine("[hot-reload] Serving \(staged.appName) at \(devServer.baseURL)")
      ProcessRunner.writeStdoutLine("[hot-reload] Watching \(project.projectRootURL.path) for changes (Ctrl-C to stop)")
    }

    return staged
  }

  public func stop() {
    stateLock.lock()
    isRunning = false
    pendingKind = .ignored
    pendingPaths.removeAll()
    let activeWatcher = watcher
    watcher = nil
    let activeServer = server
    server = nil
    stateLock.unlock()

    activeWatcher?.stop()
    activeServer?.stop()
  }

  /// Starts the dev session and blocks until SIGINT or SIGTERM is received.
  public func runUntilInterrupted() throws {
    _ = try start()

    #if os(Windows)
      RunLoop.main.run()
    #else
      let semaphore = DispatchSemaphore(value: 0)
      signal(SIGINT, SIG_IGN)
      signal(SIGTERM, SIG_IGN)

      let sigIntSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
      let sigTermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
      let finish: () -> Void = {
        semaphore.signal()
      }
      sigIntSource.setEventHandler(handler: finish)
      sigTermSource.setEventHandler(handler: finish)
      sigIntSource.resume()
      sigTermSource.resume()

      semaphore.wait()
      sigIntSource.cancel()
      sigTermSource.cancel()

      if !options.quiet {
        ProcessRunner.writeStdoutLine("\n[hot-reload] Shutting down dev server...")
      }
      stop()
    #endif
  }

  private func handleFileChanges(_ batch: ProjectChangeBatch) {
    guard batch.kind != .ignored else { return }

    var shouldSchedule = false
    stateLock.lock()
    guard isRunning else {
      stateLock.unlock()
      return
    }
    if batch.kind > pendingKind {
      pendingKind = batch.kind
    }
    pendingPaths.formUnion(batch.changedPaths)
    if !isBuilding {
      isBuilding = true
      shouldSchedule = true
    }
    stateLock.unlock()

    if shouldSchedule {
      rebuildQueue.async { [weak self] in
        self?.drainRebuildQueue()
      }
    }
  }

  private func drainRebuildQueue() {
    while true {
      stateLock.lock()
      guard isRunning else {
        isBuilding = false
        pendingKind = .ignored
        pendingPaths.removeAll()
        stateLock.unlock()
        return
      }
      let kind = pendingKind
      let paths = Array(pendingPaths).sorted()
      pendingKind = .ignored
      pendingPaths.removeAll()
      if kind == .ignored {
        isBuilding = false
        stateLock.unlock()
        return
      }
      let activeServer = server
      let project = currentProject
      let built = currentBuilt
      let staged = currentStaged
      let derivedData = derivedDataURL
      let productsDir = builtProductsDir
      stateLock.unlock()

      guard let activeServer, let project, let built, let staged, let derivedData, let productsDir else {
        continue
      }

      if kind == .resourceOnly {
        let didFastRefresh = performResourceOnlyRefresh(
          changedPaths: paths,
          project: project,
          built: built,
          staged: staged,
          server: activeServer
        )
        if didFastRefresh {
          continue
        }
        // Asset symbols changed -> fall through to incremental Wasm rebuild.
      }

      performIncrementalWasmRebuild(
        changedPaths: paths,
        derivedData: derivedData,
        builtProductsDir: productsDir,
        server: activeServer
      )
    }
  }

  /// Returns `true` if resources were refreshed without needing Wasm recompilation,
  /// or `false` if generated Swift asset symbols changed and a Wasm rebuild is required.
  private func performResourceOnlyRefresh(
    changedPaths: [String],
    project: ResolvedXcodeProject,
    built: BuiltTargetArtifacts,
    staged: StagedApplication,
    server: WasmDevServer
  ) -> Bool {
    let start = Date()
    server.broadcast(.status(state: "building", message: "Updating resources..."))
    do {
      let reloadedProject = try loader.load(
        from: projectURL,
        configuration: configuration,
        targetName: options.targetName,
        schemeName: options.schemeName,
        buildSettingOverrides: options.buildSettingOverrides
      )
      let assetsStaging = built.buildDirectory.appendingPathComponent("AssetsStaging")
      let compiledAssets = try assetCompiler.compile(project: reloadedProject, stagingRoot: assetsStaging)

      // Check whether GeneratedAssetSymbols.swift changed (e.g. colorset RGB or new symbol).
      let stagedSymbolsURL = built.buildDirectory
        .appendingPathComponent("Sources")
        .appendingPathComponent(reloadedProject.mainTarget.name)
        .appendingPathComponent("GeneratedAssetSymbols.swift")
      let existingSymbols = try? Data(contentsOf: stagedSymbolsURL)
      let newSymbols = compiledAssets.generatedSymbolsSwiftURL.flatMap { try? Data(contentsOf: $0) }
      if existingSymbols != newSymbols {
        if !options.quiet {
          ProcessRunner.writeStdoutLine("[hot-reload] Asset symbols changed; triggering incremental wasm rebuild...")
        }
        return false
      }

      try stager.stageWasmResourcesOnly(
        project: reloadedProject,
        compiledAssets: compiledAssets,
        adaptedPackageDirectories: built.adaptedRemotePackageDirectories,
        resourcesDestURL: staged.resourcesDirectory
      )

      let nextVersion = incrementVersion()
      stateLock.lock()
      self.currentProject = reloadedProject
      stateLock.unlock()

      let elapsed = Date().timeIntervalSince(start)
      server.broadcast(.resources(version: nextVersion))
      server.broadcast(.status(state: "ready", message: nil))

      if !options.quiet {
        let summary = Self.summarizeChangedFiles(changedPaths, relativeTo: reloadedProject.projectRootURL)
        ProcessRunner.writeStdoutLine(
          "[hot-reload] Updated resources in \(Self.formatDuration(elapsed)) (\(summary))"
        )
      }
      return true
    } catch {
      let message = Self.formatDiagnostics(from: error)
      server.broadcast(.status(state: "error", message: message))
      ProcessRunner.writeStderr("[hot-reload] Resource update failed:\n\(message)\n")
      return true
    }
  }

  private func performIncrementalWasmRebuild(
    changedPaths: [String],
    derivedData: URL,
    builtProductsDir: URL,
    server: WasmDevServer
  ) {
    let start = Date()
    server.broadcast(.status(state: "building", message: "Rebuilding Wasm..."))
    do {
      let reloadedProject = try loader.load(
        from: projectURL,
        configuration: configuration,
        targetName: options.targetName,
        schemeName: options.schemeName,
        buildSettingOverrides: options.buildSettingOverrides
      )
      var quietBuildOptions = options
      quietBuildOptions.quiet = true

      let built = try buildBackend.build(
        project: reloadedProject,
        platform: .wasm,
        configuration: configuration,
        derivedDataURL: derivedData,
        options: quietBuildOptions
      )
      let staged = try stager.stage(
        project: reloadedProject,
        built: built,
        builtProductsDirectory: builtProductsDir,
        quiet: true
      )

      let nextVersion = incrementVersion()
      stateLock.lock()
      self.currentProject = reloadedProject
      self.currentBuilt = built
      self.currentStaged = staged
      stateLock.unlock()

      let elapsed = Date().timeIntervalSince(start)
      server.broadcast(.wasm(version: nextVersion))
      server.broadcast(.status(state: "ready", message: nil))

      if !options.quiet {
        let summary = Self.summarizeChangedFiles(changedPaths, relativeTo: reloadedProject.projectRootURL)
        ProcessRunner.writeStdoutLine(
          "[hot-reload] Built wasm in \(Self.formatDuration(elapsed)) (\(summary))"
        )
      }
    } catch {
      let message = Self.formatDiagnostics(from: error)
      server.broadcast(.status(state: "error", message: message))
      ProcessRunner.writeStderr("[hot-reload] Build failed:\n\(message)\n")
    }
  }

  private func incrementVersion() -> Int {
    stateLock.lock()
    defer { stateLock.unlock() }
    version += 1
    return version
  }

  private static func computeWatchRoots(project: ResolvedXcodeProject) -> [URL] {
    var roots: [URL] = [project.projectRootURL.standardizedFileURL]
    for pkg in project.localPackages {
      roots.append(pkg.path.standardizedFileURL)
    }
    // Deduplicate nested paths (e.g. local package already inside projectRootURL).
    let sorted = roots.sorted { $0.path.count < $1.path.count }
    var unique: [URL] = []
    for candidate in sorted {
      let candPath = candidate.path
      let covered = unique.contains { existing in
        let prefix = existing.path.hasSuffix("/") ? existing.path : existing.path + "/"
        return candPath == existing.path || candPath.hasPrefix(prefix)
      }
      if !covered {
        unique.append(candidate)
      }
    }
    return unique
  }

  public static func formatDuration(_ seconds: TimeInterval) -> String {
    if seconds < 1.0 {
      return "\(max(1, Int((seconds * 1000).rounded())))ms"
    }
    return String(format: "%.2fs", seconds)
  }

  private static func summarizeChangedFiles(_ paths: [String], relativeTo root: URL) -> String {
    let rootPrefix = root.standardizedFileURL.path + "/"
    let names = paths.prefix(3).map { p -> String in
      if p.hasPrefix(rootPrefix) {
        return String(p.dropFirst(rootPrefix.count))
      }
      return URL(fileURLWithPath: p).lastPathComponent
    }
    if paths.count > 3 {
      return names.joined(separator: ", ") + " +\(paths.count - 3) more"
    }
    return names.joined(separator: ", ")
  }

  private static func formatDiagnostics(from error: Error) -> String {
    if case ProcessRunnerError.commandFailed(_, _, let output) = error {
      let lines = output
        .components(separatedBy: .newlines)
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
      let errorLines = lines.filter { line in
        line.contains("error:") || line.contains("warning:") || line.contains("note:")
      }
      if !errorLines.isEmpty {
        return errorLines.suffix(30).joined(separator: "\n")
      }
      return lines.suffix(30).joined(separator: "\n")
    }
    return error.localizedDescription
  }
}
