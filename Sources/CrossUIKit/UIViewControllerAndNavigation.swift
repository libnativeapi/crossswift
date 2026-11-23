import Foundation
#if !os(macOS)
  import NativeAPI
  import UniformTypeIdentifiers
#endif

// MARK: - Bar Items & Appearances

@MainActor
open class UIBarItem: NSObject {
  public var isEnabled: Bool = true
  public var title: String?
  public var image: UIImage?
  public var imageInsets: UIEdgeInsets = .zero
  public var tag: Int = 0
}

@MainActor
open class UIBarButtonItem: UIBarItem {
  public enum Style: Int, Sendable {
    case plain = 0
    case bordered = 1
    case done = 2
  }

  public enum SystemItem: Int, Sendable {
    case done = 0
    case cancel = 1
    case edit = 2
    case save = 3
    case add = 4
    case flexibleSpace = 5
    case fixedSpace = 6
    case compose = 7
    case reply = 8
    case action = 9
    case organize = 10
    case bookmarks = 11
    case search = 12
    case refresh = 13
    case stop = 14
    case camera = 15
    case trash = 16
    case play = 17
    case pause = 18
    case rewind = 19
    case fastForward = 20
    case undo = 21
    case redo = 22
    case close = 24
  }

  public var style: Style = .plain
  public var width: CGFloat = 0
  public var customView: UIView?
  public var action: Selector?
  public weak var target: AnyObject?
  public var primaryAction: UIAction?
  public var menu: UIMenu?
  public var tintColor: UIColor?
  public var isHidden: Bool = false

  public override init() { super.init() }

  public init(image: UIImage?, style: Style, target: Any?, action: Selector?) {
    super.init()
    self.image = image
    self.style = style
    self.target = target as AnyObject?
    self.action = action
  }

  public init(title: String?, style: Style, target: Any?, action: Selector?) {
    super.init()
    self.title = title
    self.style = style
    self.target = target as AnyObject?
    self.action = action
  }

  public init(barButtonSystemItem systemItem: SystemItem, target: Any?, action: Selector?) {
    super.init()
    self.target = target as AnyObject?
    self.action = action
  }

  public init(customView: UIView) {
    super.init()
    self.customView = customView
  }

  public init(primaryAction: UIAction?) {
    super.init()
    self.primaryAction = primaryAction
    self.title = primaryAction?.title
    self.image = primaryAction?.image
  }

  public init(title: String? = nil, image: UIImage? = nil, primaryAction: UIAction? = nil, menu: UIMenu? = nil) {
    super.init()
    self.title = title ?? primaryAction?.title
    self.image = image ?? primaryAction?.image
    self.primaryAction = primaryAction
    self.menu = menu
  }

  public static func flexibleSpace() -> UIBarButtonItem {
    UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
  }

  public static func fixedSpace(_ width: CGFloat) -> UIBarButtonItem {
    let item = UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil)
    item.width = width
    return item
  }
}

open class UIBarAppearance: NSObject, NSCopying {
  public var backgroundEffect: UIBlurEffect?
  public var backgroundColor: UIColor?
  public var backgroundImage: UIImage?
  public var shadowColor: UIColor?
  public var shadowImage: UIImage?

  public required override init() { super.init() }
  public func configureWithDefaultBackground() {
    backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
    backgroundColor = nil
  }
  public func configureWithOpaqueBackground() {
    backgroundEffect = nil
    backgroundColor = .systemBackground
  }
  public func configureWithTransparentBackground() {
    backgroundEffect = nil
    backgroundColor = .clear
    shadowColor = .clear
  }
  open func copy(with zone: NSZone? = nil) -> Any { Self() }
}

open class UINavigationBarAppearance: UIBarAppearance {
  public var titleTextAttributes: [NSAttributedString.Key: Any] = [:]
  public var largeTitleTextAttributes: [NSAttributedString.Key: Any] = [:]
}

open class UITabBarAppearance: UIBarAppearance {}
open class UIToolbarAppearance: UIBarAppearance {}

@MainActor
open class UINavigationItem: NSObject {
  public enum LargeTitleDisplayMode: Int, Sendable {
    case automatic = 0
    case always = 1
    case never = 2
    case inline = 3
  }

  public var title: String?
  public var subtitle: String?
  public var titleView: UIView?
  public var prompt: String?
  public var backBarButtonItem: UIBarButtonItem?
  public var backButtonTitle: String?
  public var hidesBackButton: Bool = false
  public var leftItemsSupplementBackButton: Bool = false
  public var largeTitleDisplayMode: LargeTitleDisplayMode = .automatic
  public var leftBarButtonItems: [UIBarButtonItem]?
  public var rightBarButtonItems: [UIBarButtonItem]?
  public var searchController: UISearchController?
  public var hidesSearchBarWhenScrolling: Bool = true
  public var standardAppearance: UINavigationBarAppearance?
  public var compactAppearance: UINavigationBarAppearance?
  public var scrollEdgeAppearance: UINavigationBarAppearance?

