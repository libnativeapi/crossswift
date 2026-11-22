import Foundation

// MARK: - UIResponder

@MainActor
open class UIResponder: NSObject {
  public weak var nextResponderOverride: UIResponder?
  private var isCurrentlyFirstResponder = false

  open var next: UIResponder? { nextResponderOverride }
  open var canBecomeFirstResponder: Bool { false }
  open var canResignFirstResponder: Bool { true }
  public internal(set) var isFirstResponder: Bool {
    get { isCurrentlyFirstResponder }
    set { isCurrentlyFirstResponder = newValue }
  }
  open var undoManager: UndoManager? { next?.undoManager }
  open var keyCommands: [UIKeyCommand]? { nil }

  public override init() {
    super.init()
  }

  public init?(coder: NSCoder) {
    super.init()
  }

  @discardableResult
  open func becomeFirstResponder() -> Bool {
    guard canBecomeFirstResponder else { return false }
    isCurrentlyFirstResponder = true
    return true
  }

  @discardableResult
  open func resignFirstResponder() -> Bool {
    guard canResignFirstResponder else { return false }
    isCurrentlyFirstResponder = false
    return true
  }

  open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    next?.touchesBegan(touches, with: event)
  }

  open func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    next?.touchesMoved(touches, with: event)
  }

  open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    next?.touchesEnded(touches, with: event)
  }

  open func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    next?.touchesCancelled(touches, with: event)
  }

  open func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    next?.pressesBegan(presses, with: event)
  }

  open func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    next?.pressesChanged(presses, with: event)
  }

  open func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    next?.pressesEnded(presses, with: event)
  }

  open func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    next?.pressesCancelled(presses, with: event)
  }

  open func motionBegan(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
    next?.motionBegan(motion, with: event)
  }

  open func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
    next?.motionEnded(motion, with: event)
  }

  open func motionCancelled(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
    next?.motionCancelled(motion, with: event)
  }

  open func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
    false
  }

  open func target(forAction action: Selector, withSender sender: Any?) -> Any? {
    if canPerformAction(action, withSender: sender) { return self }
    return next?.target(forAction: action, withSender: sender)
  }

  open func buildMenu(with builder: any UIMenuBuilder) {}
  open func validate(_ command: UICommand) {}
}

// MARK: - UITouch, UIPress, UIEvent, UIKeyCommand

@MainActor
open class UITouch: NSObject {
  public enum Phase: Int, Sendable {
    case began = 0
    case moved = 1
    case stationary = 2
    case ended = 3
    case cancelled = 4
    case regionEntered = 5
    case regionMoved = 6
    case regionExited = 7
  }

  public enum TouchType: Int, Sendable {
    case direct = 0
    case indirect = 1
    case pencil = 2
    case indirectPointer = 3
  }

  public var timestamp: TimeInterval
  public var phase: Phase
  public var tapCount: Int
  public var type: TouchType
  public var force: CGFloat = 0
  public var maximumPossibleForce: CGFloat = 1
  public weak var window: UIWindow?
  public weak var view: UIView?
  internal var windowLocation: CGPoint
  internal var previousWindowLocation: CGPoint

  public init(
    locationInWindow: CGPoint,
    previousLocationInWindow: CGPoint? = nil,
    phase: Phase = .began,
    tapCount: Int = 1,
    type: TouchType = .direct,
    window: UIWindow? = nil,
    view: UIView? = nil,
    timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime
  ) {
    self.windowLocation = locationInWindow
    self.previousWindowLocation = previousLocationInWindow ?? locationInWindow
    self.phase = phase
    self.tapCount = tapCount
    self.type = type
    self.window = window
    self.view = view
    self.timestamp = timestamp
    super.init()
  }

  public func location(in targetView: UIView?) -> CGPoint {
    guard let targetView else { return windowLocation }
    return targetView.convert(windowLocation, from: nil)
  }

  public func previousLocation(in targetView: UIView?) -> CGPoint {
    guard let targetView else { return previousWindowLocation }
    return targetView.convert(previousWindowLocation, from: nil)
  }
}

