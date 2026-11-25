import Foundation

#if !os(macOS)
  public struct UNAuthorizationOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let badge = UNAuthorizationOptions(rawValue: 1 << 0)
    public static let sound = UNAuthorizationOptions(rawValue: 1 << 1)
    public static let alert = UNAuthorizationOptions(rawValue: 1 << 2)
    public static let carPlay = UNAuthorizationOptions(rawValue: 1 << 3)
    public static let criticalAlert = UNAuthorizationOptions(rawValue: 1 << 4)
    public static let providesAppNotificationSettings = UNAuthorizationOptions(rawValue: 1 << 5)
    public static let provisional = UNAuthorizationOptions(rawValue: 1 << 6)
  }

  public enum UNAuthorizationStatus: Int, Sendable {
    case notDetermined = 0
    case denied = 1
    case authorized = 2
    case provisional = 3
    case ephemeral = 4
  }

  public enum UNNotificationSetting: Int, Sendable {
    case notSupported = 0
    case disabled = 1
    case enabled = 2
  }

  open class UNNotificationSettings: NSObject, @unchecked Sendable {
    public var authorizationStatus: UNAuthorizationStatus = .denied
    public var soundSetting: UNNotificationSetting = .disabled
    public var badgeSetting: UNNotificationSetting = .disabled
    public var alertSetting: UNNotificationSetting = .disabled
    public var notificationCenterSetting: UNNotificationSetting = .disabled
    public var lockScreenSetting: UNNotificationSetting = .disabled
  }

  open class UNNotificationSound: NSObject, @unchecked Sendable {
    public static let `default` = UNNotificationSound()
  }

  open class UNNotificationContent: NSObject, @unchecked Sendable {
    public var title: String = ""
    public var subtitle: String = ""
    public var body: String = ""
    public var badge: NSNumber?
    public var sound: UNNotificationSound?
    public var userInfo: [AnyHashable: Any] = [:]
    public var categoryIdentifier: String = ""
    public var threadIdentifier: String = ""
  }

  open class UNMutableNotificationContent: UNNotificationContent, @unchecked Sendable {}

  open class UNNotificationTrigger: NSObject, @unchecked Sendable {
    public var repeats: Bool = false
  }

  open class UNTimeIntervalNotificationTrigger: UNNotificationTrigger, @unchecked Sendable {
    public let timeInterval: TimeInterval
    public init(timeInterval: TimeInterval, repeats: Bool) {
      self.timeInterval = timeInterval
      super.init()
      self.repeats = repeats
    }
  }

  open class UNNotificationRequest: NSObject, @unchecked Sendable {
    public let identifier: String
    public let content: UNNotificationContent
    public let trigger: UNNotificationTrigger?

    public init(
      identifier: String,
      content: UNNotificationContent,
      trigger: UNNotificationTrigger?
    ) {
      self.identifier = identifier
      self.content = content
      self.trigger = trigger
      super.init()
    }
  }

  open class UNUserNotificationCenter: NSObject, @unchecked Sendable {
    private static let sharedCenter = UNUserNotificationCenter()

    public class func current() -> UNUserNotificationCenter {
      sharedCenter
    }

    public func requestAuthorization(
      options: UNAuthorizationOptions = [],
      completionHandler: @escaping (Bool, (any Error)?) -> Void
    ) {
      completionHandler(false, nil)
    }

    public func requestAuthorization(options: UNAuthorizationOptions = []) async throws -> Bool {
      false
    }

    public func getNotificationSettings(
      completionHandler: @escaping (UNNotificationSettings) -> Void
    ) {
      completionHandler(UNNotificationSettings())
    }

    public func notificationSettings() async -> UNNotificationSettings {
      UNNotificationSettings()
    }

    public func add(
      _ request: UNNotificationRequest,
      withCompletionHandler completionHandler: (((any Error)?) -> Void)? = nil
    ) {
      completionHandler?(nil)
    }

    public func add(_ request: UNNotificationRequest) async throws {}
    public func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {}
    public func removeAllPendingNotificationRequests() {}
    public func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {}
    public func removeAllDeliveredNotifications() {}
  }
#endif