  public var leftBarButtonItem: UIBarButtonItem? {
    get { leftBarButtonItems?.first }
    set { leftBarButtonItems = newValue.map { [$0] } }
  }

  public var rightBarButtonItem: UIBarButtonItem? {
    get { rightBarButtonItems?.first }
    set { rightBarButtonItems = newValue.map { [$0] } }
  }

  public init(title: String) {
    self.title = title
    super.init()
  }

  public override init() { super.init() }

  public func setLeftBarButton(_ item: UIBarButtonItem?, animated: Bool) { leftBarButtonItem = item }
  public func setRightBarButton(_ item: UIBarButtonItem?, animated: Bool) { rightBarButtonItem = item }
  public func setLeftBarButtonItems(_ items: [UIBarButtonItem]?, animated: Bool) { leftBarButtonItems = items }
  public func setRightBarButtonItems(_ items: [UIBarButtonItem]?, animated: Bool) { rightBarButtonItems = items }
  public func setHidesBackButton(_ hidesBackButton: Bool, animated: Bool) { self.hidesBackButton = hidesBackButton }
}

@MainActor
open class UINavigationBar: UIView {
  public var barTintColor: UIColor?
  public var isTranslucent: Bool = true
  public var prefersLargeTitles: Bool = false
  public var titleTextAttributes: [NSAttributedString.Key: Any]?
  public var largeTitleTextAttributes: [NSAttributedString.Key: Any]?
  public var standardAppearance = UINavigationBarAppearance()
  public var compactAppearance: UINavigationBarAppearance?
  public var scrollEdgeAppearance: UINavigationBarAppearance?
  public var items: [UINavigationItem]?
}

@MainActor
open class UIToolbar: UIView {
  public var items: [UIBarButtonItem]?
  public var isTranslucent: Bool = true
  public var barTintColor: UIColor?
  public var standardAppearance = UIToolbarAppearance()
  public var compactAppearance: UIToolbarAppearance?
  public var scrollEdgeAppearance: UIToolbarAppearance?

  public func setItems(_ items: [UIBarButtonItem]?, animated: Bool) {
    self.items = items
  }
}

// MARK: - Search Bar & Search Controller

@MainActor
public protocol UISearchBarDelegate: NSObjectProtocol {
  func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String)
  func searchBarSearchButtonClicked(_ searchBar: UISearchBar)
  func searchBarCancelButtonClicked(_ searchBar: UISearchBar)
}

extension UISearchBarDelegate {
  public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {}
  public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {}
  public func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {}
}

@MainActor
open class UISearchBar: UIView {
  public weak var delegate: (any UISearchBarDelegate)?
  public let searchTextField = UITextField(frame: .zero)
  public var text: String? {
    get { searchTextField.text }
    set { searchTextField.text = newValue }
  }
  public var placeholder: String? {
    get { searchTextField.placeholder }
    set { searchTextField.placeholder = newValue }
  }
  public var showsCancelButton: Bool = false
  public var barTintColor: UIColor?

  public override init(frame: CGRect) {
    super.init(frame: frame)
    searchTextField.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    addSubview(searchTextField)
  }

  public required init?(coder: NSCoder) {
    super.init(coder: coder)
    addSubview(searchTextField)
  }
}

@MainActor
public protocol UISearchResultsUpdating: NSObjectProtocol {
  func updateSearchResults(for searchController: UISearchController)
}

@MainActor
open class UISearchController: UIViewController {
  public weak var searchResultsUpdater: (any UISearchResultsUpdating)?
  public let searchResultsController: UIViewController?
  public let searchBar = UISearchBar(frame: .zero)
  public var isActive: Bool = false
  public var obscuresBackgroundDuringPresentation: Bool = false
  public var hidesNavigationBarDuringPresentation: Bool = true
  public var automaticallyShowsCancelButton: Bool = true

  public init(searchResultsController: UIViewController? = nil) {
    self.searchResultsController = searchResultsController
    super.init(nibName: nil, bundle: nil)
  }

  public required init?(coder: NSCoder) {
    self.searchResultsController = nil
    super.init(coder: coder)
  }
}

// MARK: - Sheet & Popover Presentation Controllers

@MainActor
open class UISheetPresentationController: NSObject {
  open class Detent: NSObject {
    public struct Identifier: RawRepresentable, Equatable, Hashable, Sendable {
      public let rawValue: String
      public init(_ rawValue: String) { self.rawValue = rawValue }
      public init(rawValue: String) { self.rawValue = rawValue }
      public static let medium = Identifier("com.apple.UIKit.medium")
      public static let large = Identifier("com.apple.UIKit.large")
    }

    public let identifier: Identifier
    public init(identifier: Identifier) {
      self.identifier = identifier
      super.init()
    }
    public static func medium() -> Detent { Detent(identifier: .medium) }
    public static func large() -> Detent { Detent(identifier: .large) }
    public static func custom(
      identifier: Identifier? = nil,
      resolver: @escaping (any Context) -> CGFloat?
    ) -> Detent {
      Detent(identifier: identifier ?? Identifier(UUID().uuidString))
    }

