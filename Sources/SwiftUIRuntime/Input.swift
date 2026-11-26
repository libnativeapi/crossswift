import Foundation

#if (os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)) && canImport(CoreGraphics)
  import CoreGraphics
#endif

public struct EventModifiers: OptionSet, Hashable, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  public static let shift = Self(rawValue: 1), control = Self(rawValue: 2),
    option = Self(rawValue: 4), command = Self(rawValue: 8),
    capsLock = Self(rawValue: 16), numericPad = Self(rawValue: 32)
  public static let all: EventModifiers = [.shift, .control, .option, .command, .capsLock, .numericPad]
}
public struct KeyEquivalent: Hashable, ExpressibleByExtendedGraphemeClusterLiteral, Sendable {
  public let character: Character
  public init(_ character: Character) { self.character = character }
  public init(extendedGraphemeClusterLiteral value: String) { character = value.first! }
  public static let escape = Self("\u{1b}"), `return` = Self("\r"), space = Self(" "),
    tab = Self("\t"), delete = Self("\u{8}"), deleteForward = Self("\u{7f}")
  public static let leftArrow = Self("\u{f702}"), rightArrow = Self("\u{f703}"),
    upArrow = Self("\u{f700}"), downArrow = Self("\u{f701}")
  public static let home = Self("\u{f729}"), end = Self("\u{f72b}"), pageUp = Self("\u{f72c}"),
    pageDown = Self("\u{f72d}")
}
public struct KeyboardShortcut: Equatable, Sendable {
  public struct Localization: Equatable, Hashable, Sendable {
    public static let automatic = Localization()
    public static let withoutMirroring = Localization()
    public static let custom = Localization()
  }

  public let key: KeyEquivalent
  public let modifiers: EventModifiers
  public let localization: Localization

  public init(
    _ key: KeyEquivalent,
    modifiers: EventModifiers = .command,
    localization: Localization = .automatic
  ) {
    self.key = key
    self.modifiers = modifiers
    self.localization = localization
  }
  public static let cancelAction = Self(.escape, modifiers: []),
    defaultAction = Self(.return, modifiers: [])
}
public struct KeyPress: Sendable {
  public struct Phases: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let down = Self(rawValue: 1), `repeat` = Self(rawValue: 2), up = Self(rawValue: 4)
  }
  public enum Result: Sendable { case handled, ignored }
  public let key: KeyEquivalent
  public let characters: String
  public let modifiers: EventModifiers
  public let phase: Phases
  public init(
    key: KeyEquivalent, characters: String = "", modifiers: EventModifiers = [],
    phase: Phases = .down
  ) {
    self.key = key
    self.characters = characters
    self.modifiers = modifiers
    self.phase = phase
  }
}
public enum MoveCommandDirection { case left, right, up, down }
public protocol Gesture {
  var changed: ((DragGesture.Value) -> Void)? { get }
  var ended: ((DragGesture.Value) -> Void)? { get }
}
public struct DragGesture: Gesture {
  public struct Value {
    public let location: CGPoint
    public let startLocation: CGPoint
    public let translation: CGSize
    public let time: Date
  }
  public let minimumDistance: CGFloat
  public var changed: ((Value) -> Void)?
  public var ended: ((Value) -> Void)?
  public init(minimumDistance: CGFloat = 10, coordinateSpace: CoordinateSpace = .local) {
    self.minimumDistance = minimumDistance
  }
  public func onChanged(_ action: @escaping (Value) -> Void) -> Self {
    var g = self
    g.changed = action
    return g
  }
  public func onEnded(_ action: @escaping (Value) -> Void) -> Self {
    var g = self
    g.ended = action
    return g
  }
}
public struct TextField: View, _PrimitiveView {
  public typealias Body = Never
  let title: String
  let text: Binding<String>
  let axis: Axis
  var secure = false
  public init(
    _ titleKey: LocalizedStringKey,
    text: Binding<String>,
    prompt: Text? = nil,
    axis: Axis = .horizontal
  ) {
    self.title = prompt?.content ?? titleKey.resolved()
    self.text = text
    self.axis = axis
  }
  @_disfavoredOverload
  public init<S: StringProtocol>(
    _ title: S,
    text: Binding<String>,
    prompt: Text? = nil,
    axis: Axis = .horizontal
  ) {
    self.title = prompt?.content ?? String(title)
    self.text = text
    self.axis = axis
  }
  public init<V>(
    _ titleKey: LocalizedStringKey,
    value: Binding<V>,
    formatter: Formatter,
    prompt: Text? = nil
  ) {
    self.title = prompt?.content ?? titleKey.resolved()
    self.text = Binding<String>(
      get: { formatter.string(for: value.wrappedValue) ?? "\(value.wrappedValue)" },
      set: { newStr in
        if let nf = formatter as? NumberFormatter, let num = nf.number(from: newStr) {
          if let v = num as? V {
            value.wrappedValue = v
            return
          }
          if V.self == Int.self, let n = num.intValue as? V {
            value.wrappedValue = n
            return
          }
          if V.self == Double.self, let d = num.doubleValue as? V {
            value.wrappedValue = d
            return
          }
        }
        if V.self == Int.self, let n = Int(newStr) as? V {
          value.wrappedValue = n
        } else if V.self == Double.self, let d = Double(newStr) as? V {
          value.wrappedValue = d
        } else if V.self == String.self, let s = newStr as? V {
          value.wrappedValue = s
        }
      }
    )
    self.axis = .horizontal
  }
  @_disfavoredOverload
  public init<S: StringProtocol, V>(
    _ title: S,
    value: Binding<V>,
    formatter: Formatter,
    prompt: Text? = nil
  ) {
    self.init(LocalizedStringKey(String(title)), value: value, formatter: formatter, prompt: prompt)
  }
  public var body: Never { fatalError() }
  func _makeElement(path: ViewPath) -> Element {
    var p = NodeProps()
    p.text = text.wrappedValue
    p.placeholder = title
    p.multiline = axis == .vertical
    p.secure = secure
    p.plainTextField = EnvironmentValues.current.plainTextFieldStyle
    p.font = EnvironmentValues.current.font
    p.fillWidth = true
    var e = Element(kind: .textField, props: p)
    e.textAction = { if text.wrappedValue != $0 { text.wrappedValue = $0 } }
    return e
  }
}
public struct SecureField: View {
  let title: String
  let text: Binding<String>
  public init(_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text? = nil) {
    self.title = prompt?.content ?? titleKey.resolved()
    self.text = text
  }
  @_disfavoredOverload
  public init<S: StringProtocol>(_ title: S, text: Binding<String>, prompt: Text? = nil) {
    self.title = prompt?.content ?? String(title)
    self.text = text
  }
  public var body: some View {
    var field = TextField(title, text: text)
    field.secure = true
    return field
  }
}
public protocol TextFieldStyle {}
public struct PlainTextFieldStyle: TextFieldStyle {
  public init() {}
  public static let plain = Self()
}
public struct RoundedBorderTextFieldStyle: TextFieldStyle {
  public init() {}
  public static let roundedBorder = Self()
}
public struct DefaultTextFieldStyle: TextFieldStyle {
  public init() {}
  public static let automatic = Self()
}
extension TextFieldStyle where Self == PlainTextFieldStyle {
  public static var plain: Self { Self() }
}
extension TextFieldStyle where Self == RoundedBorderTextFieldStyle {
  public static var roundedBorder: Self { Self() }
}
extension TextFieldStyle where Self == DefaultTextFieldStyle {
  public static var automatic: Self { Self() }
}
public struct PlainButtonStyle: ButtonStyle {
  public init() {}
  public func makeBody(configuration: Configuration) -> some View { configuration.label }
  public static let plain = Self()
}
extension ButtonStyle where Self == PlainButtonStyle { public static var plain: Self { Self() } }
private struct PlainTextFieldStyleKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  var plainTextFieldStyle: Bool {
    get { self[PlainTextFieldStyleKey.self] }
    set { self[PlainTextFieldStyleKey.self] = newValue }
  }
}

