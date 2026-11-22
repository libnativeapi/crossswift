import CrossAppKit
import Foundation
#if !os(macOS)
  import CoreGraphics
  import NativeAPI
#endif
#if os(Windows)
  import CAppKitWindows
#endif

// MARK: - UIControl

@MainActor
open class UIControl: UIView {
  public struct Event: OptionSet, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let touchDown = Event(rawValue: 1 << 0)
    public static let touchDownRepeat = Event(rawValue: 1 << 1)
    public static let touchDragInside = Event(rawValue: 1 << 2)
    public static let touchDragOutside = Event(rawValue: 1 << 3)
    public static let touchDragEnter = Event(rawValue: 1 << 4)
    public static let touchDragExit = Event(rawValue: 1 << 5)
    public static let touchUpInside = Event(rawValue: 1 << 6)
    public static let touchUpOutside = Event(rawValue: 1 << 7)
    public static let touchCancel = Event(rawValue: 1 << 8)
    public static let valueChanged = Event(rawValue: 1 << 12)
    public static let primaryActionTriggered = Event(rawValue: 1 << 13)
    public static let menuActionTriggered = Event(rawValue: 1 << 14)
    public static let editingDidBegin = Event(rawValue: 1 << 16)
    public static let editingChanged = Event(rawValue: 1 << 17)
    public static let editingDidEnd = Event(rawValue: 1 << 18)
    public static let editingDidEndOnExit = Event(rawValue: 1 << 19)
    public static let allTouchEvents = Event(rawValue: 0x0000_0FFF)
    public static let allEditingEvents = Event(rawValue: 0x000F_0000)
    public static let allEvents = Event(rawValue: 0xFFFF_FFFF)
  }

  public struct State: OptionSet, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let normal = State([])
    public static let highlighted = State(rawValue: 1 << 0)
    public static let disabled = State(rawValue: 1 << 1)
    public static let selected = State(rawValue: 1 << 2)
    public static let focused = State(rawValue: 1 << 3)
    public static let application = State(rawValue: 0x00FF_0000)
    public static let reserved = State(rawValue: 0xFF00_0000)
  }

  public enum ContentVerticalAlignment: Int, Sendable {
    case center = 0
    case top = 1
    case bottom = 2
    case fill = 3
  }

  public enum ContentHorizontalAlignment: Int, Sendable {
    case center = 0
    case left = 1
    case right = 2
    case fill = 3
    case leading = 4
    case trailing = 5
  }

  private struct RegisteredHandler {
    weak var target: AnyObject?
    let selector: Selector?
    let action: UIAction?
    let events: Event
  }

  open var isEnabled: Bool = true {
    didSet {
      #if !os(macOS)
        ownedNativeView?.setEnabled(isEnabled)
      #endif
    }
  }
  open var isSelected: Bool = false
  open var isHighlighted: Bool = false
  public var contentVerticalAlignment: ContentVerticalAlignment = .center
  public var contentHorizontalAlignment: ContentHorizontalAlignment = .center
  public var showsMenuAsPrimaryAction: Bool = false
  public var isContextMenuInteractionEnabled: Bool = false
  public var toolTip: String? {
    didSet {
      #if !os(macOS)
        ownedNativeView?.setTooltip(toolTip)
      #endif
    }
  }

  open var state: State {
    var s: State = []
    if !isEnabled { s.insert(.disabled) }
    if isHighlighted { s.insert(.highlighted) }
    if isSelected { s.insert(.selected) }
    if isFirstResponder { s.insert(.focused) }
    return s
  }

  private var handlers: [RegisteredHandler] = []

  public override init(frame: CGRect) {
    super.init(frame: frame)
  }

  public convenience init(frame: CGRect, primaryAction: UIAction?) {
    self.init(frame: frame)
    if let primaryAction {
      addAction(primaryAction, for: .primaryActionTriggered)
    }
  }

  public required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  public func addTarget(_ target: Any?, action: Selector, for controlEvents: Event) {
    handlers.append(RegisteredHandler(
      target: target as AnyObject?,
      selector: action,
      action: nil,
      events: controlEvents
    ))
  }

  public func removeTarget(_ target: Any?, action: Selector?, for controlEvents: Event) {
    handlers.removeAll { entry in
      guard entry.action == nil else { return false }
      let matchTarget = (target == nil) || (entry.target === (target as AnyObject))
      let matchAction = (action == nil) || (entry.selector == action)
      let matchEvent = !entry.events.intersection(controlEvents).isEmpty
      return matchTarget && matchAction && matchEvent
    }
  }

  public func addAction(_ action: UIAction, for controlEvents: Event) {
    handlers.removeAll { $0.action?.identifier == action.identifier && $0.events == controlEvents }
    handlers.append(RegisteredHandler(target: nil, selector: nil, action: action, events: controlEvents))
  }

  public func removeAction(_ action: UIAction, for controlEvents: Event) {
    removeAction(identifiedBy: action.identifier, for: controlEvents)
  }

  public func removeAction(identifiedBy actionIdentifier: UIAction.Identifier, for controlEvents: Event) {
    handlers.removeAll {
      $0.action?.identifier == actionIdentifier && !$0.events.intersection(controlEvents).isEmpty
    }
  }

  public func enumerateEventHandlers(_ iterator: (UIAction?, (Any?, Selector)?, Event, inout Bool) -> Void) {
    var stop = false
    for h in handlers {
      if let act = h.action {
        iterator(act, nil, h.events, &stop)
      } else if let sel = h.selector {
        iterator(nil, (h.target, sel), h.events, &stop)
      }
      if stop { break }
    }
  }

  public func sendAction(_ action: UIAction) {
    guard isEnabled else { return }
    action.performWithSender(self, target: nil)
  }

  open func sendAction(_ action: Selector, to target: Any?, for event: UIEvent?) {
    _ = UIApplication.shared.sendAction(action, to: target, from: self, for: event)
  }

  public func sendActions(for controlEvents: Event) {
    guard isEnabled else { return }
    for h in handlers where !h.events.intersection(controlEvents).isEmpty {
      if let uiAction = h.action {
        uiAction.performWithSender(self, target: nil)
      } else if let sel = h.selector {
        sendAction(sel, to: h.target, for: nil)
      }
    }
  }

  open override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    super.touchesEnded(touches, with: event)
    guard isEnabled else { return }
    sendActions(for: [.touchUpInside, .primaryActionTriggered])
  }
}

// MARK: - UILabel

@MainActor
open class UILabel: UIView {
  public var text: String? {
    didSet {
      syncNativeLabel()
      invalidateIntrinsicContentSize()
    }
  }

  public var attributedText: NSAttributedString? {
    didSet {
      if let attr = attributedText {
        text = attr.string
      }
    }
  }