    public protocol Context {
      var containerTraitCollection: UITraitCollection { get }
      var maximumDetentValue: CGFloat { get }
    }
  }

  public var detents: [Detent] = [.large()]
  public var selectedDetentIdentifier: Detent.Identifier?
  public var largestUndimmedDetentIdentifier: Detent.Identifier?
  public var prefersScrollingExpandsWhenScrolledToEdge: Bool = true
  public var prefersGrabberVisible: Bool = false
  public var prefersEdgeAttachedInCompactHeight: Bool = false
  public var widthFollowsPreferredContentSizeWhenEdgeAttached: Bool = false
  public var preferredCornerRadius: CGFloat?

  public func animateChanges(_ changes: () -> Void) {
    changes()
  }
}

@MainActor
open class UIPopoverPresentationController: NSObject {
  public var sourceView: UIView?
  public var sourceRect: CGRect = .zero
  public var barButtonItem: UIBarButtonItem?
  public var permittedArrowDirections: UInt = 0xF
  public var backgroundColor: UIColor?
}

@MainActor
public protocol UIViewControllerTransitionCoordinator: NSObjectProtocol {
  var isAnimated: Bool { get }
  var transitionDuration: TimeInterval { get }
  func animate(
    alongsideTransition animation: ((any UIViewControllerTransitionCoordinatorContext) -> Void)?,
    completion: ((any UIViewControllerTransitionCoordinatorContext) -> Void)?
  ) -> Bool
}

@MainActor
public protocol UIViewControllerTransitionCoordinatorContext: NSObjectProtocol {
  var isAnimated: Bool { get }
  var isCancelled: Bool { get }
  var transitionDuration: TimeInterval { get }
}

// MARK: - UIViewController

@MainActor
open class UIViewController: UIResponder, UITraitEnvironment {
  public enum ModalPresentationStyle: Int, Sendable {
    case automatic = -2
    case none = -1
    case fullScreen = 0
    case pageSheet = 1
    case formSheet = 2
    case currentContext = 3
    case custom = 4
    case overFullScreen = 5
    case overCurrentContext = 6
    case popover = 7
  }

  public enum ModalTransitionStyle: Int, Sendable {
    case coverVertical = 0
    case flipHorizontal = 1
    case crossDissolve = 2
    case partialCurl = 3
  }

  private var _view: UIView?
  public var isViewLoaded: Bool { _view != nil }
  public var viewIfLoaded: UIView? { _view }

  open var view: UIView! {
    get {
      loadViewIfNeeded()
      return _view
    }
    set {
      _view?.owningViewController = nil
      _view = newValue
      newValue?.owningViewController = self
    }
  }

  open var title: String? {
    didSet {
      if navigationItem.title == nil || navigationItem.title == oldValue {
        navigationItem.title = title
      }
      if tabBarItem.title == nil || tabBarItem.title == oldValue {
        tabBarItem.title = title
      }
    }
  }

  public let nibName: String?
  public let nibBundle: Bundle?
  public let navigationItem = UINavigationItem()
  public var tabBarItem: UITabBarItem! = UITabBarItem(title: nil, image: nil, tag: 0)
  public var toolbarItems: [UIBarButtonItem]?
  public var hidesBottomBarWhenPushed: Bool = false
  public var definesPresentationContext: Bool = false
  public var modalPresentationStyle: ModalPresentationStyle = .automatic
  public var modalTransitionStyle: ModalTransitionStyle = .coverVertical
  public var isModalInPresentation: Bool = false
  public var preferredContentSize: CGSize = .zero
  public var additionalSafeAreaInsets: UIEdgeInsets = .zero

  public var overrideUserInterfaceStyle: UIUserInterfaceStyle = .unspecified {
    didSet {
      _view?.overrideUserInterfaceStyle = overrideUserInterfaceStyle
    }
  }

  public private(set) weak var parent: UIViewController?
  public private(set) var children: [UIViewController] = []
  public internal(set) var presentedViewController: UIViewController?
  public internal(set) weak var presentingViewController: UIViewController?

  private lazy var _sheetController = UISheetPresentationController()
  private lazy var _popoverController = UIPopoverPresentationController()
  public var sheetPresentationController: UISheetPresentationController? { _sheetController }
  public var popoverPresentationController: UIPopoverPresentationController? { _popoverController }

  public var navigationController: UINavigationController? {
    if let nav = self as? UINavigationController { return nav }
    return parent?.navigationController
  }

  public var tabBarController: UITabBarController? {
    if let tab = self as? UITabBarController { return tab }
    return parent?.tabBarController
  }

  public var splitViewController: UISplitViewController? {
    if let split = self as? UISplitViewController { return split }
    return parent?.splitViewController
  }

  open override var next: UIResponder? {
    _view?.superview ?? parent ?? nextResponderOverride
  }

