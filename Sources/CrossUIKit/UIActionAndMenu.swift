import Foundation
#if !os(macOS)
  import NativeAPI
#endif

// MARK: - UIMenuElement, UIAction, UICommand, UIMenu

@MainActor
public protocol UIMenuBuilder: AnyObject {
  var system: UIMenuSystem { get }
  func menu(for identifier: UIMenu.Identifier) -> UIMenu?
  func action(for identifier: UIAction.Identifier) -> UIAction?
  func command(for action: Selector, propertyList: Any?) -> UICommand?
  func replace(menu replacedIdentifier: UIMenu.Identifier, with replacementMenu: UIMenu)
  func insertSibling(_ siblingMenu: UIMenu, beforeMenu siblingIdentifier: UIMenu.Identifier)
  func insertSibling(_ siblingMenu: UIMenu, afterMenu siblingIdentifier: UIMenu.Identifier)
  func insertChild(_ childMenu: UIMenu, atStartOfMenu parentIdentifier: UIMenu.Identifier)
  func insertChild(_ childMenu: UIMenu, atEndOfMenu parentIdentifier: UIMenu.Identifier)
  func remove(menu removedIdentifier: UIMenu.Identifier)
}

open class UIMenuSystem: NSObject, @unchecked Sendable {
  public static let main = UIMenuSystem()
  public static let context = UIMenuSystem()
  public func setNeedsRebuild() {}
  public func setNeedsRevalidate() {}
}

open class UIMenuElement: NSObject, NSCopying, @unchecked Sendable {
  public enum State: Int, Sendable {
    case off = 0
    case on = 1
    case mixed = 2
  }

  public struct Attributes: OptionSet, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let disabled = Attributes(rawValue: 1 << 0)
    public static let destructive = Attributes(rawValue: 1 << 1)
    public static let hidden = Attributes(rawValue: 1 << 2)
    public static let keepsMenuPresented = Attributes(rawValue: 1 << 3)
  }

  public var title: String
  public var subtitle: String?
  public var image: UIImage?

  public init(title: String = "", subtitle: String? = nil, image: UIImage? = nil) {
    self.title = title
    self.subtitle = subtitle
    self.image = image
    super.init()
  }

  open func copy(with zone: NSZone? = nil) -> Any { self }
}

public typealias UIActionHandler = @MainActor (UIAction) -> Void

open class UIAction: UIMenuElement, @unchecked Sendable {
  public struct Identifier: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let paste = Identifier("com.apple.menu.paste")
    public static let copy = Identifier("com.apple.menu.copy")
    public static let cut = Identifier("com.apple.menu.cut")
  }

  public let identifier: Identifier
  public var discoverabilityTitle: String?
  public var attributes: Attributes
  public var state: State
  public internal(set) weak var sender: AnyObject?
  private let handler: UIActionHandler

  public init(
    title: String = "",
    subtitle: String? = nil,
    image: UIImage? = nil,
    selectedImage: UIImage? = nil,
    identifier: Identifier? = nil,
    discoverabilityTitle: String? = nil,
    attributes: Attributes = [],
    state: State = .off,
    handler: @escaping UIActionHandler
  ) {
    self.identifier = identifier ?? Identifier(UUID().uuidString)
    self.discoverabilityTitle = discoverabilityTitle
    self.attributes = attributes
    self.state = state
    self.handler = handler
    super.init(title: title, subtitle: subtitle, image: image)
  }

  @MainActor
  public func performWithSender(_ sender: Any?, target: Any?) {
    guard !attributes.contains(.disabled) else { return }
    self.sender = sender as AnyObject?
    handler(self)
  }
}

open class UICommand: UIMenuElement, @unchecked Sendable {
  public let action: Selector
  public let propertyList: Any?
  public var discoverabilityTitle: String?
  public var attributes: Attributes
  public var state: State

  public init(
    title: String = "",
    image: UIImage? = nil,
    action: Selector,
    propertyList: Any? = nil,
    discoverabilityTitle: String? = nil,
    attributes: Attributes = [],
    state: State = .off
  ) {
    self.action = action
    self.propertyList = propertyList
    self.discoverabilityTitle = discoverabilityTitle
    self.attributes = attributes
    self.state = state
    super.init(title: title, image: image)
  }
}

open class UIKeyCommand: UICommand, @unchecked Sendable {
  public static let inputUpArrow = "UIKeyInputUpArrow"
  public static let inputDownArrow = "UIKeyInputDownArrow"
  public static let inputLeftArrow = "UIKeyInputLeftArrow"
  public static let inputRightArrow = "UIKeyInputRightArrow"
  public static let inputEscape = "UIKeyInputEscape"
  public static let inputPageUp = "UIKeyInputPageUp"
  public static let inputPageDown = "UIKeyInputPageDown"
  public static let inputHome = "UIKeyInputHome"
  public static let inputEnd = "UIKeyInputEnd"
  public static let inputDelete = "\u{8}"

  public let input: String?
  public let modifierFlags: UIKeyModifierFlags
  public var wantsPriorityOverSystemBehavior: Bool = false

  public init(
    title: String = "",
    image: UIImage? = nil,
    action: Selector,
    input: String,
    modifierFlags: UIKeyModifierFlags = [],
    propertyList: Any? = nil,
    alternates: [UICommand] = [],
    discoverabilityTitle: String? = nil,
    attributes: Attributes = [],
    state: State = .off
  ) {
    self.input = input
    self.modifierFlags = modifierFlags
    super.init(
      title: title,
      image: image,
      action: action,
      propertyList: propertyList,
      discoverabilityTitle: discoverabilityTitle,
      attributes: attributes,
      state: state
    )
  }