extension View {
  public func textFieldStyle<S: TextFieldStyle>(_ style: S) -> some View {
    environment(\.plainTextFieldStyle, style is PlainTextFieldStyle)
  }
  public func onSubmit(_ action: @escaping () -> Void) -> some View {
    TransformView(content: self) { $0.submitAction = action }
  }
  public func gesture<G: Gesture>(_ gesture: G, isEnabled: Bool = true) -> some View {
    TransformView(content: self) { el in
      guard isEnabled else { return }
      if let lp = gesture as? LongPressGesture {
        el.longPressAction = Element.LongPressConfig(
          minimumDuration: lp.minimumDuration,
          maximumDistance: Double(lp.maximumDistance),
          onPressingChanged: lp.pressingChanged,
          onEnded: { lp.ended?(DragGesture.Value(location: .zero, startLocation: .zero, translation: .zero, time: Date())) }
        )
      } else if let tap = gesture as? TapGesture, let cb = tap.tapCallback {
        if tap.count == 2 {
          el.doubleTapAction = cb
        } else {
          el.action = cb
        }
      } else if let spatial = gesture as? SpatialTapGesture, spatial.count == 2 {
        el.doubleTapLocationAction = { pt in
          spatial.ended?(
            DragGesture.Value(location: pt, startLocation: pt, translation: .zero, time: Date()))
        }
      } else {
        el.dragMinimumDistance = Double((gesture as? DragGesture)?.minimumDistance ?? 0)
        el.dragAction = { value, ended in
          if ended { gesture.ended?(value) } else { gesture.changed?(value) }
        }
      }
    }
  }
  public func onTapGesture(count: Int, perform action: @escaping () -> Void) -> some View {
    TransformView(content: self) {
      if count == 2 { $0.doubleTapAction = action } else { $0.action = action }
    }
  }
  public func onKeyPress(
    phases: KeyPress.Phases = [.down, .repeat], action: @escaping (KeyPress) -> KeyPress.Result
  ) -> some View {
    TransformView(content: self) {
      let previous = $0.keyAction
      $0.keyAction = { key in action(key) == .handled ? .handled : previous?(key) ?? .ignored }
    }
  }
  public func onKeyPress(
    keys: Set<KeyEquivalent>,
    phases: KeyPress.Phases = [.down, .repeat],
    action: @escaping (KeyPress) -> KeyPress.Result
  ) -> some View {
    onKeyPress(phases: phases) { press in
      keys.contains(press.key) ? action(press) : .ignored
    }
  }
  public func onKeyPress(
    _ key: KeyEquivalent,
    phases: KeyPress.Phases = [.down, .repeat],
    action: @escaping (KeyPress) -> KeyPress.Result
  ) -> some View {
    onKeyPress(keys: [key], phases: phases, action: action)
  }
  public func onKeyPress(
    _ key: KeyEquivalent,
    action: @escaping () -> KeyPress.Result
  ) -> some View {
    onKeyPress(keys: [key]) { _ in action() }
  }
  public func onMoveCommand(perform action: @escaping (MoveCommandDirection) -> Void) -> some View {
    onKeyPress { press in
      switch press.key {
      case .leftArrow: action(.left)
      case .rightArrow: action(.right)
      case .upArrow: action(.up)
      case .downArrow: action(.down)
      default: return .ignored
      }
      return .handled
    }
  }
  public func onExitCommand(perform action: @escaping () -> Void) -> some View {
    onKeyPress { key in
      if key.key == .escape {
        action()
        return .handled
      }
      return .ignored
    }
  }
  public func keyboardShortcut(_ key: KeyEquivalent, modifiers: EventModifiers = .command)
    -> some View
  { keyboardShortcut(KeyboardShortcut(key, modifiers: modifiers)) }
  public func keyboardShortcut(_ shortcut: KeyboardShortcut?) -> some View {
    TransformView(content: self) {
      if let shortcut {
        $0.props.keyboardShortcut = shortcut
      }
    }
  }
  public func focusable(_ focusable: Bool = true) -> some View {
    TransformView(content: self) { $0.props.focusable = focusable }
  }
  public func focusEffectDisabled(_ disabled: Bool = true) -> some View { self }  // all custom focus decoration belongs to view styles
  public func focused<Value: Hashable>(_ binding: FocusState<Value?>.Binding, equals value: Value?)
    -> some View
  {
    TransformView(content: self) {
      guard let value else { return }
      $0.focusAction = { binding.set($0 ? value : nil) }
      $0.props.focusRequested = binding.get() == value
    }
  }
}
public enum AccessibilityChildBehavior { case contain, combine, ignore }
public enum AccessibilityAdjustmentDirection { case increment, decrement }
public struct AccessibilityTraits: OptionSet, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  public static let isSelected = Self(rawValue: 1), isButton = Self(rawValue: 2),
    isHeader = Self(rawValue: 4), isLink = Self(rawValue: 8), isImage = Self(rawValue: 16),
    isModal = Self(rawValue: 32), isToggle = Self(rawValue: 64), isStaticText = Self(rawValue: 128),
    isSearchField = Self(rawValue: 256)
}
extension View {
  public func accessibilityElement(children: AccessibilityChildBehavior = .ignore) -> some View {
    self
  }
  public func accessibilityLabel(_ text: String) -> some View {
    TransformView(content: self) { $0.props.accessibilityLabel = text }
  }
  public func accessibilityLabel(_ text: Text) -> some View { accessibilityLabel(text.content) }
  public func accessibilityValue(_ text: String) -> some View {
    TransformView(content: self) { $0.props.accessibilityValue = text }
  }
  public func accessibilityValue(_ text: Text) -> some View { accessibilityValue(text.content) }
  public func accessibilityIdentifier(_ value: String) -> some View {
    TransformView(content: self) { $0.props.accessibilityIdentifier = value }
  }
  public func accessibilityHidden(_ value: Bool) -> some View {
    TransformView(content: self) { $0.props.accessibilityHidden = value }
  }
  public func accessibilityAddTraits(_ traits: AccessibilityTraits) -> some View {
    TransformView(content: self) { $0.props.accessibilityTraits = traits.rawValue }
  }
  public func accessibilityAdjustableAction(
    _ action: @escaping (AccessibilityAdjustmentDirection) -> Void
  ) -> some View {
    onMoveCommand { direction in
      action(direction == .up || direction == .right ? .increment : .decrement)
    }
  }
}

extension View {
  public func onTapGesture(
    count: Int = 1, coordinateSpace: CoordinateSpace = .local,
    perform action: @escaping (CGPoint) -> Void
  ) -> some View {
    TransformView(content: self) { node in
      if count == 2 {
        node.doubleTapAction = {}
        node.doubleTapLocationAction = action
      } else {
        node.action = {}
        node.tapLocationAction = action
      }
    }
  }
}