  open var traitCollection: UITraitCollection {
    if let v = _view { return v.traitCollection }
    let base = parent?.traitCollection ?? UITraitCollection.systemTraitCollection
    guard overrideUserInterfaceStyle != .unspecified else { return base }
    let s = overrideUserInterfaceStyle
    return base.modifyingTraits { $0.userInterfaceStyle = s }
  }

  open func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {}

  private var vcTraitObservers: [UUID: (UIViewController, UITraitCollection) -> Void] = [:]

  @discardableResult
  public func registerForTraitChanges(
    _ traits: [Any],
    handler: @escaping (Self, UITraitCollection) -> Void
  ) -> any UITraitChangeRegistration {
    let token = _TraitRegistrationToken()
    vcTraitObservers[token.id] = { vc, prev in
      if let typed = vc as? Self {
        handler(typed, prev)
      }
    }
    return token
  }

  public func unregisterForTraitChanges(_ registration: any UITraitChangeRegistration) {
    if let token = registration as? _TraitRegistrationToken {
      vcTraitObservers.removeValue(forKey: token.id)
    }
  }

  public init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
    self.nibName = nibNameOrNil
    self.nibBundle = nibBundleOrNil
    super.init()
  }

  public convenience override init() {
    self.init(nibName: nil, bundle: nil)
  }

  public required override init?(coder: NSCoder) {
    self.nibName = nil
    self.nibBundle = nil
    super.init(coder: coder)
  }

  open func loadView() {
    if _view == nil {
      let defaultView = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
      defaultView.backgroundColor = .systemBackground
      if overrideUserInterfaceStyle != .unspecified {
        defaultView.overrideUserInterfaceStyle = overrideUserInterfaceStyle
      }
      defaultView.owningViewController = self
      _view = defaultView
    }
  }

  public func loadViewIfNeeded() {
    guard _view == nil else { return }
    loadView()
    if _view == nil {
      let fallback = UIView(frame: .zero)
      fallback.owningViewController = self
      _view = fallback
    }
    viewDidLoad()
  }

  open func viewDidLoad() {}
  open func viewWillAppear(_ animated: Bool) {}
  open func viewIsAppearing(_ animated: Bool) {}
  open func viewDidAppear(_ animated: Bool) {}
  open func viewWillDisappear(_ animated: Bool) {}
  open func viewDidDisappear(_ animated: Bool) {}
  open func viewWillLayoutSubviews() {}
  open func viewDidLayoutSubviews() {}
  open func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {}
  open func didReceiveMemoryWarning() {}
  open func setNeedsStatusBarAppearanceUpdate() {}

  open func addChild(_ childController: UIViewController) {
    guard childController !== self, !children.contains(where: { $0 === childController }) else { return }
    childController.willMove(toParent: self)
    childController.parent?.children.removeAll { $0 === childController }
    children.append(childController)
    childController.parent = self
  }

  open func removeFromParent() {
    guard let p = parent else { return }
    p.children.removeAll { $0 === self }
    parent = nil
  }

  open func willMove(toParent parent: UIViewController?) {}
  open func didMove(toParent parent: UIViewController?) {}

  open func present(_ viewControllerToPresent: UIViewController, animated flag: Bool, completion: (() -> Void)? = nil) {
    if let alert = viewControllerToPresent as? UIAlertController, alert._presentNativelyIfInteractive() {
      completion?()
      return
    }
    if let docPicker = viewControllerToPresent as? UIDocumentPickerViewController, docPicker._presentNativeFileDialog() {
      completion?()
      return
    }
    presentedViewController = viewControllerToPresent
    viewControllerToPresent.presentingViewController = self
    viewControllerToPresent.loadViewIfNeeded()
    viewControllerToPresent.viewWillAppear(flag)
    if let hostView = _view {
      viewControllerToPresent.view.frame = hostView.bounds
      viewControllerToPresent.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      hostView.addSubview(viewControllerToPresent.view)
      viewControllerToPresent.view.layoutIfNeeded()
    }
    viewControllerToPresent.viewDidAppear(flag)
    completion?()
  }

  open func dismiss(animated flag: Bool, completion: (() -> Void)? = nil) {
    if let child = presentedViewController {
      child.viewWillDisappear(flag)
      child.viewIfLoaded?.removeFromSuperview()
      child.presentingViewController = nil
      presentedViewController = nil
      child.viewDidDisappear(flag)
      completion?()
      return
    }
    if let presenter = presentingViewController {
      presenter.dismiss(animated: flag, completion: completion)
      return
    }
    completion?()
  }

  open func show(_ vc: UIViewController, sender: Any?) {
    if let nav = navigationController {
      nav.pushViewController(vc, animated: true)
    } else {
      present(vc, animated: true)
    }
  }

  open func showDetailViewController(_ vc: UIViewController, sender: Any?) {
    if let split = splitViewController {
      split.setViewController(vc, for: .secondary)
    } else {
      show(vc, sender: sender)
    }
  }
}

// MARK: - UINavigationController

