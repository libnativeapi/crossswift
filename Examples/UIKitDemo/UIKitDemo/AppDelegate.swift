import SwiftUI
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
  override init() {
    super.init()
  }

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    true
  }

  func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let config = UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    config.delegateClass = SceneDelegate.self
    return config
  }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  override init() {
    super.init()
  }

  func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene else { return }
    windowScene.title = "UIKit Workbench — CrossSwift"
    windowScene.sizeRestrictions?.minimumSize = CGSize(width: 820, height: 580)

    let win = UIWindow(windowScene: windowScene)
    win.frame = CGRect(x: 96, y: 72, width: 1020, height: 700)
    win.backgroundColor = .systemBackground
    win.rootViewController = UIHostingController(rootView: UIKitWorkbenchView())
    self.window = win
    win.makeKeyAndVisible()
  }
}