  public var font: UIFont! = .systemFont(ofSize: 17) {
    didSet {
      syncNativeLabel()
      invalidateIntrinsicContentSize()
    }
  }

  public var textColor: UIColor! = .label {
    didSet { syncNativeLabel() }
  }

  public var highlightedTextColor: UIColor?
  public var isHighlighted: Bool = false
  public var isEnabled: Bool = true
  public var textAlignment: NSTextAlignment = .natural {
    didSet { syncNativeLabel() }
  }
  public var lineBreakMode: NSLineBreakMode = .byTruncatingTail
  public var numberOfLines: Int = 1 {
    didSet { invalidateIntrinsicContentSize() }
  }
  public var adjustsFontSizeToFitWidth: Bool = false
  public var adjustsFontForContentSizeCategory: Bool = false
  public var minimumScaleFactor: CGFloat = 0
  public var allowsDefaultTighteningForTruncation: Bool = false
  public var preferredMaxLayoutWidth: CGFloat = 0

  public override init(frame: CGRect) {
    super.init(frame: frame)
    self.isUserInteractionEnabled = false
  }

  public required init?(coder: NSCoder) {
    super.init(coder: coder)
    self.isUserInteractionEnabled = false
  }

  open override var intrinsicContentSize: CGSize {
    sizeThatFits(CGSize(
      width: preferredMaxLayoutWidth > 0 ? preferredMaxLayoutWidth : CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    ))
  }

  open override func sizeThatFits(_ size: CGSize) -> CGSize {
    let content = text ?? ""
    guard !content.isEmpty else { return .zero }
    let resolvedFont = font ?? .systemFont(ofSize: 17)
    let lineH = max(18, resolvedFont.lineHeight)
    let charW = max(5, resolvedFont.pointSize * 0.54)
    let maxW = size.width.isFinite && size.width > 0 ? size.width : 1e6
    var totalLines: Int = 0
    var widest: CGFloat = 0
    for para in content.split(separator: "\n", omittingEmptySubsequences: false) {
      let pw = ceil(CGFloat(para.count) * charW)
      widest = max(widest, min(pw, maxW))
      let wrapped = numberOfLines == 1 ? 1 : max(1, Int(ceil(pw / maxW)))
      totalLines += wrapped
    }
    if numberOfLines > 0 {
      totalLines = min(totalLines, numberOfLines)
    }
    return CGSize(width: widest + 2, height: CGFloat(max(1, totalLines)) * lineH)
  }

  #if !os(macOS)
    open override var prefersNativeBacking: Bool { true }

    @discardableResult
    open override func ensureNativeView() -> NativeAPI.View? {
      if let existing = ownedNativeView { return existing }
      guard let lbl = NativeAPI.Label.create(text ?? "") else { return nil }
      ownedNativeView = lbl
      syncNativeFrame()
      syncNativeAppearance()
      syncNativeLabel()
      lbl.setVisible(!isHidden)
      return lbl
    }
  #endif

  internal func syncNativeLabel() {
    #if !os(macOS)
      guard let lbl = ownedNativeView as? NativeAPI.Label else { return }
      lbl.setText(text ?? "")
      if let f = font {
        lbl.setFontSize(Double(f.pointSize))
        lbl.setFontWeight(CInt(f.fontDescriptor.weight.cssWeight))
      }
      if let tc = textColor {
        let c = tc.resolved(for: traitCollection)
        lbl.setTextColor(NativeAPI.Color(
          r: UInt8(clamping: Int((c.r * 255).rounded())),
          g: UInt8(clamping: Int((c.g * 255).rounded())),
          b: UInt8(clamping: Int((c.b * 255).rounded())),
          a: UInt8(clamping: Int((c.a * 255).rounded()))
        ))
      }
      switch textAlignment {
      case .center: lbl.setTextAlignment(.center)
      case .right: lbl.setTextAlignment(.end)
      default: lbl.setTextAlignment(.start)
      }
    #endif
  }

  open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    syncNativeLabel()
  }
}

// MARK: - UIButton

@MainActor
open class UIButton: UIControl {
  public enum ButtonType: Int, Sendable {
    case custom = 0
    case system = 1
    case detailDisclosure = 2
    case infoLight = 3
    case infoDark = 4
    case contactAdd = 5
    case plain = 6
    case close = 7
  }

  public enum Role: Int, Sendable {
    case normal = 0
    case primary = 1
    case cancel = 2
    case destructive = 3
  }

  public struct Configuration: Equatable, Sendable {
    public enum Size: Int, Sendable {
      case mini = 0
      case small = 1
      case medium = 2
      case large = 3
    }

    public enum CornerStyle: Int, Sendable {
      case fixed = -1
      case `dynamic` = 0
      case small = 1
      case medium = 2
      case large = 3
      case capsule = 4
    }

    public var title: String?
    public var subtitle: String?
    public var image: UIImage?
    public var imagePlacement: NSDirectionalRectEdge = .leading
    public var imagePadding: CGFloat = 6
    public var titlePadding: CGFloat = 2
    public var contentInsets: NSDirectionalEdgeInsets = NSDirectionalEdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12)
    public var buttonSize: Size = .medium
    public var cornerStyle: CornerStyle = .dynamic
    public var baseForegroundColor: UIColor?
    public var baseBackgroundColor: UIColor?
    public var showsActivityIndicator: Bool = false
    internal let styleKind: String

    internal init(styleKind: String) {
      self.styleKind = styleKind
    }