public struct UIKeyModifierFlags: OptionSet, Hashable, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }

  public static let alphaShift = UIKeyModifierFlags(rawValue: 1 << 16)
  public static let shift = UIKeyModifierFlags(rawValue: 1 << 17)
  public static let control = UIKeyModifierFlags(rawValue: 1 << 18)
  public static let alternate = UIKeyModifierFlags(rawValue: 1 << 19)
  public static let command = UIKeyModifierFlags(rawValue: 1 << 20)
  public static let numericPad = UIKeyModifierFlags(rawValue: 1 << 21)
}

open class UIKey: NSObject, NSCopying, @unchecked Sendable {
  public let characters: String
  public let charactersIgnoringModifiers: String
  public let modifierFlags: UIKeyModifierFlags
  public let keyCode: Int

  public init(
    characters: String = "",
    charactersIgnoringModifiers: String = "",
    modifierFlags: UIKeyModifierFlags = [],
    keyCode: Int = 0
  ) {
    self.characters = characters
    self.charactersIgnoringModifiers = charactersIgnoringModifiers
    self.modifierFlags = modifierFlags
    self.keyCode = keyCode
    super.init()
  }

  open func copy(with zone: NSZone? = nil) -> Any { self }
}

@MainActor
open class UIPress: NSObject {
  public enum Phase: Int, Sendable {
    case began = 0
    case changed = 1
    case stationary = 2
    case ended = 3
    case cancelled = 4
  }

  public enum PressType: Int, Sendable {
    case upArrow = 0
    case downArrow = 1
    case leftArrow = 2
    case rightArrow = 3
    case select = 4
    case menu = 5
    case playPause = 6
    case pageUp = 30
    case pageDown = 31
  }

  public let timestamp: TimeInterval
  public let phase: Phase
  public let type: PressType
  public let key: UIKey?
  public weak var window: UIWindow?
  public weak var responder: UIResponder?

  public init(
    phase: Phase = .began,
    type: PressType = .select,
    key: UIKey? = nil,
    window: UIWindow? = nil,
    responder: UIResponder? = nil,
    timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime
  ) {
    self.phase = phase
    self.type = type
    self.key = key
    self.window = window
    self.responder = responder
    self.timestamp = timestamp
    super.init()
  }
}

@MainActor
open class UIEvent: NSObject {
  public enum EventType: Int, Sendable {
    case touches = 0
    case motion = 1
    case remoteControl = 2
    case presses = 3
    case scroll = 10
    case hover = 11
    case transform = 14
  }

  public enum EventSubtype: Int, Sendable {
    case none = 0
    case motionShake = 1
  }

  public struct ButtonMask: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let primary = ButtonMask(rawValue: 1 << 0)
    public static let secondary = ButtonMask(rawValue: 1 << 1)
  }

  public let type: EventType
  public let subtype: EventSubtype
  public let timestamp: TimeInterval
  public let modifierFlags: UIKeyModifierFlags
  public let buttonMask: ButtonMask
  private let touchSet: Set<UITouch>

  public var allTouches: Set<UITouch>? {
    touchSet.isEmpty ? nil : touchSet
  }

  public init(
    type: EventType = .touches,
    subtype: EventSubtype = .none,
    touches: Set<UITouch> = [],
    modifierFlags: UIKeyModifierFlags = [],
    buttonMask: ButtonMask = .primary,
    timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime
  ) {
    self.type = type
    self.subtype = subtype
    self.touchSet = touches
    self.modifierFlags = modifierFlags
    self.buttonMask = buttonMask
    self.timestamp = timestamp
    super.init()
  }

  public func touches(for view: UIView) -> Set<UITouch>? {
    let matching = touchSet.filter { $0.view === view || ($0.view?.isDescendant(of: view) == true) }
    return matching.isEmpty ? nil : matching
  }

  public func touches(for window: UIWindow) -> Set<UITouch>? {
    let matching = touchSet.filter { $0.window === window }
    return matching.isEmpty ? nil : matching
  }
}

@MainActor
open class UIPressesEvent: UIEvent {
  public let allPresses: Set<UIPress>