  public convenience init(input: String, modifierFlags: UIKeyModifierFlags, action: Selector) {
    self.init(title: "", action: action, input: input, modifierFlags: modifierFlags)
  }
}

open class UIDeferredMenuElement: UIMenuElement, @unchecked Sendable {
  private let elementProvider: (@escaping ([UIMenuElement]) -> Void) -> Void

  private init(provider: @escaping (@escaping ([UIMenuElement]) -> Void) -> Void) {
    self.elementProvider = provider
    super.init(title: "")
  }

  public static func uncached(_ elementProvider: @escaping (@escaping ([UIMenuElement]) -> Void) -> Void) -> UIDeferredMenuElement {
    UIDeferredMenuElement(provider: elementProvider)
  }

  public convenience init(_ elementProvider: @escaping (@escaping ([UIMenuElement]) -> Void) -> Void) {
    self.init(provider: elementProvider)
  }

  internal func resolveSynchronously() -> [UIMenuElement] {
    var resolved: [UIMenuElement] = []
    elementProvider { items in
      resolved = items
    }
    return resolved
  }
}

open class UIMenu: UIMenuElement, @unchecked Sendable {
  public struct Identifier: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let application = Identifier("com.apple.menu.application")
    public static let file = Identifier("com.apple.menu.file")
    public static let edit = Identifier("com.apple.menu.edit")
    public static let view = Identifier("com.apple.menu.view")
    public static let window = Identifier("com.apple.menu.window")
    public static let help = Identifier("com.apple.menu.help")
  }

  public struct Options: OptionSet, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let displayInline = Options(rawValue: 1 << 0)
    public static let destructive = Options(rawValue: 1 << 1)
    public static let singleSelection = Options(rawValue: 1 << 5)
    public static let displayAsPalette = Options(rawValue: 1 << 7)
  }

  public let identifier: Identifier
  public let options: Options
  public let children: [UIMenuElement]
  public var selectedElements: [UIMenuElement] {
    children.filter {
      ($0 as? UIAction)?.state == .on || ($0 as? UICommand)?.state == .on
    }
  }

  public init(
    title: String = "",
    subtitle: String? = nil,
    image: UIImage? = nil,
    identifier: Identifier? = nil,
    options: Options = [],
    children: [UIMenuElement] = []
  ) {
    self.identifier = identifier ?? Identifier(UUID().uuidString)
    self.options = options
    self.children = children
    super.init(title: title, subtitle: subtitle, image: image)
  }

  public func replacingChildren(_ newChildren: [UIMenuElement]) -> UIMenu {
    UIMenu(
      title: title,
      subtitle: subtitle,
      image: image,
      identifier: identifier,
      options: options,
      children: newChildren
    )
  }

  #if !os(macOS)
    @MainActor
    internal func buildNativeMenu(sender: Any?, retainBag: inout [AnyObject]) -> NativeAPI.Menu? {
      guard let nativeMenu = NativeAPI.Menu.create() else { return nil }
      var addedCount = 0
      populateNativeMenu(nativeMenu, elements: children, sender: sender, retainBag: &retainBag, addedCount: &addedCount)
      return nativeMenu
    }

    @MainActor
    private func populateNativeMenu(
      _ nativeMenu: NativeAPI.Menu,
      elements: [UIMenuElement],
      sender: Any?,
      retainBag: inout [AnyObject],
      addedCount: inout Int
    ) {
      for element in elements {
        if let deferred = element as? UIDeferredMenuElement {
          let sub = deferred.resolveSynchronously()
          populateNativeMenu(nativeMenu, elements: sub, sender: sender, retainBag: &retainBag, addedCount: &addedCount)
          continue
        }
        if let submenu = element as? UIMenu {
          if submenu.options.contains(.displayInline) {
            if addedCount > 0 {
              nativeMenu.addSeparator()
            }
            populateNativeMenu(nativeMenu, elements: submenu.children, sender: sender, retainBag: &retainBag, addedCount: &addedCount)
          } else if let item = NativeAPI.MenuItem.createWithLabelAndType(submenu.title, type: .submenu),
                    let subNative = submenu.buildNativeMenu(sender: sender, retainBag: &retainBag)
          {
            item.setSubmenu(subNative)
            nativeMenu.addItem(item)
            addedCount += 1
            retainBag.append(item)
            retainBag.append(subNative)
          }
          continue
        }
        if let act = element as? UIAction {
          if act.attributes.contains(.hidden) { continue }
          let itemType: NativeAPI.MenuItemType = (act.state != .off || options.contains(.singleSelection)) ? .checkbox : .normal
          guard let item = NativeAPI.MenuItem.createWithLabelAndType(act.title, type: itemType) else { continue }
          item.setEnabled(!act.attributes.contains(.disabled))
          if act.state == .on {
            item.setState(.checked)
          } else if act.state == .mixed {
            item.setState(.mixed)
          }
          if let icon = act.image?.toNativeImage() {
            item.setIcon(icon)
          }
          weak let weakSender = sender as AnyObject?
          _ = item.addListener { event in
            if case .itemClicked = event {
              DispatchQueue.main.async {
                MainActor.assumeIsolated {
                  act.performWithSender(weakSender, target: nil)
                }
              }
            }
          }
          nativeMenu.addItem(item)
          addedCount += 1
          retainBag.append(item)
        }
      }
    }
  #endif
}