@MainActor
public protocol UINavigationControllerDelegate: NSObjectProtocol {
  func navigationController(
    _ navigationController: UINavigationController,
    willShow viewController: UIViewController,
    animated: Bool
  )
  func navigationController(
    _ navigationController: UINavigationController,
    didShow viewController: UIViewController,
    animated: Bool
  )
}

extension UINavigationControllerDelegate {
  public func navigationController(
    _ navigationController: UINavigationController,
    willShow viewController: UIViewController,
    animated: Bool
  ) {}
  public func navigationController(
    _ navigationController: UINavigationController,
    didShow viewController: UIViewController,
    animated: Bool
  ) {}
}

@MainActor
open class UINavigationController: UIViewController {
  public private(set) var viewControllers: [UIViewController] = []
  public let navigationBar = UINavigationBar(frame: .zero)
  public let toolbar = UIToolbar(frame: .zero)
  public var isNavigationBarHidden: Bool = false
  public var isToolbarHidden: Bool = true
  public weak var delegate: (any UINavigationControllerDelegate)?

  public var topViewController: UIViewController? { viewControllers.last }
  public var visibleViewController: UIViewController? { presentedViewController ?? topViewController }

  public init(rootViewController: UIViewController) {
    super.init(nibName: nil, bundle: nil)
    setViewControllers([rootViewController], animated: false)
  }

  public init(navigationBarClass: AnyClass?, toolbarClass: AnyClass?) {
    super.init(nibName: nil, bundle: nil)
  }

  public override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
    super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
  }

  public required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  open override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    topViewController?.viewIfLoaded?.frame = view.bounds
  }

  open func pushViewController(_ viewController: UIViewController, animated: Bool) {
    guard !viewControllers.contains(where: { $0 === viewController }) else { return }
    let previous = topViewController
    previous?.viewWillDisappear(animated)
    addChild(viewController)
    viewControllers.append(viewController)
    viewController.didMove(toParent: self)
    mountActiveTopViewController(previous: previous, animated: animated)
  }

  @discardableResult
  open func popViewController(animated: Bool) -> UIViewController? {
    guard viewControllers.count > 1 else { return nil }
    let popped = viewControllers.removeLast()
    popped.willMove(toParent: nil)
    popped.viewWillDisappear(animated)
    popped.viewIfLoaded?.removeFromSuperview()
    popped.removeFromParent()
    popped.viewDidDisappear(animated)
    mountActiveTopViewController(previous: nil, animated: animated)
    return popped
  }

  @discardableResult
  open func popToRootViewController(animated: Bool) -> [UIViewController]? {
    guard viewControllers.count > 1, let root = viewControllers.first else { return nil }
    return popToViewController(root, animated: animated)
  }

  @discardableResult
  open func popToViewController(_ viewController: UIViewController, animated: Bool) -> [UIViewController]? {
    guard let idx = viewControllers.firstIndex(where: { $0 === viewController }),
          idx < viewControllers.count - 1
    else { return nil }
    let popped = Array(viewControllers[(idx + 1)...])
    viewControllers.removeSubrange((idx + 1)...)
    for vc in popped {
      vc.willMove(toParent: nil)
      vc.viewWillDisappear(animated)
      vc.viewIfLoaded?.removeFromSuperview()
      vc.removeFromParent()
      vc.viewDidDisappear(animated)
    }
    mountActiveTopViewController(previous: nil, animated: animated)
    return popped
  }

  open func setViewControllers(_ viewControllers: [UIViewController], animated: Bool) {
    let previous = topViewController
    for old in self.viewControllers where !viewControllers.contains(where: { $0 === old }) {
      old.willMove(toParent: nil)
      old.viewIfLoaded?.removeFromSuperview()
      old.removeFromParent()
    }
    self.viewControllers = viewControllers
    for vc in viewControllers where vc.parent !== self {
      addChild(vc)
      vc.didMove(toParent: self)
    }
    mountActiveTopViewController(previous: previous, animated: animated)
  }

  public func setNavigationBarHidden(_ hidden: Bool, animated: Bool) {
    isNavigationBarHidden = hidden
  }

  public func setToolbarHidden(_ hidden: Bool, animated: Bool) {
    isToolbarHidden = hidden
  }

  private func mountActiveTopViewController(previous: UIViewController?, animated: Bool) {
    loadViewIfNeeded()
    if let prev = previous, prev !== topViewController {
      prev.viewIfLoaded?.removeFromSuperview()
      prev.viewDidDisappear(animated)
    }
    guard let top = topViewController else { return }
    delegate?.navigationController(self, willShow: top, animated: animated)
    top.loadViewIfNeeded()
    top.viewWillAppear(animated)
    top.view.frame = view.bounds
    top.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    if top.view.superview !== view {
      view.addSubview(top.view)
    }
    top.view.layoutIfNeeded()
    top.viewDidAppear(animated)
    navigationBar.items = viewControllers.map(\.navigationItem)
    delegate?.navigationController(self, didShow: top, animated: animated)
  }
}