  public init(
    presses: Set<UIPress>,
    modifierFlags: UIKeyModifierFlags = [],
    timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime
  ) {
    self.allPresses = presses
    super.init(type: .presses, modifierFlags: modifierFlags, timestamp: timestamp)
  }
}

// MARK: - Gesture Recognizers

@MainActor
public protocol UIGestureRecognizerDelegate: NSObjectProtocol {
  func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool
  func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool
}

extension UIGestureRecognizerDelegate {
  public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool { true }
  public func gestureRecognizer(
    _ gestureRecognizer: UIGestureRecognizer,
    shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
  ) -> Bool { false }
  public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool { true }
}

@MainActor
open class UIGestureRecognizer: NSObject {
  public enum State: Int, Sendable {
    case possible = 0
    case began = 1
    case changed = 2
    case ended = 3
    case cancelled = 4
    case failed = 5
    public static let recognized: State = .ended
  }

  internal struct TargetAction {
    weak var target: AnyObject?
    let action: Selector?
    let closure: ((UIGestureRecognizer) -> Void)?
  }

  public var state: State = .possible
  public weak var delegate: (any UIGestureRecognizerDelegate)?
  public var isEnabled: Bool = true
  public internal(set) weak var view: UIView?
  public var cancelsTouchesInView: Bool = true
  public var delaysTouchesBegan: Bool = false
  public var delaysTouchesEnded: Bool = true
  public var name: String?
  public var allowedTouchTypes: [NSNumber] = []
  public var allowedPressTypes: [NSNumber] = []
  internal var targets: [TargetAction] = []
  internal var lastWindowLocation: CGPoint = .zero

  public override init() {
    super.init()
  }

  public init(target: Any?, action: Selector?) {
    super.init()
    if let target {
      addTarget(target, action: action ?? Selector(("handleGesture:")))
    }
  }

  public convenience init(handler: @escaping (UIGestureRecognizer) -> Void) {
    self.init()
    targets.append(TargetAction(target: nil, action: nil, closure: handler))
  }

  public func addTarget(_ target: Any, action: Selector) {
    targets.append(TargetAction(target: target as AnyObject, action: action, closure: nil))
  }

  public func addAction(_ handler: @escaping (UIGestureRecognizer) -> Void) {
    targets.append(TargetAction(target: nil, action: nil, closure: handler))
  }

  public func removeTarget(_ target: Any?, action: Selector?) {
    targets.removeAll { entry in
      let matchTarget = (target == nil) || (entry.target === (target as AnyObject))
      let matchAction = (action == nil) || (entry.action == action)
      return matchTarget && matchAction
    }
  }

  public func require(toFail otherGestureRecognizer: UIGestureRecognizer) {}

  open func location(in targetView: UIView?) -> CGPoint {
    guard let targetView else { return lastWindowLocation }
    return targetView.convert(lastWindowLocation, from: nil)
  }

  open var numberOfTouches: Int { state == .possible ? 0 : 1 }

  open func location(ofTouch touchIndex: Int, in targetView: UIView?) -> CGPoint {
    location(in: targetView)
  }

  public func _fireRecognized(at windowLocation: CGPoint, state newState: State = .ended) {
    guard isEnabled else { return }
    if let delegate, !delegate.gestureRecognizerShouldBegin(self) { return }
    lastWindowLocation = windowLocation
    self.state = newState
    for entry in targets {
      if let closure = entry.closure {
        closure(self)
      } else if let actionTarget = entry.target as? any _UIActionInvoking, let sel = entry.action {
        _ = actionTarget._invokeAction(sel, sender: self)
      } else {
        #if canImport(ObjectiveC)
          if let nsObj = entry.target as? NSObject, let sel = entry.action, nsObj.responds(to: sel) {
            _ = nsObj.perform(sel, with: self)
          }
        #endif
      }
    }
    if newState == .ended || newState == .cancelled || newState == .failed {
      self.state = .possible
    }
  }
}