    public static func plain() -> Configuration { Configuration(styleKind: "plain") }
    public static func tinted() -> Configuration { Configuration(styleKind: "tinted") }
    public static func gray() -> Configuration { Configuration(styleKind: "gray") }
    public static func filled() -> Configuration { Configuration(styleKind: "filled") }
    public static func borderless() -> Configuration { Configuration(styleKind: "borderless") }
    public static func bordered() -> Configuration { Configuration(styleKind: "bordered") }
    public static func borderedTinted() -> Configuration { Configuration(styleKind: "borderedTinted") }
    public static func borderedProminent() -> Configuration { Configuration(styleKind: "borderedProminent") }
  }

  public typealias ConfigurationUpdateHandler = (UIButton) -> Void

  public let buttonType: ButtonType
  public var role: Role = .normal
  public var changesSelectionAsPrimaryAction: Bool = false
  public var configurationUpdateHandler: ConfigurationUpdateHandler?

  public var configuration: Configuration? {
    didSet {
      if let cfgTitle = configuration?.title {
        titlesByState[State.normal.rawValue] = cfgTitle
        titleLabel?.text = cfgTitle
      }
      if let cfgImg = configuration?.image {
        imagesByState[State.normal.rawValue] = cfgImg
        imageView?.image = cfgImg
      }
      syncNativeButton()
      invalidateIntrinsicContentSize()
    }
  }

  public var menu: UIMenu?
  public let titleLabel: UILabel? = UILabel(frame: .zero)
  public let imageView: UIImageView? = UIImageView(frame: .zero)

  private var titlesByState: [UInt: String] = [:]
  private var attributedTitlesByState: [UInt: NSAttributedString] = [:]
  private var titleColorsByState: [UInt: UIColor] = [:]
  private var imagesByState: [UInt: UIImage] = [:]
  private var backgroundImagesByState: [UInt: UIImage] = [:]
  #if !os(macOS)
    private var nativeListener: ListenerId?
    private var activeMenuRetainBag: [AnyObject] = []
  #endif

  public init(type buttonType: ButtonType) {
    self.buttonType = buttonType
    super.init(frame: .zero)
    titleLabel?.font = .systemFont(ofSize: 15, weight: .medium)
  }

  public convenience override init(frame: CGRect) {
    self.init(type: .custom)
    self.frame = frame
  }

  public convenience init(type buttonType: ButtonType = .system, primaryAction: UIAction?) {
    self.init(type: buttonType)
    if let primaryAction {
      if !primaryAction.title.isEmpty {
        setTitle(primaryAction.title, for: .normal)
      }
      if let img = primaryAction.image {
        setImage(img, for: .normal)
      }
      addAction(primaryAction, for: .primaryActionTriggered)
    }
  }

  public convenience init(configuration: Configuration, primaryAction: UIAction? = nil) {
    self.init(type: .system, primaryAction: primaryAction)
    self.configuration = configuration
    if let primaryAction, configuration.title == nil && !primaryAction.title.isEmpty {
      self.configuration?.title = primaryAction.title
    }
  }

  public static func systemButton(with image: UIImage, target: Any?, action: Selector?) -> UIButton {
    let b = UIButton(type: .system)
    b.setImage(image, for: .normal)
    if let action { b.addTarget(target, action: action, for: .touchUpInside) }
    return b
  }

  public required init?(coder: NSCoder) {
    self.buttonType = .system
    super.init(coder: coder)
  }

  public var currentTitle: String? {
    title(for: state) ?? title(for: .normal) ?? configuration?.title
  }

  public var currentImage: UIImage? {
    image(for: state) ?? image(for: .normal) ?? configuration?.image
  }

  public var currentTitleColor: UIColor {
    titleColor(for: state) ?? titleColor(for: .normal) ?? configuration?.baseForegroundColor ?? tintColor
  }

  public func setTitle(_ title: String?, for state: State) {
    if let title {
      titlesByState[state.rawValue] = title
    } else {
      titlesByState.removeValue(forKey: state.rawValue)
    }
    if state == .normal { titleLabel?.text = title }
    syncNativeButton()
    invalidateIntrinsicContentSize()
  }

  public func title(for state: State) -> String? {
    titlesByState[state.rawValue] ?? (state == .normal ? configuration?.title : nil)
  }

  public func setAttributedTitle(_ title: NSAttributedString?, for state: State) {
    if let title {
      attributedTitlesByState[state.rawValue] = title
      titlesByState[state.rawValue] = title.string
    } else {
      attributedTitlesByState.removeValue(forKey: state.rawValue)
    }
    syncNativeButton()
    invalidateIntrinsicContentSize()
  }

  public func attributedTitle(for state: State) -> NSAttributedString? {
    attributedTitlesByState[state.rawValue]
  }

  public func setTitleColor(_ color: UIColor?, for state: State) {
    if let color {
      titleColorsByState[state.rawValue] = color
    } else {
      titleColorsByState.removeValue(forKey: state.rawValue)
    }
  }

  public func titleColor(for state: State) -> UIColor? {
    titleColorsByState[state.rawValue]
  }

  public func setImage(_ image: UIImage?, for state: State) {
    if let image {
      imagesByState[state.rawValue] = image
    } else {
      imagesByState.removeValue(forKey: state.rawValue)
    }
    if state == .normal { imageView?.image = image }
    invalidateIntrinsicContentSize()
  }

  public func image(for state: State) -> UIImage? {
    imagesByState[state.rawValue]
  }

  public func setBackgroundImage(_ image: UIImage?, for state: State) {
    if let image {
      backgroundImagesByState[state.rawValue] = image
    } else {
      backgroundImagesByState.removeValue(forKey: state.rawValue)
    }
  }

  public func backgroundImage(for state: State) -> UIImage? {
    backgroundImagesByState[state.rawValue]
  }

  public func setNeedsUpdateConfiguration() {
    configurationUpdateHandler?(self)
  }

  open func updateConfiguration() {
    configurationUpdateHandler?(self)
  }

  open override var intrinsicContentSize: CGSize {
    let labelText = currentTitle ?? ""
    let font = titleLabel?.font ?? .systemFont(ofSize: 15, weight: .medium)
    let textW = CGFloat(labelText.count) * font.pointSize * 0.56
    let iconW: CGFloat = currentImage != nil ? 20 : 0
    let padH: CGFloat = configuration.map { $0.contentInsets.leading + $0.contentInsets.trailing } ?? 24
    let padV: CGFloat = configuration.map { $0.contentInsets.top + $0.contentInsets.bottom } ?? 12
    return CGSize(
      width: max(44, ceil(textW + iconW + padH)),
      height: max(32, ceil(font.lineHeight + padV))
    )
  }

  open override func sizeThatFits(_ size: CGSize) -> CGSize {
    intrinsicContentSize
  }

  #if !os(macOS)
    open override var prefersNativeBacking: Bool { true }

    @discardableResult
    open override func ensureNativeView() -> NativeAPI.View? {
      if let existing = ownedNativeView { return existing }
      guard let btn = NativeAPI.Button.create(currentTitle ?? "") else { return nil }
      ownedNativeView = btn
      syncNativeFrame()
      syncNativeButton()
      btn.setVisible(!isHidden)
      btn.setEnabled(isEnabled)
      nativeListener = btn.addListener { [weak self] event in
        guard case .buttonClicked = event else { return }
        DispatchQueue.main.async {
          MainActor.assumeIsolated {
            self?.handleNativeButtonClicked()
          }
        }
      }
      return btn
    }

    private func handleNativeButtonClicked() {
      guard isEnabled else { return }
      if changesSelectionAsPrimaryAction {
        isSelected.toggle()
      }
      if showsMenuAsPrimaryAction, let menu {
        activeMenuRetainBag.removeAll()
        if let nativeMenu = menu.buildNativeMenu(sender: self, retainBag: &activeMenuRetainBag),
           let strat = NativeAPI.PositioningStrategy.cursorPosition()
        {
          sendActions(for: .menuActionTriggered)
          _ = nativeMenu.open(strat, placement: .bottomStart)
          return
        }
      }
      sendActions(for: [.touchUpInside, .primaryActionTriggered])
    }
  #endif

  private func syncNativeButton() {
    #if !os(macOS)
      guard let btn = ownedNativeView as? NativeAPI.Button else { return }
      btn.setText(currentTitle ?? "")
      if let f = titleLabel?.font {
        btn.setFontSize(Double(f.pointSize))
        btn.setFontWeight(CInt(f.fontDescriptor.weight.cssWeight))
      }
      btn.setEnabled(isEnabled)
    #endif
  }
}