// MARK: - UITabBar & UITabBarController

@MainActor
open class UITabBarItem: UIBarItem {
  public enum SystemItem: Int, Sendable {
    case more = 0
    case favorites = 1
    case featured = 2
    case topRated = 3
    case recents = 4
    case contacts = 5
    case history = 6
    case bookmarks = 7
    case search = 8
    case downloads = 9
    case mostRecent = 10
    case mostViewed = 11
  }

  public var selectedImage: UIImage?
  public var badgeValue: String?
  public var badgeColor: UIColor?
  public var standardAppearance: UITabBarAppearance?
  public var scrollEdgeAppearance: UITabBarAppearance?

  public override init() { super.init() }

  public init(title: String?, image: UIImage?, tag: Int) {
    super.init()
    self.title = title
    self.image = image
    self.tag = tag
  }

  public init(title: String?, image: UIImage?, selectedImage: UIImage?) {
    super.init()
    self.title = title
    self.image = image
    self.selectedImage = selectedImage
  }

  public init(tabBarSystemItem systemItem: SystemItem, tag: Int) {
    super.init()
    self.tag = tag
  }
}

@MainActor
open class UITabBar: UIView {
  public var items: [UITabBarItem]?
  public weak var selectedItem: UITabBarItem?
  public var barTintColor: UIColor?
  public var unselectedItemTintColor: UIColor?
  public var isTranslucent: Bool = true
  public var standardAppearance = UITabBarAppearance()
  public var scrollEdgeAppearance: UITabBarAppearance?
}

@MainActor
public protocol UITabBarControllerDelegate: NSObjectProtocol {
  func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool
  func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController)
}

extension UITabBarControllerDelegate {
  public func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool { true }
  public func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {}
}

@MainActor
open class UITabBarController: UIViewController {
  public let tabBar = UITabBar(frame: .zero)
  public weak var delegate: (any UITabBarControllerDelegate)?

  public var viewControllers: [UIViewController]? {
    didSet {
      for old in children where !(viewControllers?.contains(where: { $0 === old }) ?? false) {
        old.willMove(toParent: nil)
        old.viewIfLoaded?.removeFromSuperview()
        old.removeFromParent()
      }
      for vc in viewControllers ?? [] where vc.parent !== self {
        addChild(vc)
        vc.didMove(toParent: self)
      }
      tabBar.items = viewControllers?.map(\.tabBarItem)
      if let list = viewControllers, !list.isEmpty {
        if selectedIndex >= list.count || selectedIndex < 0 {
          selectedIndex = 0
        } else {
          syncSelectedTabView()
        }
      }
    }
  }

  public var selectedIndex: Int = 0 {
    didSet { syncSelectedTabView() }
  }

  public var selectedViewController: UIViewController? {
    get {
      guard let vcs = viewControllers, vcs.indices.contains(selectedIndex) else { return nil }
      return vcs[selectedIndex]
    }
    set {
      if let newValue, let idx = viewControllers?.firstIndex(where: { $0 === newValue }) {
        selectedIndex = idx
      }
    }
  }

  public func setViewControllers(_ viewControllers: [UIViewController]?, animated: Bool) {
    self.viewControllers = viewControllers
  }

  open override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    selectedViewController?.viewIfLoaded?.frame = view.bounds
  }

  private func syncSelectedTabView() {
    loadViewIfNeeded()
    for (idx, vc) in (viewControllers ?? []).enumerated() where idx != selectedIndex {
      vc.viewIfLoaded?.removeFromSuperview()
    }
    guard let active = selectedViewController else { return }
    active.loadViewIfNeeded()
    active.viewWillAppear(false)
    active.view.frame = view.bounds
    active.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    if active.view.superview !== view {
      view.addSubview(active.view)
    }
    active.view.layoutIfNeeded()
    active.viewDidAppear(false)
    tabBar.selectedItem = active.tabBarItem
  }
}

// MARK: - UISplitViewController & UIPageViewController

@MainActor
open class UISplitViewController: UIViewController {
  public enum Style: Int, Sendable {
    case unspecified = 0
    case doubleColumn = 1
    case tripleColumn = 2
  }

  public enum Column: Int, Sendable {
    case primary = 0
    case supplementary = 1
    case secondary = 2
    case compact = 3
  }

  public enum DisplayMode: Int, Sendable {
    case automatic = 0
    case secondaryOnly = 1
    case oneBesideSecondary = 2
    case oneOverSecondary = 3
    case twoBesideSecondary = 4
    case twoOverSecondary = 5
    case twoDisplaceSecondary = 6
  }

  public let style: Style
  public var preferredDisplayMode: DisplayMode = .automatic
  public var displayMode: DisplayMode { preferredDisplayMode == .automatic ? .oneBesideSecondary : preferredDisplayMode }
  public var presentsWithGesture: Bool = true
  public var showsSecondaryOnlyButton: Bool = false
  public var preferredPrimaryColumnWidthFraction: CGFloat = 0.30
  public var minimumPrimaryColumnWidth: CGFloat = 200
  public var maximumPrimaryColumnWidth: CGFloat = 360
  private var columnControllers: [Column: UIViewController] = [:]