public protocol _UIActionInvoking: AnyObject {
  @MainActor func _invokeAction(_ selector: Selector, sender: Any?) -> Bool
}

open class UITapGestureRecognizer: UIGestureRecognizer {
  public var numberOfTapsRequired: Int = 1
  public var numberOfTouchesRequired: Int = 1
  public var buttonMaskRequired: UIEvent.ButtonMask = .primary
}

open class UILongPressGestureRecognizer: UIGestureRecognizer {
  public var numberOfTapsRequired: Int = 0
  public var numberOfTouchesRequired: Int = 1
  public var minimumPressDuration: TimeInterval = 0.5
  public var allowableMovement: CGFloat = 10
}

open class UIPanGestureRecognizer: UIGestureRecognizer {
  public var minimumNumberOfTouches: Int = 1
  public var maximumNumberOfTouches: Int = Int.max
  private var storedTranslation: CGPoint = .zero
  private var storedVelocity: CGPoint = .zero

  public func translation(in view: UIView?) -> CGPoint { storedTranslation }
  public func setTranslation(_ translation: CGPoint, in view: UIView?) {
    storedTranslation = translation
  }
  public func velocity(in view: UIView?) -> CGPoint { storedVelocity }
}

open class UISwipeGestureRecognizer: UIGestureRecognizer {
  public struct Direction: OptionSet, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let right = Direction(rawValue: 1 << 0)
    public static let left = Direction(rawValue: 1 << 1)
    public static let up = Direction(rawValue: 1 << 2)
    public static let down = Direction(rawValue: 1 << 3)
  }

  public var numberOfTouchesRequired: Int = 1
  public var direction: Direction = .right
}

open class UIPinchGestureRecognizer: UIGestureRecognizer {
  public var scale: CGFloat = 1.0
  public var velocity: CGFloat = 0.0
}

open class UIRotationGestureRecognizer: UIGestureRecognizer {
  public var rotation: CGFloat = 0.0
  public var velocity: CGFloat = 0.0
}

open class UIHoverGestureRecognizer: UIGestureRecognizer {}

// MARK: - Haptic Feedback Generators

@MainActor
open class UIFeedbackGenerator: NSObject {
  public private(set) var prepareCount: Int = 0
  public override init() { super.init() }
  open func prepare() { prepareCount += 1 }
}

@MainActor
open class UIImpactFeedbackGenerator: UIFeedbackGenerator {
  public enum FeedbackStyle: Int, Sendable {
    case light = 0
    case medium = 1
    case heavy = 2
    case soft = 3
    case rigid = 4
  }

  public let style: FeedbackStyle
  public private(set) var impactCount: Int = 0

  public override convenience init() {
    self.init(style: .medium)
  }

  public init(style: FeedbackStyle) {
    self.style = style
    super.init()
  }

  public convenience init(style: FeedbackStyle, view: UIView) {
    self.init(style: style)
  }

  open func impactOccurred() {
    impactCount += 1
  }

  open func impactOccurred(intensity: CGFloat) {
    impactCount += 1
  }

  open func impactOccurred(intensity: CGFloat, at location: CGPoint) {
    impactCount += 1
  }
}

@MainActor
open class UINotificationFeedbackGenerator: UIFeedbackGenerator {
  public enum FeedbackType: Int, Sendable {
    case success = 0
    case warning = 1
    case error = 2
  }

  public private(set) var lastNotificationType: FeedbackType?

  public override init() { super.init() }
  public convenience init(view: UIView) { self.init() }

  open func notificationOccurred(_ notificationType: FeedbackType) {
    lastNotificationType = notificationType
  }

  open func notificationOccurred(_ notificationType: FeedbackType, at location: CGPoint) {
    lastNotificationType = notificationType
  }
}

@MainActor
open class UISelectionFeedbackGenerator: UIFeedbackGenerator {
  public private(set) var selectionChangeCount: Int = 0

  public override init() { super.init() }
  public convenience init(view: UIView) { self.init() }

  open func selectionChanged() {
    selectionChangeCount += 1
  }

  open func selectionChanged(at location: CGPoint) {
    selectionChangeCount += 1
  }
}