// MARK: - Text Input Traits & UITextField

public enum UIKeyboardType: Int, Sendable {
  case `default` = 0
  case asciiCapable = 1
  case numbersAndPunctuation = 2
  case URL = 3
  case numberPad = 4
  case phonePad = 5
  case namePhonePad = 6
  case emailAddress = 7
  case decimalPad = 8
  case twitter = 9
  case webSearch = 10
  case asciiCapableNumberPad = 11
}

public enum UIReturnKeyType: Int, Sendable {
  case `default` = 0
  case go = 1
  case google = 2
  case join = 3
  case next = 4
  case route = 5
  case search = 6
  case send = 7
  case yahoo = 8
  case done = 9
  case emergencyCall = 10
  case `continue` = 11
}

public enum UITextAutocapitalizationType: Int, Sendable {
  case none = 0
  case words = 1
  case sentences = 2
  case allCharacters = 3
}

public enum UITextAutocorrectionType: Int, Sendable {
  case `default` = 0
  case no = 1
  case yes = 2
}

public enum UITextSpellCheckingType: Int, Sendable {
  case `default` = 0
  case no = 1
  case yes = 2
}

public enum UITextSmartQuotesType: Int, Sendable {
  case `default` = 0
  case no = 1
  case yes = 2
}

public enum UITextSmartDashesType: Int, Sendable {
  case `default` = 0
  case no = 1
  case yes = 2
}

public struct UITextContentType: RawRepresentable, Equatable, Hashable, Sendable {
  public let rawValue: String
  public init(rawValue: String) { self.rawValue = rawValue }
  public static let username = UITextContentType(rawValue: "username")
  public static let password = UITextContentType(rawValue: "password")
  public static let newPassword = UITextContentType(rawValue: "new-password")
  public static let oneTimeCode = UITextContentType(rawValue: "one-time-code")
  public static let emailAddress = UITextContentType(rawValue: "email")
  public static let name = UITextContentType(rawValue: "name")
  public static let telephoneNumber = UITextContentType(rawValue: "tel")
  public static let URL = UITextContentType(rawValue: "url")
}

@MainActor
public protocol UITextFieldDelegate: NSObjectProtocol {
  func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool
  func textFieldDidBeginEditing(_ textField: UITextField)
  func textFieldShouldEndEditing(_ textField: UITextField) -> Bool
  func textFieldDidEndEditing(_ textField: UITextField)
  func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool
  func textFieldShouldClear(_ textField: UITextField) -> Bool
  func textFieldShouldReturn(_ textField: UITextField) -> Bool
  func textFieldDidChangeSelection(_ textField: UITextField)
}

extension UITextFieldDelegate {
  public func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool { true }
  public func textFieldDidBeginEditing(_ textField: UITextField) {}
  public func textFieldShouldEndEditing(_ textField: UITextField) -> Bool { true }
  public func textFieldDidEndEditing(_ textField: UITextField) {}
  public func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool { true }
  public func textFieldShouldClear(_ textField: UITextField) -> Bool { true }
  public func textFieldShouldReturn(_ textField: UITextField) -> Bool { true }
  public func textFieldDidChangeSelection(_ textField: UITextField) {}
}

@MainActor
open class UITextField: UIControl {
  public enum BorderStyle: Int, Sendable {
    case none = 0
    case line = 1
    case bezel = 2
    case roundedRect = 3
  }

  public enum ViewMode: Int, Sendable {
    case never = 0
    case whileEditing = 1
    case unlessEditing = 2
    case always = 3
  }

  public static let textDidBeginEditingNotification = Notification.Name("UITextFieldTextDidBeginEditingNotification")
  public static let textDidChangeNotification = Notification.Name("UITextFieldTextDidChangeNotification")
  public static let textDidEndEditingNotification = Notification.Name("UITextFieldTextDidEndEditingNotification")

  public weak var delegate: (any UITextFieldDelegate)?
  private var isSyncingNativeText = false

  public var text: String? = "" {
    didSet {
      guard !isSyncingNativeText else { return }
      syncNativeTextField()
    }
  }

  public var attributedText: NSAttributedString? {
    get { text.map { NSAttributedString(string: $0) } }
    set { text = newValue?.string }
  }

  public var placeholder: String? {
    didSet { syncNativeTextField() }
  }

  public var attributedPlaceholder: NSAttributedString? {
    didSet {
      if let attr = attributedPlaceholder { placeholder = attr.string }
    }
  }

  public var font: UIFont? = .systemFont(ofSize: 15) {
    didSet { syncNativeTextField(); invalidateIntrinsicContentSize() }
  }
  public var textColor: UIColor? = .label {
    didSet { syncNativeTextField() }
  }
  public var textAlignment: NSTextAlignment = .natural
  public var borderStyle: BorderStyle = .none {
    didSet { syncNativeTextField() }
  }
  public var clearsOnBeginEditing: Bool = false
  public var adjustsFontSizeToFitWidth: Bool = false
  public var minimumFontSize: CGFloat = 0
  public var clearButtonMode: ViewMode = .never
  public var leftView: UIView?
  public var leftViewMode: ViewMode = .never
  public var rightView: UIView?
  public var rightViewMode: ViewMode = .never
  public var inputView: UIView?
  public var inputAccessoryView: UIView?
  public private(set) var isEditing: Bool = false

  public var autocapitalizationType: UITextAutocapitalizationType = .sentences
  public var autocorrectionType: UITextAutocorrectionType = .default
  public var spellCheckingType: UITextSpellCheckingType = .default
  public var smartQuotesType: UITextSmartQuotesType = .default
  public var smartDashesType: UITextSmartDashesType = .default
  public var keyboardType: UIKeyboardType = .default
  public var returnKeyType: UIReturnKeyType = .default
  public var textContentType: UITextContentType?
  public var isSecureTextEntry: Bool = false {
    didSet { syncNativeTextField() }
  }

  #if !os(macOS)
    private var nativeListener: ListenerId?
  #endif

  open override var canBecomeFirstResponder: Bool { isEnabled }