  public var viewControllers: [UIViewController] = []

  public init(style: Style) {
    self.style = style
    super.init(nibName: nil, bundle: nil)
  }

  public override convenience init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
    self.init(style: .doubleColumn)
  }

  public required init?(coder: NSCoder) {
    self.style = .doubleColumn
    super.init(coder: coder)
  }

  public func setViewController(_ vc: UIViewController?, for column: Column) {
    if let old = columnControllers.removeValue(forKey: column) {
      old.willMove(toParent: nil)
      old.viewIfLoaded?.removeFromSuperview()
      old.removeFromParent()
    }
    if let vc {
      columnControllers[column] = vc
      addChild(vc)
      loadViewIfNeeded()
      vc.loadViewIfNeeded()
      view.addSubview(vc.view)
      vc.didMove(toParent: self)
      view.setNeedsLayout()
    }
  }

  public func viewController(for column: Column) -> UIViewController? {
    columnControllers[column]
  }

  open override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let b = view.bounds
    let primary = columnControllers[.primary]
    let secondary = columnControllers[.secondary]
    if let primary, let secondary {
      let sideW = min(maximumPrimaryColumnWidth, max(minimumPrimaryColumnWidth, (b.width * preferredPrimaryColumnWidthFraction).rounded()))
      primary.view.frame = CGRect(x: 0, y: 0, width: sideW, height: b.height)
      secondary.view.frame = CGRect(x: sideW, y: 0, width: max(0, b.width - sideW), height: b.height)
    } else if let only = secondary ?? primary {
      only.view.frame = b
    }
  }
}

@MainActor
open class UIPageViewController: UIViewController {
  public enum TransitionStyle: Int, Sendable {
    case pageCurl = 0
    case scroll = 1
  }

  public enum NavigationOrientation: Int, Sendable {
    case horizontal = 0
    case vertical = 1
  }

  public enum NavigationDirection: Int, Sendable {
    case forward = 0
    case reverse = 1
  }

  public private(set) var viewControllers: [UIViewController]?

  public init(
    transitionStyle style: TransitionStyle,
    navigationOrientation: NavigationOrientation,
    options: [String: Any]? = nil
  ) {
    super.init(nibName: nil, bundle: nil)
  }

  public required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  public func setViewControllers(
    _ viewControllers: [UIViewController]?,
    direction: NavigationDirection,
    animated: Bool,
    completion: ((Bool) -> Void)? = nil
  ) {
    for old in self.viewControllers ?? [] {
      old.viewIfLoaded?.removeFromSuperview()
      old.removeFromParent()
    }
    self.viewControllers = viewControllers
    loadViewIfNeeded()
    if let first = viewControllers?.first {
      addChild(first)
      first.loadViewIfNeeded()
      first.view.frame = view.bounds
      first.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      view.addSubview(first.view)
      first.didMove(toParent: self)
    }
    completion?(true)
  }
}

// MARK: - UIAlertController & System Pickers

@MainActor
open class UIAlertAction: NSObject, @preconcurrency NSCopying {
  public enum Style: Int, Sendable {
    case `default` = 0
    case cancel = 1
    case destructive = 2
  }

  public let title: String?
  public let style: Style
  public var isEnabled: Bool = true
  internal let handler: ((UIAlertAction) -> Void)?

  public init(title: String?, style: Style, handler: ((UIAlertAction) -> Void)? = nil) {
    self.title = title
    self.style = style
    self.handler = handler
    super.init()
  }

  open func copy(with zone: NSZone? = nil) -> Any {
    let c = UIAlertAction(title: title, style: style, handler: handler)
    c.isEnabled = isEnabled
    return c
  }

  public func _trigger() {
    guard isEnabled else { return }
    handler?(self)
  }
}

@MainActor
open class UIAlertController: UIViewController {
  public enum Style: Int, Sendable {
    case actionSheet = 0
    case alert = 1
  }

  public var message: String?
  public let preferredStyle: Style
  public private(set) var actions: [UIAlertAction] = []
  public var preferredAction: UIAlertAction?
  public private(set) var textFields: [UITextField]?

  /// Controls whether `present(_:)` opens a blocking OS `MessageDialog` (`false` in unit tests).
  public static var usesNativeModalDialogs: Bool = true

  public init(title: String?, message: String?, preferredStyle: Style) {
    self.message = message
    self.preferredStyle = preferredStyle
    super.init(nibName: nil, bundle: nil)
    self.title = title
  }

  public required init?(coder: NSCoder) {
    self.preferredStyle = .alert
    super.init(coder: coder)
  }

  public func addAction(_ action: UIAlertAction) {
    actions.append(action)
  }

  public func addTextField(configurationHandler: ((UITextField) -> Void)? = nil) {
    let tf = UITextField(frame: .zero)
    configurationHandler?(tf)
    if textFields == nil { textFields = [] }
    textFields?.append(tf)
  }

