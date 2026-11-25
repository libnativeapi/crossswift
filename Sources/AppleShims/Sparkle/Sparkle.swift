import CrossFoundation
import Foundation

#if !os(macOS)
  public protocol SPUUpdaterDelegate: AnyObject {}
  public protocol SPUStandardUserDriverDelegate: AnyObject {}
  public protocol SPUUserDriver: AnyObject {}

  open class SPUStandardUserDriver: NSObject, SPUUserDriver, @unchecked Sendable {
    public init(hostBundle: Bundle, delegate: (any SPUStandardUserDriverDelegate)?) {
      super.init()
    }
  }

  open class SPUUpdater: NSObject, @unchecked Sendable {
    public var automaticallyChecksForUpdates: Bool = false
    public var automaticallyDownloadsUpdates: Bool = false
    public var canCheckForUpdates: Bool = false
    public var updateCheckInterval: TimeInterval = 86400
    public var lastUpdateCheckDate: Date? = nil
    public var sendsSystemProfile: Bool = false

    public init(
      hostBundle: Bundle,
      applicationBundle: Bundle,
      userDriver: any SPUUserDriver,
      delegate: (any SPUUpdaterDelegate)?
    ) {
      super.init()
    }

    public func start() throws {}
    public func checkForUpdates() {}
    public func checkForUpdatesInBackground() {}
    public func checkForUpdateInformation() {}
  }

  open class SPUStandardUpdaterController: NSObject, @unchecked Sendable {
    public let updater: SPUUpdater
    public let userDriver: SPUStandardUserDriver

    public init(
      startingUpdater: Bool,
      updaterDelegate: (any SPUUpdaterDelegate)?,
      userDriverDelegate: (any SPUStandardUserDriverDelegate)?
    ) {
      let driver = SPUStandardUserDriver(hostBundle: .main, delegate: userDriverDelegate)
      self.userDriver = driver
      self.updater = SPUUpdater(
        hostBundle: .main,
        applicationBundle: .main,
        userDriver: driver,
        delegate: updaterDelegate
      )
      super.init()
      if startingUpdater {
        try? self.updater.start()
      }
    }

    public func startUpdater() {
      try? updater.start()
    }

    public func checkForUpdates(_ sender: Any?) {
      updater.checkForUpdates()
    }
  }
#endif