  @discardableResult
  open override func becomeFirstResponder() -> Bool {
    if let delegate, !delegate.textFieldShouldBeginEditing(self) { return false }
    guard super.becomeFirstResponder() else { return false }
    isEditing = true
    if clearsOnBeginEditing { text = "" }
    #if !os(macOS)
      (ownedNativeView as? NativeAPI.TextField)?.focus()
    #endif
    delegate?.textFieldDidBeginEditing(self)
    sendActions(for: .editingDidBegin)
    NotificationCenter.default.post(name: Self.textDidBeginEditingNotification, object: self)
    return true
  }

  @discardableResult
  open override func resignFirstResponder() -> Bool {
    if let delegate, !delegate.textFieldShouldEndEditing(self) { return false }
    guard super.resignFirstResponder() else { return false }
    isEditing = false
    delegate?.textFieldDidEndEditing(self)
    sendActions(for: .editingDidEnd)
    NotificationCenter.default.post(name: Self.textDidEndEditingNotification, object: self)
    return true
  }

  open override var intrinsicContentSize: CGSize {
    let f = font ?? .systemFont(ofSize: 15)
    return CGSize(width: 160, height: max(32, ceil(f.lineHeight + 10)))
  }

  open override func sizeThatFits(_ size: CGSize) -> CGSize {
    let intrinsic = intrinsicContentSize
    return CGSize(
      width: size.width.isFinite && size.width > 0 ? size.width : intrinsic.width,
      height: intrinsic.height
    )
  }

  #if !os(macOS)
    open override var prefersNativeBacking: Bool { true }

    @discardableResult
    open override func ensureNativeView() -> NativeAPI.View? {
      if let existing = ownedNativeView { return existing }
      guard let tf = NativeAPI.TextField.create(text ?? "") else { return nil }
      ownedNativeView = tf
      syncNativeFrame()
      syncNativeAppearance()
      syncNativeTextField()
      tf.setVisible(!isHidden)
      tf.setEnabled(isEnabled)
      nativeListener = tf.addListener { [weak self] event in
        guard let self else { return }
        switch event {
        case .textFieldChanged(_, let raw):
          let newText = raw ?? ""
          MainActor.assumeIsolated {
            guard !self.isSyncingNativeText else { return }
            let oldText = self.text ?? ""
            if let delegate = self.delegate {
              let fullRange = NSRange(location: 0, length: (oldText as NSString).length)
              if !delegate.textField(self, shouldChangeCharactersIn: fullRange, replacementString: newText) {
                self.syncNativeTextField()
                return
              }
            }
            self.isSyncingNativeText = true
            self.text = newText
            self.isSyncingNativeText = false
            self.sendActions(for: [.editingChanged, .valueChanged])
            NotificationCenter.default.post(name: Self.textDidChangeNotification, object: self)
          }
        case .textFieldSubmitted:
          MainActor.assumeIsolated {
            let allow = self.delegate?.textFieldShouldReturn(self) ?? true
            if allow {
              self.sendActions(for: [.editingDidEndOnExit, .primaryActionTriggered])
            }
          }
        case .focused:
          MainActor.assumeIsolated {
            self.isEditing = true
            self.isFirstResponder = true
            self.delegate?.textFieldDidBeginEditing(self)
            self.sendActions(for: .editingDidBegin)
          }
        case .blurred:
          MainActor.assumeIsolated {
            self.isEditing = false
            self.isFirstResponder = false
            self.delegate?.textFieldDidEndEditing(self)
            self.sendActions(for: .editingDidEnd)
          }
        default:
          break
        }
      }
      return tf
    }
  #endif

  private func syncNativeTextField() {
    #if !os(macOS)
      guard let tf = ownedNativeView as? NativeAPI.TextField else { return }
      let desired = text ?? ""
      if tf.text != desired {
        isSyncingNativeText = true
        tf.setText(desired)
        isSyncingNativeText = false
      }
      tf.setPlaceholder(placeholder)
      tf.setBordered(borderStyle != .none)
      tf.setSecure(isSecureTextEntry)
      tf.setEditable(isEnabled)
      tf.setEnabled(isEnabled)
      if let f = font {
        tf.setFontSize(Double(f.pointSize))
      }
      if let tc = textColor {
        let c = tc.resolved(for: traitCollection)
        tf.setTextColor(NativeAPI.Color(
          r: UInt8(clamping: Int((c.r * 255).rounded())),
          g: UInt8(clamping: Int((c.g * 255).rounded())),
          b: UInt8(clamping: Int((c.b * 255).rounded())),
          a: UInt8(clamping: Int((c.a * 255).rounded()))
        ))
      }
    #endif
  }

  open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    syncNativeTextField()
  }
}

// MARK: - UIScrollView & UIRefreshControl

@MainActor
public protocol UIScrollViewDelegate: NSObjectProtocol {
  func scrollViewDidScroll(_ scrollView: UIScrollView)
  func scrollViewWillBeginDragging(_ scrollView: UIScrollView)
  func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool)
  func scrollViewDidEndDecelerating(_ scrollView: UIScrollView)
  func viewForZooming(in scrollView: UIScrollView) -> UIView?
  func scrollViewDidZoom(_ scrollView: UIScrollView)
}

extension UIScrollViewDelegate {
  public func scrollViewDidScroll(_ scrollView: UIScrollView) {}
  public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {}
  public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {}
  public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {}
  public func viewForZooming(in scrollView: UIScrollView) -> UIView? { nil }
  public func scrollViewDidZoom(_ scrollView: UIScrollView) {}
}

@MainActor
open class UIRefreshControl: UIControl {
  public private(set) var isRefreshing: Bool = false
  public var attributedTitle: NSAttributedString?

  public override init(frame: CGRect) {
    super.init(frame: frame)
  }

  public convenience init() {
    self.init(frame: CGRect(x: 0, y: 0, width: 32, height: 32))
  }

  public required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  open func beginRefreshing() {
    isRefreshing = true
  }

  open func endRefreshing() {
    isRefreshing = false
  }
}

@MainActor
open class UIScrollView: UIView {
  public enum IndicatorStyle: Int, Sendable {
    case `default` = 0
    case black = 1
    case white = 2
  }

  public enum KeyboardDismissMode: Int, Sendable {
    case none = 0
    case onDrag = 1
    case interactive = 2
    case onDragWithAccessory = 3
    case interactiveWithAccessory = 4
  }