  internal func _presentNativelyIfInteractive() -> Bool {
    guard Self.usesNativeModalDialogs,
          !CommandLine.arguments.contains("--smoke")
    else { return false }
    #if !os(macOS)
      let enabledActions = actions.filter(\.isEnabled)
      guard let dialog = NativeAPI.MessageDialog.create(title ?? "", message: message ?? "") else {
        return false
      }
      dialog.setModality(.application)
      let primaryTitle = enabledActions.indices.contains(0) ? (enabledActions[0].title ?? "OK") : "OK"
      let secondaryTitle = enabledActions.indices.contains(1) ? (enabledActions[1].title ?? "") : ""
      let closeTitle = enabledActions.indices.contains(2) ? (enabledActions[2].title ?? "") : ""
      _ = dialog.setButtons(primaryTitle, secondary: secondaryTitle, close: closeTitle)
      _ = dialog.open()
      switch dialog.result {
      case .primary:
        if enabledActions.indices.contains(0) { enabledActions[0]._trigger() }
      case .secondary:
        if enabledActions.indices.contains(1) { enabledActions[1]._trigger() }
      case .close:
        if enabledActions.indices.contains(2) { enabledActions[2]._trigger() }
      case .none:
        if let cancel = enabledActions.first(where: { $0.style == .cancel }) {
          cancel._trigger()
        }
      }
      return true
    #else
      return false
    #endif
  }
}

@MainActor
open class UIActivityViewController: UIViewController {
  public let activityItems: [Any]
  public var excludedActivityTypes: [String]?

  public init(activityItems: [Any], applicationActivities: [Any]? = nil) {
    self.activityItems = activityItems
    super.init(nibName: nil, bundle: nil)
  }

  public required init?(coder: NSCoder) {
    self.activityItems = []
    super.init(coder: coder)
  }
}

@MainActor
public protocol UIDocumentPickerDelegate: NSObjectProtocol {
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL])
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController)
}

extension UIDocumentPickerDelegate {
  public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {}
  public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
}

@MainActor
open class UIDocumentPickerViewController: UIViewController {
  public weak var delegate: (any UIDocumentPickerDelegate)?
  public var allowsMultipleSelection: Bool = false
  public var shouldShowFileExtensions: Bool = false
  public var directoryURL: URL?
  private let isExporting: Bool
  private let exportURLs: [URL]
  private let allowedExtensions: [String]

  #if !os(macOS)
    public init(forOpeningContentTypes contentTypes: [UTType], asCopy: Bool = false) {
      self.isExporting = false
      self.exportURLs = []
      self.allowedExtensions = contentTypes.compactMap(\.preferredFilenameExtension)
      super.init(nibName: nil, bundle: nil)
    }
  #endif

  public init(forExporting urls: [URL], asCopy: Bool = false) {
    self.isExporting = true
    self.exportURLs = urls
    self.allowedExtensions = []
    super.init(nibName: nil, bundle: nil)
  }

  public required init?(coder: NSCoder) {
    self.isExporting = false
    self.exportURLs = []
    self.allowedExtensions = []
    super.init(coder: coder)
  }

  internal func _presentNativeFileDialog() -> Bool {
    guard !CommandLine.arguments.contains("--smoke") else { return false }
    #if !os(macOS)
      let mode: NativeAPI.FileDialogMode = isExporting
        ? .saveFile
        : (allowsMultipleSelection ? .openFiles : .openFile)
      guard let dialog = NativeAPI.FileDialog.create(mode) else { return false }
      dialog.setModality(.window)
      if let owner = UIApplication.shared.keyWindow?.nativeWindow {
        _ = dialog.setParentWindow(owner)
      }
      let dotted = allowedExtensions.compactMap { ext -> String? in
        let clean = ext.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        if clean == "*" { return "*" }
        return clean.isEmpty ? nil : ".\(clean.lowercased())"
      }
      if !dotted.isEmpty {
        _ = dialog.setFileTypes(dotted)
      }
      if isExporting, let first = exportURLs.first {
        _ = dialog.setSuggestedFileName(first.lastPathComponent)
      }
      if dialog.open(), dialog.result == .accepted, !dialog.paths.isEmpty {
        let picked = dialog.paths.map { URL(filePath: $0) }
        delegate?.documentPicker(self, didPickDocumentsAt: picked)
      } else {
        delegate?.documentPickerWasCancelled(self)
      }
      return true
    #else
      return false
    #endif
  }
}

@MainActor
open class UIImagePickerController: UINavigationController {
  public enum SourceType: Int, Sendable {
    case photoLibrary = 0
    case camera = 1
    case savedPhotosAlbum = 2
  }

  public var sourceType: SourceType = .photoLibrary
  public var allowsEditing: Bool = false
  public static func isSourceTypeAvailable(_ sourceType: SourceType) -> Bool {
    sourceType != .camera
  }
}