  public struct DecelerationRate: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: CGFloat
    public init(rawValue: CGFloat) { self.rawValue = rawValue }
    public static let normal = DecelerationRate(rawValue: 0.998)
    public static let fast = DecelerationRate(rawValue: 0.990)
  }

  public weak var delegate: (any UIScrollViewDelegate)?
  public var contentOffset: CGPoint = .zero {
    didSet {
      bounds.origin = contentOffset
      delegate?.scrollViewDidScroll(self)
    }
  }
  public var contentSize: CGSize = .zero
  public var contentInset: UIEdgeInsets = .zero
  public var adjustedContentInset: UIEdgeInsets {
    guard contentInsetAdjustmentBehavior != .never else { return contentInset }
    return UIEdgeInsets(
      top: contentInset.top + safeAreaInsets.top,
      left: contentInset.left + safeAreaInsets.left,
      bottom: contentInset.bottom + safeAreaInsets.bottom,
      right: contentInset.right + safeAreaInsets.right
    )
  }
  public var contentInsetAdjustmentBehavior: ContentInsetAdjustmentBehavior = .automatic
  public var isDirectionalLockEnabled: Bool = false
  public var bounces: Bool = true
  public var alwaysBounceVertical: Bool = false
  public var alwaysBounceHorizontal: Bool = false
  public var isPagingEnabled: Bool = false
  public var isScrollEnabled: Bool = true
  public var showsVerticalScrollIndicator: Bool = true
  public var showsHorizontalScrollIndicator: Bool = true
  public var indicatorStyle: IndicatorStyle = .default
  public var decelerationRate: DecelerationRate = .normal
  public var keyboardDismissMode: KeyboardDismissMode = .none
  public private(set) var isTracking: Bool = false
  public private(set) var isDragging: Bool = false
  public private(set) var isDecelerating: Bool = false
  public var minimumZoomScale: CGFloat = 1.0
  public var maximumZoomScale: CGFloat = 1.0
  public var zoomScale: CGFloat = 1.0
  public var refreshControl: UIRefreshControl?

  private lazy var _contentGuide = UILayoutGuide(kind: .custom, owningView: self)
  private lazy var _frameGuide = UILayoutGuide(kind: .custom, owningView: self)
  public var contentLayoutGuide: UILayoutGuide { _contentGuide }
  public var frameLayoutGuide: UILayoutGuide { _frameGuide }

  public override init(frame: CGRect) {
    super.init(frame: frame)
    self.clipsToBounds = true
  }

  public required init?(coder: NSCoder) {
    super.init(coder: coder)
    self.clipsToBounds = true
  }

  open func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
    self.contentOffset = contentOffset
  }

  open func scrollRectToVisible(_ rect: CGRect, animated: Bool) {
    var next = contentOffset
    let vis = CGRect(origin: contentOffset, size: bounds.size)
    if rect.maxY > vis.maxY { next.y = rect.maxY - bounds.height }
    if rect.minY < vis.minY { next.y = rect.minY }
    if rect.maxX > vis.maxX { next.x = rect.maxX - bounds.width }
    if rect.minX < vis.minX { next.x = rect.minX }
    setContentOffset(next, animated: animated)
  }
}

// MARK: - UITextView

@MainActor
public protocol UITextViewDelegate: UIScrollViewDelegate {
  func textViewShouldBeginEditing(_ textView: UITextView) -> Bool
  func textViewDidBeginEditing(_ textView: UITextView)
  func textViewShouldEndEditing(_ textView: UITextView) -> Bool
  func textViewDidEndEditing(_ textView: UITextView)
  func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool
  func textViewDidChange(_ textView: UITextView)
  func textViewDidChangeSelection(_ textView: UITextView)
}

extension UITextViewDelegate {
  public func textViewShouldBeginEditing(_ textView: UITextView) -> Bool { true }
  public func textViewDidBeginEditing(_ textView: UITextView) {}
  public func textViewShouldEndEditing(_ textView: UITextView) -> Bool { true }
  public func textViewDidEndEditing(_ textView: UITextView) {}
  public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool { true }
  public func textViewDidChange(_ textView: UITextView) {}
  public func textViewDidChangeSelection(_ textView: UITextView) {}
}

@MainActor
open class UITextView: UIScrollView {
  public static let textDidBeginEditingNotification = Notification.Name("UITextViewTextDidBeginEditingNotification")
  public static let textDidChangeNotification = Notification.Name("UITextViewTextDidChangeNotification")
  public static let textDidEndEditingNotification = Notification.Name("UITextViewTextDidEndEditingNotification")

  private weak var textDelegate: (any UITextViewDelegate)?
  public override var delegate: (any UIScrollViewDelegate)? {
    get { textDelegate }
    set { textDelegate = newValue as? any UITextViewDelegate }
  }

  public let textStorage: NSTextStorage
  public let layoutManager: NSLayoutManager
  public let textContainer: NSTextContainer
  private var isSyncingNativeEditor = false

  public var text: String! {
    get { textStorage.string }
    set {
      let replacement = newValue ?? ""
      textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: replacement)
      if !isSyncingNativeEditor { syncNativeTextView() }
    }
  }

  public var attributedText: NSAttributedString! {
    get { NSAttributedString(attributedString: textStorage) }
    set {
      textStorage.setAttributedString(newValue ?? NSAttributedString(string: ""))
      if !isSyncingNativeEditor { syncNativeTextView() }
    }
  }

  public var font: UIFont? = .systemFont(ofSize: 15) {
    didSet { syncNativeTextView() }
  }
  public var textColor: UIColor? = .label {
    didSet { syncNativeTextView() }
  }
  public var textAlignment: NSTextAlignment = .natural
  public var selectedRange: NSRange = NSRange(location: 0, length: 0)
  public var isEditable: Bool = true {
    didSet { syncNativeTextView() }
  }
  public var isSelectable: Bool = true
  public var textContainerInset: UIEdgeInsets = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
  public var typingAttributes: [NSAttributedString.Key: Any] = [:]
  public var linkTextAttributes: [NSAttributedString.Key: Any]! = [:]

  public var autocapitalizationType: UITextAutocapitalizationType = .sentences
  public var autocorrectionType: UITextAutocorrectionType = .default
  public var keyboardType: UIKeyboardType = .default
  public var returnKeyType: UIReturnKeyType = .default

  #if !os(macOS)
    private var nativeListener: ListenerId?
  #endif

  public init(frame: CGRect, textContainer: NSTextContainer?) {
    let resolvedContainer = textContainer ?? NSTextContainer(size: CGSize(width: max(frame.width, 100), height: 1e7))
    let lm = resolvedContainer.layoutManager ?? NSLayoutManager()
    if resolvedContainer.layoutManager == nil { lm.addTextContainer(resolvedContainer) }
    let storage = lm.textStorage ?? NSTextStorage()
    if lm.textStorage == nil { storage.addLayoutManager(lm) }
    self.textStorage = storage
    self.layoutManager = lm
    self.textContainer = resolvedContainer
    super.init(frame: frame)
  }

  public convenience override init(frame: CGRect) {
    self.init(frame: frame, textContainer: nil)
  }

  public convenience init(usingTextLayoutManager: Bool) {
    self.init(frame: .zero, textContainer: nil)
  }

  public required init?(coder: NSCoder) {
    let storage = NSTextStorage()
    let lm = NSLayoutManager()
    let container = NSTextContainer()
    storage.addLayoutManager(lm)
    lm.addTextContainer(container)
    self.textStorage = storage
    self.layoutManager = lm
    self.textContainer = container
    super.init(coder: coder)
  }

  open override var canBecomeFirstResponder: Bool { isEditable || isSelectable }

  open override var intrinsicContentSize: CGSize {
    CGSize(width: UIView.noIntrinsicMetric, height: 96)
  }

  #if !os(macOS)
    open override var prefersNativeBacking: Bool { true }

    @discardableResult
    open override func ensureNativeView() -> NativeAPI.View? {
      if let existing = ownedNativeView { return existing }
      let initial = textStorage.string.replacingOccurrences(of: "\n", with: "\r\n")
      guard let tf = NativeAPI.TextField.create(initial) else { return nil }
      tf.setMultiline(true)
      tf.setBordered(true)
      ownedNativeView = tf
      syncNativeFrame()
      syncNativeAppearance()
      syncNativeTextView()
      tf.setVisible(!isHidden)
      nativeListener = tf.addListener { [weak self] event in
        guard let self else { return }
        if case let .textFieldChanged(_, raw) = event {
          let normalized = (raw ?? "").replacingOccurrences(of: "\r\n", with: "\n")
          MainActor.assumeIsolated {
            guard !self.isSyncingNativeEditor else { return }
            if self.textStorage.string != normalized {
              self.isSyncingNativeEditor = true
              self.textStorage.replaceCharacters(
                in: NSRange(location: 0, length: self.textStorage.length),
                with: normalized
              )
              self.isSyncingNativeEditor = false
              self.textDelegate?.textViewDidChange(self)
              NotificationCenter.default.post(name: Self.textDidChangeNotification, object: self)
            }
          }
        }
      }
      return tf
    }
  #endif

  private func syncNativeTextView() {
    #if !os(macOS)
      guard let tf = ownedNativeView as? NativeAPI.TextField else { return }
      let desired = textStorage.string.replacingOccurrences(of: "\n", with: "\r\n")
      if tf.text != desired {
        isSyncingNativeEditor = true
        tf.setText(desired)
        isSyncingNativeEditor = false
      }
      tf.setEditable(isEditable)
      if let f = font {
        tf.setFontSize(Double(f.pointSize))
        if f.fontName.lowercased().contains("mono") || f.fontName.lowercased().contains("cascadia") {
          tf.setFontFamily("Consolas")
        }
      }
      if let tc = textColor {
        let c = tc.resolved(for: traitCollection)
        tf.setTextColor(NativeAPI.Color(
          r: UInt8(clamping: Int((c.r * 255).rounded())),
          g: UInt8(clamping: Int((c.g * 255).rounded())),
          b: UInt8(clamping: Int((c.b * 255).rounded())),
          a: UInt8(clamping: Int((c.a * 255).rounded()))
        ))
      }
    #endif
  }

  open override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
    super.traitCollectionDidChange(previousTraitCollection)
    syncNativeTextView()
  }
}

// MARK: - UIImageView & Value Controls

@MainActor
open class UIImageView: UIView {
  public var image: UIImage? {
    didSet { invalidateIntrinsicContentSize() }
  }
  public var highlightedImage: UIImage?
  public var isHighlighted: Bool = false
  public var animationImages: [UIImage]?
  public var highlightedAnimationImages: [UIImage]?
  public var animationDuration: TimeInterval = 0
  public var animationRepeatCount: Int = 0
  public private(set) var isAnimating: Bool = false
  public var preferredSymbolConfiguration: UIImage.SymbolConfiguration?

  public init(image: UIImage?, highlightedImage: UIImage? = nil) {
    self.image = image
    self.highlightedImage = highlightedImage
    super.init(frame: CGRect(origin: .zero, size: image?.size ?? .zero))
    self.isUserInteractionEnabled = false
  }

  public override init(frame: CGRect) {
    super.init(frame: frame)
    self.isUserInteractionEnabled = false
  }

  public required init?(coder: NSCoder) {
    super.init(coder: coder)
    self.isUserInteractionEnabled = false
  }

  open override var intrinsicContentSize: CGSize {
    image?.size ?? CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
  }

  open func startAnimating() { isAnimating = true }
  open func stopAnimating() { isAnimating = false }
}

@MainActor
open class UISwitch: UIControl {
  public enum Style: Int, Sendable {
    case automatic = 0
    case checkbox = 1
    case sliding = 2
  }

  public var isOn: Bool = false
  public var onTintColor: UIColor?
  public var thumbTintColor: UIColor?
  public var title: String?
  public var preferredStyle: Style = .automatic

  public override init(frame: CGRect) {
    super.init(frame: CGRect(origin: frame.origin, size: CGSize(width: 51, height: 31)))
  }

  public required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  public func setOn(_ on: Bool, animated: Bool) {
    isOn = on
  }

  open override var intrinsicContentSize: CGSize {
    CGSize(width: 51, height: 31)
  }
}

@MainActor
open class UISlider: UIControl {
  public var value: Float = 0.0 {
    didSet { value = min(max(value, minimumValue), maximumValue) }
  }
  public var minimumValue: Float = 0.0
  public var maximumValue: Float = 1.0
  public var minimumValueImage: UIImage?
  public var maximumValueImage: UIImage?
  public var isContinuous: Bool = true
  public var minimumTrackTintColor: UIColor?
  public var maximumTrackTintColor: UIColor?
  public var thumbTintColor: UIColor?

  public func setValue(_ value: Float, animated: Bool) {
    self.value = min(max(value, minimumValue), maximumValue)
  }

  open override var intrinsicContentSize: CGSize {
    CGSize(width: UIView.noIntrinsicMetric, height: 30)
  }
}

@MainActor
open class UIStepper: UIControl {
  public var isContinuous: Bool = true
  public var autorepeat: Bool = true
  public var wraps: Bool = false
  public var minimumValue: Double = 0
  public var maximumValue: Double = 100
  public var stepValue: Double = 1
  public var value: Double = 0 {
    didSet { value = min(max(value, minimumValue), maximumValue) }
  }

  open override var intrinsicContentSize: CGSize {
    CGSize(width: 94, height: 32)
  }
}

@MainActor
open class UISegmentedControl: UIControl {
  public static let noSegment = -1

  private struct SegmentEntry {
    var title: String?
    var image: UIImage?
    var action: UIAction?
    var isEnabled: Bool = true
    var width: CGFloat = 0
  }

  private var segments: [SegmentEntry] = []
  public var isMomentary: Bool = false
  public var apportionsSegmentWidthsByContent: Bool = false
  public var selectedSegmentTintColor: UIColor?

  public var numberOfSegments: Int { segments.count }
  public var selectedSegmentIndex: Int = UISegmentedControl.noSegment

  public override init(frame: CGRect) {
    super.init(frame: frame)
  }

  public init(items: [Any]?) {
    super.init(frame: .zero)
    for item in items ?? [] {
      if let s = item as? String {
        segments.append(SegmentEntry(title: s))
      } else if let img = item as? UIImage {
        segments.append(SegmentEntry(image: img))
      } else if let act = item as? UIAction {
        segments.append(SegmentEntry(title: act.title, image: act.image, action: act))
      }
    }
  }

  public init(frame: CGRect, actions: [UIAction]) {
    super.init(frame: frame)
    self.segments = actions.map { SegmentEntry(title: $0.title, image: $0.image, action: $0) }
  }

  public required init?(coder: NSCoder) {
    super.init(coder: coder)
  }

  public func insertSegment(withTitle title: String?, at segment: Int, animated: Bool) {
    let idx = min(max(0, segment), segments.count)
    segments.insert(SegmentEntry(title: title), at: idx)
  }

  public func insertSegment(with image: UIImage?, at segment: Int, animated: Bool) {
    let idx = min(max(0, segment), segments.count)
    segments.insert(SegmentEntry(image: image), at: idx)
  }

  public func insertSegment(action: UIAction, at segment: Int, animated: Bool) {
    let idx = min(max(0, segment), segments.count)
    segments.insert(SegmentEntry(title: action.title, image: action.image, action: action), at: idx)
  }

  public func removeSegment(at segment: Int, animated: Bool) {
    guard segments.indices.contains(segment) else { return }
    segments.remove(at: segment)
    if selectedSegmentIndex >= segments.count {
      selectedSegmentIndex = segments.count - 1
    }
  }

  public func removeAllSegments() {
    segments.removeAll()
    selectedSegmentIndex = Self.noSegment
  }

  public func setTitle(_ title: String?, forSegmentAt segment: Int) {
    guard segments.indices.contains(segment) else { return }
    segments[segment].title = title
  }

  public func titleForSegment(at segment: Int) -> String? {
    segments.indices.contains(segment) ? segments[segment].title : nil
  }

  public func setImage(_ image: UIImage?, forSegmentAt segment: Int) {
    guard segments.indices.contains(segment) else { return }
    segments[segment].image = image
  }

  public func imageForSegment(at segment: Int) -> UIImage? {
    segments.indices.contains(segment) ? segments[segment].image : nil
  }

  public func setEnabled(_ enabled: Bool, forSegmentAt segment: Int) {
    guard segments.indices.contains(segment) else { return }
    segments[segment].isEnabled = enabled
  }

  public func isEnabledForSegment(at segment: Int) -> Bool {
    segments.indices.contains(segment) ? segments[segment].isEnabled : false
  }

  open override var intrinsicContentSize: CGSize {
    CGSize(width: CGFloat(max(1, segments.count)) * 68, height: 32)
  }
}

@MainActor
open class UIActivityIndicatorView: UIView {
  public enum Style: Int, Sendable {
    case medium = 100
    case large = 101
    case whiteLarge = 0
    case white = 1
    case gray = 2
  }

  public var style: Style
  public var hidesWhenStopped: Bool = true
  public var color: UIColor?
  public private(set) var isAnimating: Bool = false

  public init(style: Style = .medium) {
    self.style = style
    let side: CGFloat = (style == .large || style == .whiteLarge) ? 37 : 20
    super.init(frame: CGRect(x: 0, y: 0, width: side, height: side))
    self.isHidden = true
  }

  public override convenience init(frame: CGRect) {
    self.init(style: .medium)
    self.frame = frame
  }

  public required init?(coder: NSCoder) {
    self.style = .medium
    super.init(coder: coder)
  }

  public func startAnimating() {
    isAnimating = true
    isHidden = false
  }

  public func stopAnimating() {
    isAnimating = false
    if hidesWhenStopped { isHidden = true }
  }

  open override var intrinsicContentSize: CGSize {
    let side: CGFloat = (style == .large || style == .whiteLarge) ? 37 : 20
    return CGSize(width: side, height: side)
  }
}

@MainActor
open class UIProgressView: UIView {
  public enum Style: Int, Sendable {
    case `default` = 0
    case bar = 1
  }

  public var progressViewStyle: Style
  public var progress: Float = 0 {
    didSet { progress = min(max(progress, 0), 1) }
  }
  public var progressTintColor: UIColor?
  public var trackTintColor: UIColor?
  public var observedProgress: Progress?

  public init(progressViewStyle style: Style = .default) {
    self.progressViewStyle = style
    super.init(frame: CGRect(x: 0, y: 0, width: 160, height: 4))
  }

  public override convenience init(frame: CGRect) {
    self.init(progressViewStyle: .default)
    self.frame = frame
  }

  public required init?(coder: NSCoder) {
    self.progressViewStyle = .default
    super.init(coder: coder)
  }

  public func setProgress(_ progress: Float, animated: Bool) {
    self.progress = min(max(progress, 0), 1)
  }

  open override var intrinsicContentSize: CGSize {
    CGSize(width: UIView.noIntrinsicMetric, height: 4)
  }
}

@MainActor
open class UIPageControl: UIControl {
  public var numberOfPages: Int = 0
  public var currentPage: Int = 0
  public var hidesForSinglePage: Bool = false
  public var pageIndicatorTintColor: UIColor?
  public var currentPageIndicatorTintColor: UIColor?

  open override var intrinsicContentSize: CGSize {
    CGSize(width: CGFloat(max(1, numberOfPages)) * 16, height: 26)
  }
}

@MainActor
open class UIDatePicker: UIControl {
  public enum Mode: Int, Sendable {
    case time = 0
    case date = 1
    case dateAndTime = 2
    case countDownTimer = 3
  }

  public enum Style: Int, Sendable {
    case automatic = 0
    case wheels = 1
    case compact = 2
    case inline = 3
  }

  public var datePickerMode: Mode = .dateAndTime
  public var preferredDatePickerStyle: Style = .automatic
  public var locale: Locale? = .current
  public var calendar: Calendar! = .current
  public var timeZone: TimeZone?
  public var date: Date = Date()
  public var minimumDate: Date?
  public var maximumDate: Date?
  public var countDownDuration: TimeInterval = 0
  public var minuteInterval: Int = 1

  public func setDate(_ date: Date, animated: Bool) {
    self.date = date
  }
}

@MainActor
open class UIColorWell: UIControl {
  public var title: String?
  public var supportsAlpha: Bool = true
  public var selectedColor: UIColor?

  open override var intrinsicContentSize: CGSize {
    CGSize(width: 28, height: 28)
  }
}
