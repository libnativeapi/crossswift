import Foundation

#if (os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)) && canImport(CoreGraphics)
  import CoreGraphics
#endif

// MARK: - Divider

public struct Divider: View, _PrimitiveView {
  public typealias Body = Never
  public init() {}
  public var body: Never { fatalError("Divider is primitive") }

  func _makeElement(path: ViewPath) -> Element {
    let axis = EnvironmentValues.current.enclosingStackAxis
    let color = SeparatorShapeStyle()._resolvePrimaryColor(in: EnvironmentValues.current)
    var p = NodeProps()
    p.background = color
    p.accessibilityIdentifier = "SwiftUI.Divider"
    if axis == .horizontal {
      p.frameWidth = 1
      p.fillHeight = true
    } else {
      p.frameHeight = 1
      p.fillWidth = true
    }
    return Element(kind: .shape, props: p)
  }
}

// MARK: - Label & LabelStyle

public struct LabelStyleConfiguration {
  public typealias Title = AnyView
  public typealias Icon = AnyView
  public let title: Title
  public let icon: Icon
}

@MainActor @preconcurrency
public protocol LabelStyle {
  associatedtype Body: View
  typealias Configuration = LabelStyleConfiguration
  @ViewBuilder func makeBody(configuration: Configuration) -> Body
}

public struct DefaultLabelStyle: LabelStyle {
  public init() {}
  public func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 6) {
      configuration.icon
      configuration.title
    }
  }
}

public struct TitleAndIconLabelStyle: LabelStyle {
  public init() {}
  public func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 6) {
      configuration.icon
      configuration.title
    }
  }
}

public struct IconOnlyLabelStyle: LabelStyle {
  public init() {}
  public func makeBody(configuration: Configuration) -> some View {
    configuration.icon
  }
}

public struct TitleOnlyLabelStyle: LabelStyle {
  public init() {}
  public func makeBody(configuration: Configuration) -> some View {
    configuration.title
  }
}

extension LabelStyle where Self == DefaultLabelStyle {
  public static var automatic: DefaultLabelStyle { DefaultLabelStyle() }
}
extension LabelStyle where Self == TitleAndIconLabelStyle {
  public static var titleAndIcon: TitleAndIconLabelStyle { TitleAndIconLabelStyle() }
}
extension LabelStyle where Self == IconOnlyLabelStyle {
  public static var iconOnly: IconOnlyLabelStyle { IconOnlyLabelStyle() }
}
extension LabelStyle where Self == TitleOnlyLabelStyle {
  public static var titleOnly: TitleOnlyLabelStyle { TitleOnlyLabelStyle() }
}

private enum LabelStyleKey: EnvironmentKey {
  nonisolated(unsafe) static let defaultValue: (@MainActor (LabelStyleConfiguration) -> AnyView)? = nil
}

extension EnvironmentValues {
  fileprivate var customLabelStyle: (@MainActor (LabelStyleConfiguration) -> AnyView)? {
    get { self[LabelStyleKey.self] }
    set { self[LabelStyleKey.self] = newValue }
  }
}

extension View {
  public func labelStyle<S: LabelStyle>(_ style: S) -> some View {
    environment(\.customLabelStyle) { config in
      AnyView(style.makeBody(configuration: config))
    }
  }
}

public struct Label<Title: View, Icon: View>: View {
  let title: Title
  let icon: Icon
  @Environment(\.customLabelStyle) private var customStyle

  public init(@ViewBuilder title: () -> Title, @ViewBuilder icon: () -> Icon) {
    self.title = title()
    self.icon = icon()
  }

  public init(_ titleKey: LocalizedStringKey, systemImage name: String)
  where Title == Text, Icon == Image {
    self.title = Text(titleKey)
    self.icon = Image(systemName: name)
  }

  @_disfavoredOverload
  public init<S: StringProtocol>(_ title: S, systemImage name: String)
  where Title == Text, Icon == Image {
    self.title = Text(verbatim: String(title))
    self.icon = Image(systemName: name)
  }

  public init(_ titleKey: LocalizedStringKey, image name: String)
  where Title == Text, Icon == Image {
    self.title = Text(titleKey)
    self.icon = Image(name)
  }

  @_disfavoredOverload
  public init<S: StringProtocol>(_ title: S, image name: String)
  where Title == Text, Icon == Image {
    self.title = Text(verbatim: String(title))
    self.icon = Image(name)
  }

  public var body: some View {
    let config = LabelStyleConfiguration(title: AnyView(title), icon: AnyView(icon))
    if let customStyle {
      customStyle(config)
    } else {
      DefaultLabelStyle().makeBody(configuration: config)
    }
  }
}

extension Button where Label == SwiftUIRuntime.Label<Text, Image> {
  public init(
    _ titleKey: LocalizedStringKey,
    systemImage: String,
    role: ButtonRole? = nil,
    action: @escaping () -> Void
  ) {
    self.init(role: role, action: action) {
      SwiftUIRuntime.Label(titleKey, systemImage: systemImage)
    }
  }

  @_disfavoredOverload
  public init<S: StringProtocol>(
    _ title: S,
    systemImage: String,
    role: ButtonRole? = nil,
    action: @escaping () -> Void
  ) {
    self.init(role: role, action: action) {
      SwiftUIRuntime.Label(title, systemImage: systemImage)
    }
  }
}

// MARK: - ButtonStyle Variants & ControlSize

public enum ControlSize: CaseIterable, Hashable, Sendable {
  case mini, small, regular, large, extraLarge
}

private enum ControlSizeKey: EnvironmentKey {
  static let defaultValue: ControlSize = .regular
}

private enum InheritedButtonStyleKey: EnvironmentKey {
  nonisolated(unsafe) static let defaultValue:
    (@MainActor (AnyView, ButtonRole?, ViewPath, @escaping () -> Void) -> Element)? = nil
}

extension EnvironmentValues {
  public var controlSize: ControlSize {
    get { self[ControlSizeKey.self] }
    set { self[ControlSizeKey.self] = newValue }
  }
  package var inheritedButtonStyle:
    (@MainActor (AnyView, ButtonRole?, ViewPath, @escaping () -> Void) -> Element)?
  {
    get { self[InheritedButtonStyleKey.self] }
    set { self[InheritedButtonStyleKey.self] = newValue }
  }
}

public struct DefaultButtonStyle: ButtonStyle {
  public init() {}
  public func makeBody(configuration: Configuration) -> some View {
    BorderedButtonStyle().makeBody(configuration: configuration)
  }
}

public struct BorderedButtonStyle: ButtonStyle {
  public init() {}
  private struct BodyView: View {
    let configuration: Configuration
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovered = false

    var body: some View {
      let enabled = isEnabled
      let isHovered = hovered
      let isPressed = enabled && configuration.isPressed
      #if os(Android) || CROSS_SWIFTUI_HARMONY
      let hPad: CGFloat = 18
      let vPad: CGFloat = 10
      let minHeight: CGFloat = 38
      let labelFont: Font = .body.weight(.medium)
      #else
      let hPad: CGFloat = 12
      let vPad: CGFloat = 5
      let minHeight: CGFloat = 24
      let labelFont: Font = .callout
      #endif
      return configuration.label
        .font(labelFont)
        .opacity(enabled ? 1.0 : 0.42)
        .padding(.horizontal, hPad)
        .padding(.vertical, vPad)
        .frame(minHeight: minHeight)
        .background(
          Color { scheme in
            if !enabled {
              return scheme == .dark ? (1, 1, 1, 0.04) : (0, 0, 0, 0.03)
            }
            if isPressed {
              return scheme == .dark ? (1, 1, 1, 0.20) : (0, 0, 0, 0.14)
            }
            if isHovered {
              return scheme == .dark ? (1, 1, 1, 0.14) : (0, 0, 0, 0.09)
            }
            return scheme == .dark ? (1, 1, 1, 0.08) : (0, 0, 0, 0.055)
          },
          in: RoundedRectangle(cornerRadius: 6)
        )
        .overlay {
          RoundedRectangle(cornerRadius: 6)
            .strokeBorder(
              Color { scheme in
                let alpha = !enabled ? 0.07 : (scheme == .dark ? 0.14 : 0.12)
                return scheme == .dark ? (1, 1, 1, alpha) : (0, 0, 0, alpha)
              },
              lineWidth: 1
            )
        }
        .onHover { hovered = $0 }
    }
  }
  public func makeBody(configuration: Configuration) -> some View {
    BodyView(configuration: configuration)
  }
}

public struct BorderedProminentButtonStyle: ButtonStyle {
  public init() {}
  public func makeBody(configuration: Configuration) -> some View {
    let isEnabled = EnvironmentValues.current.isEnabled
    let isPressed = isEnabled && configuration.isPressed
    #if os(Android) || CROSS_SWIFTUI_HARMONY
    let hPad: CGFloat = 20
    let vPad: CGFloat = 10
    let labelFont: Font = .body.weight(.semibold)
    #else
    let hPad: CGFloat = 12
    let vPad: CGFloat = 5
    let labelFont: Font = .callout.weight(.medium)
    #endif
    return configuration.label
      .font(labelFont)
      .foregroundStyle(
        isEnabled
          ? Color.white
          : Color { scheme in scheme == .dark ? (1, 1, 1, 0.42) : (0, 0, 0, 0.38) }
      )
      .padding(.horizontal, hPad)
      .padding(.vertical, vPad)
      .background(
        isEnabled
          ? Color.accentColor.opacity(isPressed ? 0.80 : 1.0)
          : Color { scheme in scheme == .dark ? (1, 1, 1, 0.14) : (0, 0, 0, 0.10) },
        in: RoundedRectangle(cornerRadius: 6)
      )
  }
}

public struct BorderlessButtonStyle: ButtonStyle {
  public init() {}
  public func makeBody(configuration: Configuration) -> some View {
    let isEnabled = EnvironmentValues.current.isEnabled
    let alpha = !isEnabled ? 0.40 : (configuration.isPressed ? 0.65 : 1.0)
    #if os(Android) || CROSS_SWIFTUI_HARMONY
    return configuration.label
      .font(.body.weight(.medium))
      .padding(.horizontal, 16)
      .padding(.vertical, 8)
      .opacity(alpha)
    #else
    return configuration.label
      .opacity(alpha)
    #endif
  }
}

public struct LinkButtonStyle: ButtonStyle {
  public init() {}
  public func makeBody(configuration: Configuration) -> some View {
    let isEnabled = EnvironmentValues.current.isEnabled
    let alpha = !isEnabled ? 0.40 : (configuration.isPressed ? 0.70 : 1.0)
    return configuration.label
      .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary)
      .opacity(alpha)
  }
}

extension ButtonStyle where Self == DefaultButtonStyle {
  public static var automatic: DefaultButtonStyle { DefaultButtonStyle() }
}
extension ButtonStyle where Self == BorderedButtonStyle {
  public static var bordered: BorderedButtonStyle { BorderedButtonStyle() }
}
extension ButtonStyle where Self == BorderedProminentButtonStyle {
  public static var borderedProminent: BorderedProminentButtonStyle { BorderedProminentButtonStyle() }
}
extension ButtonStyle where Self == BorderlessButtonStyle {
  public static var borderless: BorderlessButtonStyle { BorderlessButtonStyle() }
}
extension ButtonStyle where Self == LinkButtonStyle {
  public static var link: LinkButtonStyle { LinkButtonStyle() }
}

extension View {
  @_disfavoredOverload
  public func buttonStyle<S: ButtonStyle>(_ style: S) -> some View {
    environment(\.inheritedButtonStyle) { label, role, path, action in
      let btn = Button(role: role, action: action) { label }
      return _render(StyledButton(button: btn, style: style), path: path)
    }
  }

  public func controlSize(_ controlSize: ControlSize) -> some View {
    environment(\.controlSize, controlSize)
  }
}

// MARK: - LabeledContent

public struct LabeledContent<Label: View, Content: View>: View {
  let label: Label
  let content: Content
  @Environment(\.labelsHidden) private var labelsHidden

  public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
    self.content = content()
    self.label = label()
  }

  public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content)
  where Label == Text {
    self.label = Text(titleKey)
    self.content = content()
  }

  @_disfavoredOverload
  public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content)
  where Label == Text {
    self.label = Text(verbatim: String(title))
    self.content = content()
  }

  public init<S: StringProtocol>(_ titleKey: LocalizedStringKey, value: S)
  where Label == Text, Content == Text {
    self.label = Text(titleKey)
    self.content = Text(verbatim: String(value))
  }

  @_disfavoredOverload
  public init<S1: StringProtocol, S2: StringProtocol>(_ title: S1, value: S2)
  where Label == Text, Content == Text {
    self.label = Text(verbatim: String(title))
    self.content = Text(verbatim: String(value))
  }

  public var body: some View {
    if labelsHidden {
      content
    } else {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          label
        }
        Spacer(minLength: 12)
        content
      }
      .frame(maxWidth: .infinity)
    }
  }
}

// MARK: - Semantic Control Wrapper

private struct SemanticControlWrapper<Content: View>: View, _PrimitiveView {
  typealias Body = Never
  let semantic: SemanticControl
  let content: Content
  var boolAction: ((Bool) -> Void)? = nil
  var doubleAction: ((Double, Bool) -> Void)? = nil
  var intAction: ((Int) -> Void)? = nil
  var incrementAction: (() -> Void)? = nil
  var decrementAction: (() -> Void)? = nil
  var backAction: (() -> Void)? = nil
  var tapAction: (() -> Void)? = nil

  var body: Never { fatalError("SemanticControlWrapper is primitive") }

  func _makeElement(path: ViewPath) -> Element {
    var element = _render(content, path: path)
    element.props.semanticControl = semantic
    if let boolAction { element.semanticBoolAction = boolAction }
    if let doubleAction { element.semanticDoubleAction = doubleAction }
    if let intAction { element.semanticIntAction = intAction }
    if let incrementAction { element.semanticIncrementAction = incrementAction }
    if let decrementAction { element.semanticDecrementAction = decrementAction }
    if let backAction { element.semanticBackAction = backAction }
    if let tapAction { element.action = tapAction }
    return element
  }
}

// MARK: - Toggle & ToggleStyle

public struct ToggleStyleConfiguration {
  public typealias Label = AnyView
  public let label: Label
  @Binding public var isOn: Bool

  public init(label: Label, isOn: Binding<Bool>) {
    self.label = label
    self._isOn = isOn
  }
}

@MainActor @preconcurrency
public protocol ToggleStyle {
  associatedtype Body: View
  typealias Configuration = ToggleStyleConfiguration
  @ViewBuilder func makeBody(configuration: Configuration) -> Body
}

public struct SwitchToggleStyle: ToggleStyle {
  public var tint: Color?
  public init(tint: Color? = nil) { self.tint = tint }

  public func makeBody(configuration: Configuration) -> some View {
    @Environment(\.labelsHidden) var labelsHidden
    #if os(Android) || CROSS_SWIFTUI_HARMONY
    let trackWidth: CGFloat = 64
    let trackHeight: CGFloat = 34
    let thumbSize: CGFloat = 24
    #else
    let trackWidth: CGFloat = 34
    let trackHeight: CGFloat = 20
    let thumbSize: CGFloat = 16
    #endif
    let pill = SemanticControlWrapper(
      semantic: SemanticControl(
        kind: "switch",
        boolValue: configuration.isOn,
        tint: tint
      ),
      content: Button {
        withAnimation(.easeOut(duration: 0.14)) {
          configuration.isOn.toggle()
        }
      } label: {
        ZStack(alignment: configuration.isOn ? .trailing : .leading) {
          Capsule()
            .fill(
              configuration.isOn
                ? (tint ?? Color.accentColor)
                : Color { scheme in scheme == .dark ? (1, 1, 1, 0.18) : (0, 0, 0, 0.16) }
            )
            .frame(width: trackWidth, height: trackHeight)
          Circle()
            .fill(Color.white)
            .frame(width: thumbSize, height: thumbSize)
            .padding(.horizontal, 2)
        }
      }
      .buttonStyle(.plain),
      boolAction: { newValue in
        withAnimation(.easeOut(duration: 0.14)) {
          configuration.isOn = newValue
        }
      }
    )

    return Group {
      if labelsHidden {
        pill
      } else {
        HStack(alignment: .center, spacing: 12) {
          VStack(alignment: .leading, spacing: 2) {
            configuration.label
          }
          Spacer(minLength: 12)
          pill
        }
        .frame(maxWidth: .infinity)
      }
    }
  }
}

public struct CheckboxToggleStyle: ToggleStyle {
  public init() {}
  public func makeBody(configuration: Configuration) -> some View {
    @Environment(\.labelsHidden) var labelsHidden
    #if os(Android) || CROSS_SWIFTUI_HARMONY
    let boxSize: CGFloat = 28
    #else
    let boxSize: CGFloat = 16
    #endif
    let box = SemanticControlWrapper(
      semantic: SemanticControl(
        kind: "checkbox",
        boolValue: configuration.isOn,
        tint: EnvironmentValues.current.tint
      ),
      content: Button {
        configuration.isOn.toggle()
      } label: {
        ZStack {
          RoundedRectangle(cornerRadius: 4)
            .fill(
              configuration.isOn
                ? Color.accentColor
                : Color { scheme in scheme == .dark ? (1, 1, 1, 0.08) : (0, 0, 0, 0.06) }
            )
            .frame(width: boxSize, height: boxSize)
            .overlay {
              RoundedRectangle(cornerRadius: 4)
                .strokeBorder(
                  configuration.isOn
                    ? Color.clear
                    : Color { scheme in scheme == .dark ? (1, 1, 1, 0.24) : (0, 0, 0, 0.24) },
                  lineWidth: 1
                )
            }
          if configuration.isOn {
            Image(systemName: "checkmark")
              .font(.system(size: 10, weight: .bold))
              .foregroundStyle(.white)
          }
        }
      }
      .buttonStyle(.plain),
      boolAction: { newValue in
        configuration.isOn = newValue
      }
    )

    return Group {
      if labelsHidden {
        box
      } else {
        HStack(alignment: .center, spacing: 8) {
          box
          VStack(alignment: .leading, spacing: 2) {
            configuration.label
          }
        }
      }
    }
  }
}

public struct ButtonToggleStyle: ToggleStyle {
  public init() {}
  public func makeBody(configuration: Configuration) -> some View {
    #if os(Android) || CROSS_SWIFTUI_HARMONY
    if configuration.isOn {
      Button {
        configuration.isOn.toggle()
      } label: {
        configuration.label
      }
      .buttonStyle(.borderedProminent)
    } else {
      Button {
        configuration.isOn.toggle()
      } label: {
        configuration.label
      }
      .buttonStyle(.bordered)
    }
    #else
    Button {
      configuration.isOn.toggle()
    } label: {
      configuration.label
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
          configuration.isOn ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.06),
          in: RoundedRectangle(cornerRadius: 6)
        )
    }
    .buttonStyle(.plain)
    #endif
  }
}

extension ToggleStyle where Self == SwitchToggleStyle {
  public static var automatic: SwitchToggleStyle { SwitchToggleStyle() }
  public static var `switch`: SwitchToggleStyle { SwitchToggleStyle() }
}
extension ToggleStyle where Self == CheckboxToggleStyle {
  public static var checkbox: CheckboxToggleStyle { CheckboxToggleStyle() }
}
extension ToggleStyle where Self == ButtonToggleStyle {
  public static var button: ButtonToggleStyle { ButtonToggleStyle() }
}

private enum ToggleStyleKey: EnvironmentKey {
  nonisolated(unsafe) static let defaultValue: (@MainActor (ToggleStyleConfiguration) -> AnyView)? = nil
}

extension EnvironmentValues {
  fileprivate var customToggleStyle: (@MainActor (ToggleStyleConfiguration) -> AnyView)? {
    get { self[ToggleStyleKey.self] }
    set { self[ToggleStyleKey.self] = newValue }
  }
}

extension View {
  public func toggleStyle<S: ToggleStyle>(_ style: S) -> some View {
    environment(\.customToggleStyle) { config in
      AnyView(style.makeBody(configuration: config))
    }
  }
}

public struct Toggle<Label: View>: View {
  let isOn: Binding<Bool>
  let label: Label
  @Environment(\.customToggleStyle) private var customStyle

  public init(isOn: Binding<Bool>, @ViewBuilder label: () -> Label) {
    self.isOn = isOn
    self.label = label()
  }

  public init(_ titleKey: LocalizedStringKey, isOn: Binding<Bool>) where Label == Text {
    self.isOn = isOn
    self.label = Text(titleKey)
  }

  @_disfavoredOverload
  public init<S: StringProtocol>(_ title: S, isOn: Binding<Bool>) where Label == Text {
    self.isOn = isOn
    self.label = Text(verbatim: String(title))
  }

  public init(_ titleKey: LocalizedStringKey, systemImage: String, isOn: Binding<Bool>)
  where Label == SwiftUIRuntime.Label<Text, Image> {
    self.isOn = isOn
    self.label = SwiftUIRuntime.Label(titleKey, systemImage: systemImage)
  }

  public var body: some View {
    let config = ToggleStyleConfiguration(label: AnyView(label), isOn: isOn)
    if let customStyle {
      customStyle(config)
    } else {
      SwitchToggleStyle().makeBody(configuration: config)
    }
  }
}

// MARK: - Picker & PickerStyle

public enum PickerStyleKind: Sendable {
  case menu, segmented, inline, radioGroup
}

public struct PickerStyle: Sendable {
  let kind: PickerStyleKind
  public static let automatic = PickerStyle(kind: .menu)
  public static let menu = PickerStyle(kind: .menu)
  public static let segmented = PickerStyle(kind: .segmented)
  public static let inline = PickerStyle(kind: .inline)
  public static let radioGroup = PickerStyle(kind: .radioGroup)
}

private enum PickerStyleKey: EnvironmentKey {
  static let defaultValue: PickerStyle = .automatic
}

extension EnvironmentValues {
  fileprivate var pickerStyle: PickerStyle {
    get { self[PickerStyleKey.self] }
    set { self[PickerStyleKey.self] = newValue }
  }
}

extension View {
  public func pickerStyle(_ style: PickerStyle) -> some View {
    environment(\.pickerStyle, style)
  }
}

private struct ExtractedOption {
  let tag: AnyHashable
  let title: String
}

@MainActor
private func extractTaggedOptions<C: View>(from content: C) -> [ExtractedOption] {
  let tree = _render(content, path: ViewPath())
  var results: [ExtractedOption] = []
  func textOf(_ el: Element) -> String {
    if el.kind == .text && !el.props.text.isEmpty { return el.props.text }
    for c in el.children {
      let t = textOf(c)
      if !t.isEmpty { return t }
    }
    return ""
  }
  func walk(_ el: Element) {
    if let tag = el.tagValue ?? el.explicitID {
      let t = textOf(el)
      if !t.isEmpty || el.tagValue != nil {
        results.append(ExtractedOption(tag: tag, title: t))
        return
      }
    }
    for c in el.children { walk(c) }
  }
  walk(tree)
  return results
}

public struct Picker<Label: View, SelectionValue: Hashable, Content: View>: View {
  let selection: Binding<SelectionValue>
  let label: Label
  let content: Content
  @State private var menuExpanded = false
  @Environment(\.pickerStyle) private var style
  @Environment(\.labelsHidden) private var labelsHidden

  public init(
    selection: Binding<SelectionValue>,
    @ViewBuilder content: () -> Content,
    @ViewBuilder label: () -> Label
  ) {
    self.selection = selection
    self.content = content()
    self.label = label()
  }

  public init(
    _ titleKey: LocalizedStringKey,
    selection: Binding<SelectionValue>,
    @ViewBuilder content: () -> Content
  ) where Label == Text {
    self.selection = selection
    self.content = content()
    self.label = Text(titleKey)
  }

  @_disfavoredOverload
  public init<S: StringProtocol>(
    _ title: S,
    selection: Binding<SelectionValue>,
    @ViewBuilder content: () -> Content
  ) where Label == Text {
    self.selection = selection
    self.content = content()
    self.label = Text(verbatim: String(title))
  }

  public var body: some View {
    let options = extractTaggedOptions(from: content)
    let currentKey = AnyHashable(selection.wrappedValue)
    let selectedTitle = options.first(where: { $0.tag == currentKey })?.title
      ?? String(describing: selection.wrappedValue)

    let control = Group {
      switch style.kind {
      case .segmented:
        let selectedIdx = options.firstIndex(where: { $0.tag == currentKey }) ?? 0
        let ctrlSize = EnvironmentValues.current.controlSize
        #if os(Android) || CROSS_SWIFTUI_HARMONY
        let segMinHeight: CGFloat = 40
        let segHPad: CGFloat = 10
        let segVPad: CGFloat = 4
        #else
        let segMinHeight: CGFloat =
          switch ctrlSize {
          case .large, .extraLarge: 28
          case .small, .mini: 20
          case .regular: 24
          }
        let segHPad: CGFloat = (ctrlSize == .small || ctrlSize == .mini) ? 8 : 12
        let segVPad: CGFloat =
          switch ctrlSize {
          case .large, .extraLarge: 5
          case .small, .mini: 2
          case .regular: 3
          }
        #endif
        SemanticControlWrapper(
          semantic: SemanticControl(
            kind: "segmented",
            intValue: selectedIdx,
            items: options.map(\.title),
            tint: EnvironmentValues.current.tint
          ),
          content: HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
              let isSelected = opt.tag == currentKey
              Button {
                if let typed = opt.tag.base as? SelectionValue {
                  selection.wrappedValue = typed
                }
              } label: {
                #if os(Android) || CROSS_SWIFTUI_HARMONY
                Text(verbatim: opt.title)
                  .font(.callout.weight(isSelected ? .medium : .regular))
                  .lineLimit(1)
                  .padding(.horizontal, segHPad)
                  .padding(.vertical, segVPad)
                  .frame(maxWidth: .infinity, minHeight: segMinHeight - 4)
                  .background(
                    isSelected
                      ? Color { s in s == .dark ? (1, 1, 1, 0.16) : (1, 1, 1, 0.92) }
                      : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5)
                  )
                #else
                ZStack {
                  // Reserve medium-weight width so switching segments never shifts outer bounds.
                  Text(verbatim: opt.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .opacity(0)
                    .accessibilityHidden(true)
                  Text(verbatim: opt.title)
                    .font(.callout.weight(isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                }
                .padding(.horizontal, segHPad)
                .padding(.vertical, segVPad)
                .frame(minHeight: segMinHeight - 4)
                .background(
                  isSelected
                    ? Color { s in s == .dark ? (1, 1, 1, 0.18) : (1, 1, 1, 0.96) }
                    : Color.clear,
                  in: RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                )
                #endif
              }
              .buttonStyle(.plain)
            }
          }
          .padding(2)
          .frame(minHeight: segMinHeight)
          .background(
            Color { s in s == .dark ? (1, 1, 1, 0.07) : (0, 0, 0, 0.06) },
            in: RoundedRectangle(cornerRadius: 7, style: .continuous)
          )
          .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
              .strokeBorder(
                Color { s in s == .dark ? (1, 1, 1, 0.09) : (0, 0, 0, 0.08) },
                lineWidth: 1
              )
          },
          intAction: { idx in
            guard idx >= 0, idx < options.count else { return }
            if let typed = options[idx].tag.base as? SelectionValue {
              selection.wrappedValue = typed
            }
          }
        )

      case .inline, .radioGroup:
        VStack(alignment: .leading, spacing: 6) {
          ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
            let isSelected = opt.tag == currentKey
            Button {
              if let typed = opt.tag.base as? SelectionValue {
                selection.wrappedValue = typed
              }
            } label: {
              HStack(spacing: 8) {
                ZStack {
                  Circle()
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.3), lineWidth: 1.5)
                    .frame(width: 14, height: 14)
                  if isSelected {
                    Circle().fill(Color.accentColor).frame(width: 7, height: 7)
                  }
                }
                Text(verbatim: opt.title).font(.body)
              }
            }
            .buttonStyle(.plain)
          }
        }

      case .menu:
        let selectedIdx = options.firstIndex(where: { $0.tag == currentKey }) ?? 0
        #if os(Android) || CROSS_SWIFTUI_HARMONY
        let menuMinHeight: CGFloat = 38
        #else
        let menuMinHeight: CGFloat = 24
        #endif
        SemanticControlWrapper(
          semantic: SemanticControl(
            kind: "menu",
            intValue: selectedIdx,
            items: options.map(\.title),
            title: selectedTitle,
            tint: EnvironmentValues.current.tint
          ),
          content: Button {
            menuExpanded.toggle()
          } label: {
            HStack(spacing: 6) {
              Text(verbatim: selectedTitle)
                .font(.callout)
                .lineLimit(1)
              Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: menuMinHeight)
            .background(
              Color { s in s == .dark ? (1, 1, 1, 0.08) : (0, 0, 0, 0.06) },
              in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay {
              RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                  Color { s in s == .dark ? (1, 1, 1, 0.14) : (0, 0, 0, 0.12) },
                  lineWidth: 1
                )
            }
          }
          .buttonStyle(.plain)
          ._menuPopover(isPresented: $menuExpanded, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 2) {
              ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                let isSelected = opt.tag == currentKey
                Button {
                  if let typed = opt.tag.base as? SelectionValue {
                    selection.wrappedValue = typed
                  }
                  menuExpanded = false
                } label: {
                  HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                      .font(.system(size: 11, weight: .semibold))
                      .opacity(isSelected ? 1 : 0)
                    Text(verbatim: opt.title)
                      .font(.callout)
                      .lineLimit(1)
                  }
                }
                .buttonStyle(_MenuRowButtonStyle(isSelected: isSelected, role: nil))
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            .frame(maxWidth: 300, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
            .background(
              Color { s in s == .dark ? (0.16, 0.16, 0.18, 0.98) : (0.98, 0.98, 0.99, 0.98) },
              in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
              RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color { s in s == .dark ? (1, 1, 1, 0.14) : (0, 0, 0, 0.12) }, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 4)
          },
          intAction: { idx in
            guard idx >= 0, idx < options.count else { return }
            if let typed = options[idx].tag.base as? SelectionValue {
              selection.wrappedValue = typed
            }
          }
        )
      }
    }

    if labelsHidden {
      control
    } else {
      HStack(alignment: .center, spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          label
        }
        Spacer(minLength: 12)
        control
      }
      .frame(maxWidth: .infinity)
    }
  }
}

// MARK: - Slider & Stepper

public struct Slider<Label: View, ValueLabel: View>: View {
  let value: Binding<Double>
  let bounds: ClosedRange<Double>
  let step: Double?
  let onEditingChanged: (Bool) -> Void
  let label: Label
  let minLabel: ValueLabel
  let maxLabel: ValueLabel
  @Environment(\.labelsHidden) private var labelsHidden

  public init<V: BinaryFloatingPoint>(
    value: Binding<V>,
    in bounds: ClosedRange<V> = 0...1,
    step: V.Stride? = nil,
    @ViewBuilder label: () -> Label,
    @ViewBuilder minimumValueLabel: () -> ValueLabel,
    @ViewBuilder maximumValueLabel: () -> ValueLabel,
    onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) where V.Stride: BinaryFloatingPoint {
    self.value = Binding(
      get: { Double(value.wrappedValue) },
      set: { value.wrappedValue = V($0) }
    )
    self.bounds = Double(bounds.lowerBound)...Double(bounds.upperBound)
    self.step = step.map { Double($0) }
    self.onEditingChanged = onEditingChanged
    self.label = label()
    self.minLabel = minimumValueLabel()
    self.maxLabel = maximumValueLabel()
  }

  public init<V: BinaryFloatingPoint>(
    value: Binding<V>,
    in bounds: ClosedRange<V> = 0...1,
    step: V.Stride? = nil,
    @ViewBuilder label: () -> Label,
    onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) where ValueLabel == EmptyView, V.Stride: BinaryFloatingPoint {
    self.init(
      value: value, in: bounds, step: step, label: label,
      minimumValueLabel: { EmptyView() }, maximumValueLabel: { EmptyView() },
      onEditingChanged: onEditingChanged
    )
  }

  public init<V: BinaryFloatingPoint>(
    value: Binding<V>,
    in bounds: ClosedRange<V> = 0...1,
    step: V.Stride? = nil,
    onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) where Label == EmptyView, ValueLabel == EmptyView, V.Stride: BinaryFloatingPoint {
    self.init(
      value: value, in: bounds, step: step, label: { EmptyView() },
      minimumValueLabel: { EmptyView() }, maximumValueLabel: { EmptyView() },
      onEditingChanged: onEditingChanged
    )
  }

  public var body: some View {
    let span = max(1e-9, bounds.upperBound - bounds.lowerBound)
    let fraction = min(1, max(0, (value.wrappedValue - bounds.lowerBound) / span))
    #if os(Android) || CROSS_SWIFTUI_HARMONY
    let sliderHeight: CGFloat = 40
    #else
    let sliderHeight: CGFloat = 20
    #endif
    let sliderBar = SemanticControlWrapper(
      semantic: SemanticControl(
        kind: "slider",
        doubleValue: value.wrappedValue,
        minValue: bounds.lowerBound,
        maxValue: bounds.upperBound,
        stepValue: step ?? 0,
        tint: EnvironmentValues.current.tint
      ),
      content: GeometryReader { geo in
        let w = max(1, geo.size.width)
        ZStack(alignment: .leading) {
          Capsule()
            .fill(Color.primary.opacity(0.15))
            .frame(height: 4)
          Capsule()
            .fill(Color.accentColor)
            .frame(width: w * CGFloat(fraction), height: 4)
          Circle()
            .fill(Color.white)
            .frame(width: 14, height: 14)
            .overlay { Circle().strokeBorder(Color.black.opacity(0.20), lineWidth: 1) }
            .offset(x: max(0, min(w - 14, w * CGFloat(fraction) - 7)))
        }
        .frame(height: sliderHeight)
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { drag in
              onEditingChanged(true)
              let f = min(1, max(0, Double(drag.location.x / w)))
              var raw = bounds.lowerBound + f * span
              if let step, step > 0 {
                raw = bounds.lowerBound + ((raw - bounds.lowerBound) / step).rounded() * step
              }
              value.wrappedValue = min(bounds.upperBound, max(bounds.lowerBound, raw))
            }
            .onEnded { _ in
              onEditingChanged(false)
            }
        )
      }
      .frame(minWidth: 120, idealWidth: 160, minHeight: sliderHeight, maxHeight: sliderHeight),
      doubleAction: { newValue, ended in
        onEditingChanged(!ended)
        var raw = newValue
        if let step, step > 0 {
          raw = bounds.lowerBound + ((raw - bounds.lowerBound) / step).rounded() * step
        }
        value.wrappedValue = min(bounds.upperBound, max(bounds.lowerBound, raw))
        if ended { onEditingChanged(false) }
      }
    )
    let trackControl = HStack(spacing: 8) {
      minLabel
      sliderBar
      maxLabel
    }

    if labelsHidden || Label.self == EmptyView.self {
      trackControl
    } else {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) { label }
        Spacer(minLength: 12)
        trackControl
      }
    }
  }
}

public struct Stepper<Label: View>: View {
  let label: Label
  let onIncrement: (() -> Void)?
  let onDecrement: (() -> Void)?
  @Environment(\.labelsHidden) private var labelsHidden

  public init(
    @ViewBuilder label: () -> Label,
    onIncrement: (() -> Void)?,
    onDecrement: (() -> Void)?,
    onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) {
    self.label = label()
    self.onIncrement = onIncrement
    self.onDecrement = onDecrement
  }

  public init<V: Strideable>(
    value: Binding<V>,
    in bounds: ClosedRange<V>,
    step: V.Stride = 1,
    @ViewBuilder label: () -> Label,
    onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) {
    self.label = label()
    self.onIncrement = {
      let next = value.wrappedValue.advanced(by: step)
      if next <= bounds.upperBound { value.wrappedValue = next }
    }
    self.onDecrement = {
      let prev = value.wrappedValue.advanced(by: -step)
      if prev >= bounds.lowerBound { value.wrappedValue = prev }
    }
  }

  public init<V: Strideable>(
    _ titleKey: LocalizedStringKey,
    value: Binding<V>,
    in bounds: ClosedRange<V>,
    step: V.Stride = 1,
    onEditingChanged: @escaping (Bool) -> Void = { _ in }
  ) where Label == Text {
    self.init(value: value, in: bounds, step: step, label: { Text(titleKey) }, onEditingChanged: onEditingChanged)
  }

  public var body: some View {
    #if os(Android) || CROSS_SWIFTUI_HARMONY
    let stepW: CGFloat = 100
    let stepH: CGFloat = 36
    #else
    let stepW: CGFloat = 48
    let stepH: CGFloat = 24
    #endif
    let buttons = SemanticControlWrapper(
      semantic: SemanticControl(
        kind: "stepper",
        tint: EnvironmentValues.current.tint
      ),
      content: HStack(spacing: 2) {
        Button { onDecrement?() } label: {
          Image(systemName: "minus").font(.system(size: 11, weight: .semibold)).frame(width: 22, height: 22)
        }
        .buttonStyle(.bordered)
        Button { onIncrement?() } label: {
          Image(systemName: "plus").font(.system(size: 11, weight: .semibold)).frame(width: 22, height: 22)
        }
        .buttonStyle(.bordered)
      }
      .frame(minWidth: stepW, minHeight: stepH),
      incrementAction: onIncrement,
      decrementAction: onDecrement
    )

    if labelsHidden {
      buttons
    } else {
      HStack(spacing: 12) {
        label
        Spacer(minLength: 12)
        buttons
      }
    }
  }
}

// MARK: - Menu & ControlGroup

public struct MenuStyle: Sendable {
  public static let automatic = MenuStyle()
  public static let button = MenuStyle()
  public static let borderlessButton = MenuStyle()
}

public struct MenuOrder: Equatable, Sendable {
  public static let automatic = MenuOrder()
  public static let priority = MenuOrder()
  public static let fixed = MenuOrder()
}

public struct MenuActionDismissBehavior: Equatable, Sendable {
  public static let automatic = MenuActionDismissBehavior()
  public static let enabled = MenuActionDismissBehavior()
  public static let disabled = MenuActionDismissBehavior()
}

public struct Menu<Label: View, Content: View>: View {
  let label: Label
  let content: Content
  let primaryAction: (() -> Void)?
  @State private var isExpanded = false
  @Environment(\.menuIndicatorVisibility) private var indicatorVisibility

  public init(@ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
    self.content = content()
    self.label = label()
    self.primaryAction = nil
  }

  public init(
    @ViewBuilder content: () -> Content,
    @ViewBuilder label: () -> Label,
    primaryAction: @escaping () -> Void
  ) {
    self.content = content()
    self.label = label()
    self.primaryAction = primaryAction
  }

  public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content)
  where Label == Text {
    self.content = content()
    self.label = Text(titleKey)
    self.primaryAction = nil
  }

  @_disfavoredOverload
  public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content)
  where Label == Text {
    self.content = content()
    self.label = Text(verbatim: String(title))
    self.primaryAction = nil
  }

  public init(_ titleKey: LocalizedStringKey, systemImage: String, @ViewBuilder content: () -> Content)
  where Label == SwiftUIRuntime.Label<Text, Image> {
    self.content = content()
    self.label = SwiftUIRuntime.Label(titleKey, systemImage: systemImage)
    self.primaryAction = nil
  }

  public var body: some View {
    Button {
      if let primaryAction {
        primaryAction()
      } else {
        isExpanded.toggle()
      }
    } label: {
      HStack(spacing: 4) {
        label
        if indicatorVisibility != .hidden {
          Image(systemName: "chevron.down")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
        }
      }
    }
    .buttonStyle(.bordered)
    ._menuPopover(isPresented: $isExpanded, arrowEdge: .top) {
      VStack(alignment: .leading, spacing: 2) {
        content
          ._menuItemButtonStyle()
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(6)
      .frame(maxWidth: 300, alignment: .leading)
      .fixedSize(horizontal: true, vertical: false)
      .background(
        Color { s in s == .dark ? (0.16, 0.16, 0.18, 0.98) : (0.98, 0.98, 0.99, 0.98) },
        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .strokeBorder(Color { s in s == .dark ? (1, 1, 1, 0.14) : (0, 0, 0, 0.12) }, lineWidth: 1)
      }
      .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 4)
    }
  }
}

struct _MenuRowButtonStyle: ButtonStyle {
  let isSelected: Bool
  let role: ButtonRole?

  func makeBody(configuration: Configuration) -> some View {
    RowBody(configuration: configuration, isSelected: isSelected, role: role)
  }

  private struct RowBody: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    let role: ButtonRole?
    @State private var hovered = false

    var body: some View {
      let isEnabled = EnvironmentValues.current.isEnabled
      let isPressed = isEnabled && configuration.isPressed
      let isHovered = isEnabled && hovered
      let isDestructive = role == .destructive
      let isSelectedRow = isSelected
      let fill: Color = {
        if isPressed {
          return isDestructive ? Color.red.opacity(0.24) : Color.accentColor.opacity(0.32)
        }
        if isHovered {
          if isSelectedRow {
            return Color.accentColor.opacity(0.28)
          }
          if isDestructive {
            return Color.red.opacity(0.18)
          }
          return Color { s in s == .dark ? (1, 1, 1, 0.11) : (0, 0, 0, 0.08) }
        }
        if isSelectedRow {
          return Color.accentColor.opacity(0.20)
        }
        return .clear
      }()
      configuration.label
        .font(.callout)
        .lineLimit(1)
        .foregroundStyle(isDestructive ? Color.red : Color.primary)
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .opacity(isEnabled ? 1.0 : 0.45)
        .onHover { hovered = $0 }
    }
  }
}

extension View {
  func _menuItemButtonStyle() -> some View {
    environment(\.inheritedButtonStyle) { label, role, path, action in
      let btn = Button(role: role, action: action) { label }
      return _render(StyledButton(button: btn, style: _MenuRowButtonStyle(isSelected: false, role: role)), path: path)
    }
  }
}

private enum MenuIndicatorKey: EnvironmentKey {
  static let defaultValue: Visibility = .automatic
}

extension EnvironmentValues {
  fileprivate var menuIndicatorVisibility: Visibility {
    get { self[MenuIndicatorKey.self] }
    set { self[MenuIndicatorKey.self] = newValue }
  }
}

extension View {
  public func menuStyle(_ style: MenuStyle) -> some View { self }
  public func menuIndicator(_ visibility: Visibility) -> some View {
    environment(\.menuIndicatorVisibility, visibility)
  }
  public func menuOrder(_ order: MenuOrder) -> some View { self }
  public func menuActionDismissBehavior(_ behavior: MenuActionDismissBehavior) -> some View { self }
}

public struct ControlGroupStyle: Sendable {
  public static let automatic = ControlGroupStyle()
  public static let navigation = ControlGroupStyle()
}

public struct ControlGroup<Content: View>: View {
  let content: Content
  public init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }
  public var body: some View {
    HStack(spacing: 4) {
      content
    }
  }
}

extension View {
  public func controlGroupStyle(_ style: ControlGroupStyle) -> some View { self }
}

// MARK: - Form & Section

public struct FormStyle: Sendable {
  public enum Kind: Sendable { case automatic, grouped, columns }
  let kind: Kind
  public static let automatic = FormStyle(kind: .grouped)
  public static let grouped = FormStyle(kind: .grouped)
  public static let columns = FormStyle(kind: .columns)
}

private enum InGroupedFormKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  fileprivate var inGroupedForm: Bool {
    get { self[InGroupedFormKey.self] }
    set { self[InGroupedFormKey.self] = newValue }
  }
}

extension View {
  public func formStyle(_ style: FormStyle) -> some View {
    environment(\.inGroupedForm, style.kind != .columns)
  }
}

public struct Form<Content: View>: View {
  let content: Content

  public init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  public var body: some View {
    ScrollView(.vertical) {
      VStack(alignment: .leading, spacing: 18) {
        content
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .environment(\.inGroupedForm, true)
    }
  }
}

private struct GroupedSectionRows<Content: View>: View, _PrimitiveView {
  typealias Body = Never
  let content: Content
  var body: Never { fatalError() }

  func _makeElement(path: ViewPath) -> Element {
    let raw = flattenChildren(_render(content, path: path))
    guard !raw.isEmpty else { return Element(kind: .empty) }
    let sepColor = SeparatorShapeStyle()._resolvePrimaryColor(in: EnvironmentValues.current)
    var interspersed: [Element] = []
    #if os(Android) || CROSS_SWIFTUI_HARMONY
    let rowInsets = EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
    #else
    let rowInsets = EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
    #endif
    for (idx, item) in raw.enumerated() {
      if idx > 0 {
        var sp = NodeProps()
        sp.background = sepColor
        sp.frameHeight = 1
        sp.fillWidth = true
        sp.semanticControl = SemanticControl(kind: "divider")
        let sepLine = Element(kind: .shape, props: sp)
        #if os(Android) || CROSS_SWIFTUI_HARMONY
        var sepWrap = NodeProps()
        sepWrap.padding = EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 0)
        sepWrap.fillWidth = true
        interspersed.append(Element(kind: .padding, props: sepWrap, children: [sepLine]))
        #else
        interspersed.append(sepLine)
        #endif
      }
      var rowWrap = NodeProps()
      rowWrap.padding = rowInsets
      rowWrap.fillWidth = true
      rowWrap.alignment = .leading
      rowWrap.semanticControl = SemanticControl(kind: "listItem")
      interspersed.append(Element(kind: .padding, props: rowWrap, children: [item]))
    }
    var vp = NodeProps()
    vp.spacing = 0
    vp.horizontalAlignment = .leading
    vp.fillWidth = true
    return Element(kind: .container(.vertical), props: vp, children: interspersed)
  }
}

public struct Section<Parent: View, Content: View, Footer: View>: View {
  let header: Parent
  let content: Content
  let footer: Footer
  @Environment(\.inGroupedForm) private var inGroupedForm

  public init(
    @ViewBuilder content: () -> Content,
    @ViewBuilder header: () -> Parent,
    @ViewBuilder footer: () -> Footer
  ) {
    self.content = content()
    self.header = header()
    self.footer = footer()
  }

  public var body: some View {
    if inGroupedForm {
      #if os(Android) || CROSS_SWIFTUI_HARMONY
      VStack(alignment: .leading, spacing: 8) {
        if Parent.self != EmptyView.self {
          header
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
        }
        GroupedSectionRows(content: content)
          .background(
            Color { s in s == .dark ? (0.11, 0.11, 0.12, 1) : (1, 1, 1, 1) },
            in: RoundedRectangle(cornerRadius: 26)
          )
        if Footer.self != EmptyView.self {
          footer
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      #else
      VStack(alignment: .leading, spacing: 6) {
        if Parent.self != EmptyView.self {
          header
            .font(.headline)
            .padding(.horizontal, 4)
        }
        GroupedSectionRows(content: content)
          .background(
            Color { s in s == .dark ? (1, 1, 1, 0.05) : (0, 0, 0, 0.04) },
            in: RoundedRectangle(cornerRadius: 10)
          )
          .overlay {
            RoundedRectangle(cornerRadius: 10)
              .strokeBorder(
                Color { s in s == .dark ? (1, 1, 1, 0.10) : (0, 0, 0, 0.10) },
                lineWidth: 1
              )
          }
        if Footer.self != EmptyView.self {
          footer
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      #endif
    } else {
      VStack(alignment: .leading, spacing: 4) {
        if Parent.self != EmptyView.self {
          header
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 6)
        }
        content
        if Footer.self != EmptyView.self {
          footer
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
        }
      }
    }
  }
}

extension Section where Parent == EmptyView, Footer == EmptyView {
  public init(@ViewBuilder content: () -> Content) {
    self.init(content: content, header: { EmptyView() }, footer: { EmptyView() })
  }
}

extension Section where Footer == EmptyView {
  public init(@ViewBuilder content: () -> Content, @ViewBuilder header: () -> Parent) {
    self.init(content: content, header: header, footer: { EmptyView() })
  }

  public init(_ titleKey: LocalizedStringKey, @ViewBuilder content: () -> Content)
  where Parent == Text {
    self.init(content: content, header: { Text(titleKey) }, footer: { EmptyView() })
  }

  @_disfavoredOverload
  public init<S: StringProtocol>(_ title: S, @ViewBuilder content: () -> Content)
  where Parent == Text {
    self.init(content: content, header: { Text(verbatim: String(title)) }, footer: { EmptyView() })
  }

  public init(
    isExpanded: Binding<Bool>,
    @ViewBuilder content: () -> Content,
    @ViewBuilder header: () -> Parent
  ) {
    self.init(
      content: content,
      header: header,
      footer: { EmptyView() }
    )
  }
}

extension Section where Parent == EmptyView {
  public init(@ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
    self.init(content: content, header: { EmptyView() }, footer: footer)
  }
}

// MARK: - List & ListStyle

public struct ListStyle: Sendable {
  public static let automatic = ListStyle()
  public static let plain = ListStyle()
  public static let inset = ListStyle()
  public static let insetGrouped = ListStyle()
  public static let grouped = ListStyle()
  public static let sidebar = ListStyle()
  public static let bordered = ListStyle()
}

extension View {
  public func listStyle(_ style: ListStyle) -> some View { self }
  public func listRowInsets(_ insets: EdgeInsets?) -> some View { self }
  public func listRowSeparator(_ visibility: Visibility, edges: VerticalEdge.Set = .all) -> some View { self }
  public func listSectionSeparator(_ visibility: Visibility, edges: VerticalEdge.Set = .all) -> some View { self }
  public func listRowBackground<V: View>(_ view: V?) -> some View { self }
}

private struct SelectableListBody<SelectionValue: Hashable, Content: View>: View, _PrimitiveView {
  typealias Body = Never
  let selection: Binding<SelectionValue?>?
  let content: Content

  var body: Never { fatalError() }

  func _makeElement(path: ViewPath) -> Element {
    var root = _render(content, path: path)
    let selectedTag = selection?.wrappedValue.map { AnyHashable($0) }
    func decorate(_ el: inout Element) {
      if let tag = el.tagValue {
        let isSel = (tag == selectedTag)
        let selBind = selection
        var rowProps = NodeProps()
        rowProps.padding = EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
        rowProps.cornerRadius = 7
        rowProps.fillWidth = true
        rowProps.alignment = .leading
        rowProps.background = isSel
          ? Color { s in s == .dark ? (1, 1, 1, 0.12) : (0, 0, 0, 0.09) }
          : .clear
        el = Element(
          kind: .styledButton,
          props: rowProps,
          children: [Element(kind: .padding, props: rowProps, children: [el])],
          explicitID: el.explicitID ?? tag,
          action: {
            if let typed = tag.base as? SelectionValue {
              selBind?.wrappedValue = typed
            }
          }
        )
        return
      }
      for i in el.children.indices {
        decorate(&el.children[i])
      }
    }
    decorate(&root)
    var vp = NodeProps()
    #if os(Android) || CROSS_SWIFTUI_HARMONY
    vp.spacing = 20
    #else
    vp.spacing = 2
    #endif
    vp.horizontalAlignment = .leading
    vp.fillWidth = true
    return Element(kind: .container(.vertical), props: vp, children: flattenChildren(root))
  }
}

public struct List<SelectionValue: Hashable, Content: View>: View {
  let selection: Binding<SelectionValue?>?
  let content: Content

  public init(selection: Binding<SelectionValue?>?, @ViewBuilder content: () -> Content) {
    self.selection = selection
    self.content = content()
  }

  public init(@ViewBuilder content: () -> Content) where SelectionValue == Never {
    self.selection = nil
    self.content = content()
  }

  public init<Data: RandomAccessCollection, RowContent: View>(
    _ data: Data,
    selection: Binding<SelectionValue?>? = nil,
    @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
  ) where Data.Element: Identifiable, Content == ForEach<Data, Data.Element.ID, RowContent> {
    self.selection = selection
    self.content = ForEach(data, content: rowContent)
  }

  public init<Data: RandomAccessCollection, ID: Hashable, RowContent: View>(
    _ data: Data,
    id: KeyPath<Data.Element, ID>,
    selection: Binding<SelectionValue?>? = nil,
    @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
  ) where Content == ForEach<Data, ID, RowContent> {
    self.selection = selection
    self.content = ForEach(data, id: id, content: rowContent)
  }

  public var body: some View {
    #if os(Android) || CROSS_SWIFTUI_HARMONY
    ScrollView(.vertical) {
      SelectableListBody(selection: selection, content: content)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.inGroupedForm, true)
    }
    .background(Color { s in s == .dark ? (0, 0, 0, 1) : (0.949, 0.949, 0.969, 1) })
    #else
    ScrollView(.vertical) {
      SelectableListBody(selection: selection, content: content)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.inGroupedForm, false)
    }
    #endif
  }
}

// MARK: - NavigationSplitView, Toolbar & Searchable

public struct NavigationSplitViewVisibility: Equatable, Sendable {
  public static let automatic = NavigationSplitViewVisibility()
  public static let all = NavigationSplitViewVisibility()
  public static let doubleColumn = NavigationSplitViewVisibility()
  public static let detailOnly = NavigationSplitViewVisibility()
}

public struct NavigationSplitViewStyle: Sendable {
  public static let automatic = NavigationSplitViewStyle()
  public static let balanced = NavigationSplitViewStyle()
  public static let prominentDetail = NavigationSplitViewStyle()
}

private struct SidebarColumnWidthPreferenceKey: PreferenceKey {
  static var defaultValue: CGFloat? { nil }
  static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
    value = value ?? nextValue()
  }
}

public struct NavigationSplitView<Sidebar: View, Content: View, Detail: View>: View {
  let sidebar: Sidebar
  let content: Content
  let detail: Detail
  @State private var sidebarWidth: CGFloat = 232

  public init(
    columnVisibility: Binding<NavigationSplitViewVisibility> = .constant(.all),
    @ViewBuilder sidebar: () -> Sidebar,
    @ViewBuilder detail: () -> Detail
  ) where Content == EmptyView {
    self.sidebar = sidebar()
    self.content = EmptyView()
    self.detail = detail()
  }

  public init(
    columnVisibility: Binding<NavigationSplitViewVisibility> = .constant(.all),
    @ViewBuilder sidebar: () -> Sidebar,
    @ViewBuilder content: () -> Content,
    @ViewBuilder detail: () -> Detail
  ) {
    self.sidebar = sidebar()
    self.content = content()
    self.detail = detail()
  }

  public var body: some View {
    HStack(spacing: 0) {
      sidebar
        .frame(width: sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(Color { s in s == .dark ? (0.12, 0.12, 0.14, 1.0) : (0.94, 0.94, 0.96, 1.0) })
        .onPreferenceChange(SidebarColumnWidthPreferenceKey.self) { w in
          if let w, w > 0 { sidebarWidth = w }
        }
      Divider()
      if Content.self != EmptyView.self {
        content
          .frame(maxHeight: .infinity)
          .background(Color { s in s == .dark ? (0.10, 0.10, 0.12, 1.0) : (1.0, 1.0, 1.0, 1.0) })
        Divider()
      }
      detail
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color { s in s == .dark ? (0.10, 0.10, 0.12, 1.0) : (1.0, 1.0, 1.0, 1.0) })
    }
  }
}

private struct _NavigationEntry: Identifiable {
  let id: Int
  let title: String
  let view: AnyView
}

struct _NavigationActions: Sendable {
  let push: (@MainActor @Sendable (String, AnyView) -> Void)?
  let pushValue: (@MainActor @Sendable (ObjectIdentifier, AnyHashable, Any, String) -> Void)?
  let pop: (@MainActor @Sendable () -> Void)?
  let popToRoot: (@MainActor @Sendable () -> Void)?
}

private enum _NavigationActionsKey: EnvironmentKey {
  static let defaultValue = _NavigationActions(push: nil, pushValue: nil, pop: nil, popToRoot: nil)
}

extension EnvironmentValues {
  var _navigationActions: _NavigationActions {
    get { self[_NavigationActionsKey.self] }
    set { self[_NavigationActionsKey.self] = newValue }
  }
}

private struct _NavigationTitlePreferenceKey: PreferenceKey {
  static let defaultValue: String? = nil
  static func reduce(value: inout String?, nextValue: () -> String?) {
    if let next = nextValue() { value = next }
  }
}

public struct NavigationStack<Data, Root: View>: View {
  let root: Root
  private let pathBinding: Binding<NavigationPath>?
  private let arrayPathSync: ((inout [NavigationPath.Box]) -> Void)?
  private let arrayPathPush: ((Any) -> Void)?
  private let arrayPathPop: (() -> Void)?
  private let arrayPathCount: (() -> Int)?
  private let arrayPathLast: (() -> NavigationPath.Box?)?
  @State private var entries: [_NavigationEntry] = []
  @State private var nextID: Int = 1
  @State private var rootTitle: String = ""
  @State private var detailTitle: String = ""
  @State private var destinationRegistry = _NavigationDestinationRegistry()

  public init(@ViewBuilder root: () -> Root) where Data == Never {
    self.root = root()
    self.pathBinding = nil
    self.arrayPathSync = nil
    self.arrayPathPush = nil
    self.arrayPathPop = nil
    self.arrayPathCount = nil
    self.arrayPathLast = nil
  }

  public init(path: Binding<NavigationPath>, @ViewBuilder root: () -> Root) where Data == NavigationPath {
    self.root = root()
    self.pathBinding = path
    self.arrayPathSync = nil
    self.arrayPathPush = nil
    self.arrayPathPop = nil
    self.arrayPathCount = nil
    self.arrayPathLast = nil
  }

  public init<Element: Hashable>(
    path: Binding<[Element]>,
    @ViewBuilder root: () -> Root
  ) where Data == [Element] {
    self.root = root()
    self.pathBinding = nil
    self.arrayPathSync = nil
    self.arrayPathPush = { raw in
      if let typed = raw as? Element {
        path.wrappedValue.append(typed)
      }
    }
    self.arrayPathPop = {
      if !path.wrappedValue.isEmpty {
        path.wrappedValue.removeLast()
      }
    }
    self.arrayPathCount = { path.wrappedValue.count }
    self.arrayPathLast = { path.wrappedValue.last.map { NavigationPath.Box($0) } }
  }

  @_disfavoredOverload
  public init(path: Binding<Data>, @ViewBuilder root: () -> Root) {
    self.root = root()
    self.pathBinding = nil
    self.arrayPathSync = nil
    self.arrayPathPush = nil
    self.arrayPathPop = nil
    self.arrayPathCount = nil
    self.arrayPathLast = nil
  }

  public var body: some View {
    let registry = destinationRegistry
    let actions = _NavigationActions(
      push: { title, dest in
        let id = nextID
        nextID += 1
        detailTitle = title
        entries.append(_NavigationEntry(id: id, title: title, view: dest))
      },
      pushValue: { typeID, hashable, raw, label in
        if let pathBinding {
          pathBinding.wrappedValue.boxes.append(NavigationPath.Box(hashable))
          // Preserve concrete payload for typed destination resolution.
          let idx = pathBinding.wrappedValue.boxes.count - 1
          pathBinding.wrappedValue.boxes[idx] = NavigationPath.Box(
            _RawBoxPayload(typeID: typeID, hashable: hashable, raw: raw, label: label)
          )
        } else if let arrayPathPush {
          arrayPathPush(raw)
        } else if let view = registry.resolve(typeID: typeID, value: raw) {
          let id = nextID
          nextID += 1
          detailTitle = label
          entries.append(_NavigationEntry(id: id, title: label, view: view))
        }
      },
      pop: {
        if let pathBinding, !pathBinding.wrappedValue.isEmpty {
          pathBinding.wrappedValue.removeLast()
          detailTitle = ""
        } else if let arrayPathPop, (arrayPathCount?() ?? 0) > 0 {
          arrayPathPop()
          detailTitle = ""
        } else if !entries.isEmpty {
          entries.removeLast()
          detailTitle = entries.last?.title ?? ""
        }
      },
      popToRoot: {
        if let pathBinding {
          pathBinding.wrappedValue.removeLast(pathBinding.wrappedValue.count)
        } else if let arrayPathPop, let count = arrayPathCount?(), count > 0 {
          for _ in 0..<count { arrayPathPop() }
        }
        entries.removeAll()
        detailTitle = ""
      }
    )

    let externalDepth: Int = {
      if let pathBinding { return pathBinding.wrappedValue.count }
      if let arrayPathCount { return arrayPathCount() }
      return 0
    }()
    let totalDepth = externalDepth > 0 ? externalDepth : entries.count
    let topExternalBox: NavigationPath.Box? = {
      if let pathBinding { return pathBinding.wrappedValue.boxes.last }
      if let arrayPathLast { return arrayPathLast() }
      return nil
    }()
    let topExternalView: AnyView? = topExternalBox.flatMap { box in
      if let payload = box.raw as? _RawBoxPayload {
        return registry.resolve(typeID: payload.typeID, value: payload.raw)
      }
      return registry.resolve(typeID: box.typeID, value: box.raw)
    }

    let activeTitle = totalDepth == 0
      ? rootTitle
      : (detailTitle.isEmpty ? (entries.last?.title ?? topExternalBox?.label ?? "") : detailTitle)
    let backTitle = totalDepth <= 1
      ? (rootTitle.isEmpty ? "Back" : rootTitle)
      : (entries.count >= 2 ? entries[entries.count - 2].title : "Back")

    let pageKey: String = {
      if let box = topExternalBox {
        return "path-\(totalDepth)-\(box.label)"
      }
      return entries.last.map { String($0.id) } ?? "0"
    }()

    SemanticControlWrapper(
      semantic: SemanticControl(
        kind: "navStack",
        intValue: totalDepth,
        subtitle: pageKey,
        canGoBack: totalDepth > 0
      ),
      content: VStack(spacing: 0) {
        if !activeTitle.isEmpty || totalDepth > 0 {
          SemanticControlWrapper(
            semantic: SemanticControl(
              kind: "navBar",
              title: activeTitle,
              subtitle: backTitle,
              canGoBack: totalDepth > 0
            ),
            content: HStack(spacing: 8) {
              if totalDepth > 0 {
                Button {
                  actions.pop?()
                } label: {
                  HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text(verbatim: backTitle)
                  }
                  .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
              }
              Spacer()
              Text(verbatim: activeTitle)
                .font(.headline)
              Spacer()
              if totalDepth > 0 {
                Color.clear.frame(width: 44, height: 1)
              }
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 56, maxHeight: 56)
            .background(Color { s in s == .dark ? (0.11, 0.11, 0.12, 1) : (0.97, 0.97, 0.98, 1) }),
            backAction: { actions.pop?() }
          )
          #if !(os(Android) || CROSS_SWIFTUI_HARMONY)
          Divider()
          #endif
        }

        Group {
          if let topExternalView {
            topExternalView
              .onPreferenceChange(_NavigationTitlePreferenceKey.self) { title in
                if let title, !title.isEmpty { detailTitle = title }
              }
          } else if let top = entries.last {
            top.view
              .onPreferenceChange(_NavigationTitlePreferenceKey.self) { title in
                if let title, !title.isEmpty { detailTitle = title }
              }
          } else {
            root
              .onPreferenceChange(_NavigationTitlePreferenceKey.self) { title in
                if let title, !title.isEmpty { rootTitle = title }
              }
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\._navigationActions, actions)
        .environment(\._navigationDestinations, registry)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity),
      backAction: { actions.pop?() }
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

private struct _RawBoxPayload: Hashable {
  let typeID: ObjectIdentifier
  let hashable: AnyHashable
  let raw: Any
  let label: String

  static func == (lhs: _RawBoxPayload, rhs: _RawBoxPayload) -> Bool {
    lhs.typeID == rhs.typeID && lhs.hashable == rhs.hashable
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(typeID)
    hasher.combine(hashable)
  }
}

public struct NavigationLink<Label: View, Destination: View>: View {
  let label: Label
  private let destinationBuilder: (() -> AnyView)?
  let fallbackTitle: String
  private let valuePush: (@MainActor (_NavigationActions) -> Void)?
  @Environment(\._navigationActions) private var navActions

  public init(@ViewBuilder destination: () -> Destination, @ViewBuilder label: () -> Label) {
    let dest = destination()
    self.destinationBuilder = { AnyView(dest) }
    self.label = label()
    self.fallbackTitle = ""
    self.valuePush = nil
  }
  public init(_ titleKey: LocalizedStringKey, @ViewBuilder destination: () -> Destination)
  where Label == Text {
    let dest = destination()
    self.destinationBuilder = { AnyView(dest) }
    self.label = Text(titleKey)
    self.fallbackTitle = titleKey.resolved()
    self.valuePush = nil
  }
  @_disfavoredOverload
  public init<S: StringProtocol>(_ title: S, @ViewBuilder destination: () -> Destination)
  where Label == Text {
    let str = String(title)
    let dest = destination()
    self.destinationBuilder = { AnyView(dest) }
    self.label = Text(verbatim: str)
    self.fallbackTitle = str
    self.valuePush = nil
  }

  public init<P: Hashable>(
    value: P?,
    @ViewBuilder label: () -> Label
  ) where Destination == Never {
    self.destinationBuilder = nil
    self.label = label()
    self.fallbackTitle = value.map { String(describing: $0) } ?? ""
    if let value {
      self.valuePush = { actions in
        actions.pushValue?(ObjectIdentifier(P.self), AnyHashable(value), value, String(describing: value))
      }
    } else {
      self.valuePush = nil
    }
  }

  public init<P: Hashable>(
    _ titleKey: LocalizedStringKey,
    value: P?
  ) where Label == Text, Destination == Never {
    self.destinationBuilder = nil
    self.label = Text(titleKey)
    self.fallbackTitle = titleKey.resolved()
    if let value {
      let title = titleKey.resolved()
      self.valuePush = { actions in
        actions.pushValue?(ObjectIdentifier(P.self), AnyHashable(value), value, title)
      }
    } else {
      self.valuePush = nil
    }
  }

  @_disfavoredOverload
  public init<S: StringProtocol, P: Hashable>(
    _ title: S,
    value: P?
  ) where Label == Text, Destination == Never {
    let str = String(title)
    self.destinationBuilder = nil
    self.label = Text(verbatim: str)
    self.fallbackTitle = str
    if let value {
      self.valuePush = { actions in
        actions.pushValue?(ObjectIdentifier(P.self), AnyHashable(value), value, str)
      }
    } else {
      self.valuePush = nil
    }
  }

  public var body: some View {
    Button {
      if let valuePush {
        valuePush(navActions)
      } else if let destinationBuilder {
        navActions.push?(fallbackTitle, destinationBuilder())
      }
    } label: {
      HStack(spacing: 8) {
        label
        Spacer(minLength: 8)
        Image(systemName: "chevron.right")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

public struct ToolbarItemPlacement: Equatable, Sendable {
  public static let automatic = ToolbarItemPlacement()
  public static let principal = ToolbarItemPlacement()
  public static let navigation = ToolbarItemPlacement()
  public static let primaryAction = ToolbarItemPlacement()
  public static let status = ToolbarItemPlacement()
  public static let confirmationAction = ToolbarItemPlacement()
  public static let cancellationAction = ToolbarItemPlacement()
  public static let destructiveAction = ToolbarItemPlacement()
  public static let keyboard = ToolbarItemPlacement()
}

public struct ToolbarRemoving: Equatable, Sendable {
  public static let sidebarToggle = ToolbarRemoving()
}

public struct ToolbarTitleDisplayMode: Equatable, Sendable {
  public static let automatic = ToolbarTitleDisplayMode()
  public static let inline = ToolbarTitleDisplayMode()
  public static let large = ToolbarTitleDisplayMode()
}

public struct ToolbarItem<ID, Content: View>: View {
  let content: Content
  public init(placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content)
  where ID == Void {
    self.content = content()
  }
  public init(id: ID, placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content) {
    self.content = content()
  }
  public var body: some View { content }
}

public struct ToolbarItemGroup<Content: View>: View {
  let content: Content
  public init(placement: ToolbarItemPlacement = .automatic, @ViewBuilder content: () -> Content) {
    self.content = content()
  }
  public var body: some View { HStack(spacing: 6) { content } }
}

public struct SearchFieldPlacement: Equatable, Sendable {
  public static let automatic = SearchFieldPlacement()
  public static let sidebar = SearchFieldPlacement()
  public static let toolbar = SearchFieldPlacement()
}

extension View {
  public func navigationSplitViewStyle(_ style: NavigationSplitViewStyle) -> some View { self }

  public func navigationSplitViewColumnWidth(_ width: CGFloat) -> some View {
    preference(key: SidebarColumnWidthPreferenceKey.self, value: width)
  }

  public func navigationSplitViewColumnWidth(
    min: CGFloat? = nil,
    ideal: CGFloat,
    max: CGFloat? = nil
  ) -> some View {
    preference(key: SidebarColumnWidthPreferenceKey.self, value: ideal)
  }

  public func navigationTitle(_ titleKey: LocalizedStringKey) -> some View {
    preference(key: _NavigationTitlePreferenceKey.self, value: titleKey.resolved())
  }
  @_disfavoredOverload
  public func navigationTitle<S: StringProtocol>(_ title: S) -> some View {
    preference(key: _NavigationTitlePreferenceKey.self, value: String(title))
  }
  public func navigationTitle(_ title: Text) -> some View {
    preference(key: _NavigationTitlePreferenceKey.self, value: title.content)
  }
  public func navigationSubtitle(_ subtitleKey: LocalizedStringKey) -> some View { self }
  @_disfavoredOverload
  public func navigationSubtitle<S: StringProtocol>(_ subtitle: S) -> some View { self }

  public func toolbar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    let _ = content()
    return self
  }

  public func toolbar(removing: ToolbarRemoving?) -> some View { self }
  public func toolbarTitleDisplayMode(_ mode: ToolbarTitleDisplayMode) -> some View { self }
  public func toolbarBackground(_ visibility: Visibility, for bars: Any...) -> some View { self }

  public func searchable(
    text: Binding<String>,
    placement: SearchFieldPlacement = .automatic,
    prompt: LocalizedStringKey
  ) -> some View {
    searchableImpl(text: text, promptText: prompt.resolved())
  }

  @_disfavoredOverload
  public func searchable<S: StringProtocol>(
    text: Binding<String>,
    placement: SearchFieldPlacement = .automatic,
    prompt: S
  ) -> some View {
    searchableImpl(text: text, promptText: String(prompt))
  }

  public func searchable(
    text: Binding<String>,
    isPresented: Binding<Bool>,
    placement: SearchFieldPlacement = .automatic,
    prompt: LocalizedStringKey
  ) -> some View {
    searchableImpl(text: text, promptText: prompt.resolved())
  }

  @_disfavoredOverload
  public func searchable<S: StringProtocol>(
    text: Binding<String>,
    isPresented: Binding<Bool>,
    placement: SearchFieldPlacement = .automatic,
    prompt: S
  ) -> some View {
    searchableImpl(text: text, promptText: String(prompt))
  }

  public func searchable(
    text: Binding<String>,
    placement: SearchFieldPlacement = .automatic
  ) -> some View {
    searchableImpl(text: text, promptText: "Search")
  }

  private func searchableImpl(text: Binding<String>, promptText: String) -> some View {
    VStack(spacing: 0) {
      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(.secondary)
        TextField(promptText, text: text)
          .textFieldStyle(.plain)
          .font(.callout)
        if !text.wrappedValue.isEmpty {
          Button {
            text.wrappedValue = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 12))
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .background(
        Color { s in s == .dark ? (1, 1, 1, 0.07) : (0, 0, 0, 0.05) },
        in: RoundedRectangle(cornerRadius: 7)
      )
      .padding(.horizontal, 10)
      .padding(.top, 10)
      .padding(.bottom, 4)

      self
    }
  }
}

// MARK: - ProgressView, ContentUnavailableView, TextEditor & Link

public struct ProgressViewStyle: Sendable {
  public enum Kind: Sendable { case automatic, linear, circular }
  let kind: Kind
  public static let automatic = ProgressViewStyle(kind: .automatic)
  public static let linear = ProgressViewStyle(kind: .linear)
  public static let circular = ProgressViewStyle(kind: .circular)
}

private enum ProgressViewStyleKey: EnvironmentKey {
  static let defaultValue: ProgressViewStyle = .automatic
}

extension EnvironmentValues {
  fileprivate var progressViewStyle: ProgressViewStyle {
    get { self[ProgressViewStyleKey.self] }
    set { self[ProgressViewStyleKey.self] = newValue }
  }
}

extension View {
  public func progressViewStyle(_ style: ProgressViewStyle) -> some View {
    environment(\.progressViewStyle, style)
  }
}

private struct SpinningProgressIndicator: View {
  let tint: Color
  @State private var spinning = false

  var body: some View {
    ZStack {
      Circle()
        .stroke(Color.primary.opacity(0.14), lineWidth: 2.2)
      Circle()
        .trim(from: 0.0, to: 0.72)
        .stroke(tint, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
        .rotationEffect(.degrees(spinning ? 360 : 0))
        .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spinning)
    }
    .frame(width: 18, height: 18)
    .onAppear {
      spinning = true
    }
  }
}

public struct ProgressView<Label: View, CurrentValueLabel: View>: View {
  let fraction: Double?
  let label: Label
  let currentValueLabel: CurrentValueLabel
  @Environment(\.progressViewStyle) private var style

  public init() where Label == EmptyView, CurrentValueLabel == EmptyView {
    self.fraction = nil
    self.label = EmptyView()
    self.currentValueLabel = EmptyView()
  }

  public init(@ViewBuilder label: () -> Label) where CurrentValueLabel == EmptyView {
    self.fraction = nil
    self.label = label()
    self.currentValueLabel = EmptyView()
  }

  public init(_ titleKey: LocalizedStringKey) where Label == Text, CurrentValueLabel == EmptyView {
    self.fraction = nil
    self.label = Text(titleKey)
    self.currentValueLabel = EmptyView()
  }

  public init<V: BinaryFloatingPoint>(
    value: V?,
    total: V = 1.0
  ) where Label == EmptyView, CurrentValueLabel == EmptyView {
    if let value, total > 0 {
      self.fraction = min(1, max(0, Double(value) / Double(total)))
    } else {
      self.fraction = nil
    }
    self.label = EmptyView()
    self.currentValueLabel = EmptyView()
  }

  public init<V: BinaryFloatingPoint>(
    value: V?,
    total: V = 1.0,
    @ViewBuilder label: () -> Label
  ) where CurrentValueLabel == EmptyView {
    if let value, total > 0 {
      self.fraction = min(1, max(0, Double(value) / Double(total)))
    } else {
      self.fraction = nil
    }
    self.label = label()
    self.currentValueLabel = EmptyView()
  }

  public init<V: BinaryFloatingPoint>(
    value: V?,
    total: V = 1.0,
    @ViewBuilder label: () -> Label,
    @ViewBuilder currentValueLabel: () -> CurrentValueLabel
  ) {
    if let value, total > 0 {
      self.fraction = min(1, max(0, Double(value) / Double(total)))
    } else {
      self.fraction = nil
    }
    self.label = label()
    self.currentValueLabel = currentValueLabel()
  }

  public var body: some View {
    let resolvedTint = EnvironmentValues.current.tint
    if let fraction, style.kind != .circular {
      VStack(alignment: .leading, spacing: 4) {
        if Label.self != EmptyView.self { label }
        SemanticControlWrapper(
          semantic: SemanticControl(
            kind: "progressLinear",
            doubleValue: fraction,
            tint: EnvironmentValues.current.tint,
            isIndeterminate: false
          ),
          content: GeometryReader { geo in
            ZStack(alignment: .leading) {
              Capsule().fill(Color.primary.opacity(0.14)).frame(height: 6)
              Capsule().fill(resolvedTint).frame(width: geo.size.width * CGFloat(fraction), height: 6)
            }
          }
          .frame(height: 6)
        )
        if CurrentValueLabel.self != EmptyView.self { currentValueLabel }
      }
    } else {
      HStack(spacing: 8) {
        SemanticControlWrapper(
          semantic: SemanticControl(
            kind: "progressCircular",
            tint: EnvironmentValues.current.tint,
            isIndeterminate: true
          ),
          content: SpinningProgressIndicator(tint: resolvedTint)
        )
        if Label.self != EmptyView.self { label }
      }
    }
  }
}

public struct ContentUnavailableView<Label: View, Description: View, Actions: View>: View {
  let label: Label
  let description: Description
  let actions: Actions

  public init(
    @ViewBuilder label: () -> Label,
    @ViewBuilder description: () -> Description = { EmptyView() },
    @ViewBuilder actions: () -> Actions = { EmptyView() }
  ) {
    self.label = label()
    self.description = description()
    self.actions = actions()
  }

  public init(
    _ titleKey: LocalizedStringKey,
    systemImage: String,
    description: Text? = nil
  ) where Label == SwiftUIRuntime.Label<Text, Image>, Description == Text?, Actions == EmptyView {
    self.label = SwiftUIRuntime.Label(titleKey, systemImage: systemImage)
    self.description = description
    self.actions = EmptyView()
  }

  @_disfavoredOverload
  public init<S: StringProtocol>(
    _ title: S,
    systemImage: String,
    description: Text? = nil
  ) where Label == SwiftUIRuntime.Label<Text, Image>, Description == Text?, Actions == EmptyView {
    self.label = SwiftUIRuntime.Label(title, systemImage: systemImage)
    self.description = description
    self.actions = EmptyView()
  }

  public var body: some View {
    VStack(spacing: 8) {
      label
        .font(.headline)
        .foregroundStyle(.secondary)
      description
        .font(.subheadline)
        .foregroundStyle(.tertiary)
        .multilineTextAlignment(.center)
      actions
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

extension ContentUnavailableView
where Label == VStack<TupleView>, Description == Text?, Actions == EmptyView {
  public static var search: ContentUnavailableView {
    search(text: "")
  }

  public static func search(text: String) -> ContentUnavailableView {
    let desc: Text? = text.isEmpty ? nil : Text(verbatim: "No results for \"\(text)\"")
    return ContentUnavailableView(
      label: {
        VStack(spacing: 8) {
          Image(systemName: "magnifyingglass")
            .font(.system(size: 28, weight: .regular))
          Text("No Results")
        }
      },
      description: { desc },
      actions: { EmptyView() }
    )
  }
}

public struct TextEditor: View {
  let text: Binding<String>

  public init(text: Binding<String>) {
    self.text = text
  }

  public var body: some View {
    TextField("", text: text, axis: .vertical)
  }
}

public struct Link<Label: View>: View {
  let destination: URL
  let label: Label
  @Environment(\.openURL) private var openURL

  public init(destination: URL, @ViewBuilder label: () -> Label) {
    self.destination = destination
    self.label = label()
  }

  public init(_ titleKey: LocalizedStringKey, destination: URL) where Label == Text {
    self.destination = destination
    self.label = Text(titleKey)
  }

  @_disfavoredOverload
  public init<S: StringProtocol>(_ title: S, destination: URL) where Label == Text {
    self.destination = destination
    self.label = Text(verbatim: String(title))
  }

  public var body: some View {
    Button {
      _ = openURL(destination)
    } label: {
      label.foregroundStyle(.tint)
    }
    .buttonStyle(.plain)
  }
}

// MARK: - LazyHGrid

public struct LazyHGrid<Content: View>: View {
  let rows: [GridItem]
  let spacing: CGFloat
  let content: Content
  public init(
    rows: [GridItem],
    alignment: VerticalAlignment = .center,
    spacing: CGFloat? = nil,
    pinnedViews: PinnedScrollableViews = [],
    @ViewBuilder content: () -> Content
  ) {
    self.rows = rows
    self.spacing = spacing ?? 8
    self.content = content()
  }
  public var body: some View {
    HGridContent(layout: HGridLayout(rows: rows, spacing: spacing), content: content)
  }
}

private struct HGridContent<Content: View>: View, _PrimitiveView {
  typealias Body = Never
  let layout: HGridLayout
  let content: Content
  var body: Never { fatalError("HGrid content is primitive") }

  func _makeElement(path: ViewPath) -> Element {
    let stackKey = AnyHashable(path)
    let savedCtx = EnvironmentValues.current.lazyContainerContext
    let rowEstimate: Int
    if layout.rows.count == 1, case .adaptive(let minH, _) = layout.rows[0].size {
      let vh = EnvironmentValues.current.scrollViewportContext?.viewportHeight ?? 400
      rowEstimate = max(1, Int((vh + Double(layout.spacing)) / (Double(minH) + Double(layout.spacing))))
    } else {
      rowEstimate = max(1, layout.rows.count)
    }
    EnvironmentValues.current.lazyContainerContext = LazyContainerContext(
      key: stackKey, axis: .horizontalGrid(rows: rowEstimate), spacing: Double(layout.spacing))
    defer { EnvironmentValues.current.lazyContainerContext = savedCtx }
    let contentElement = _render(content, path: path)
    let children = flattenChildren(contentElement)
    var props = NodeProps()
    props.isLazyContainer =
      contentElement.props.isLazyContainer
      || children.count > ScrollViewportContext.virtualizationThreshold
    var node = Element(kind: .customLayout, props: props, children: children)
    node.layout = layout
    node.lazyCacheKey = stackKey
    return node
  }
}

private struct HGridLayout: _LayoutBridge {
  var translatesWithBounds: Bool { true }
  let rows: [GridItem]
  let spacing: CGFloat

  func heights(_ proposal: ProposedViewSize) -> [CGFloat] {
    let height = proposal.height ?? 300
    if rows.count == 1, case .adaptive(let minimum, let maximum) = rows[0].size {
      let n = max(1, Int((height + spacing) / (minimum + spacing)))
      return Array(
        repeating: min(maximum, (height - CGFloat(n - 1) * spacing) / CGFloat(n)), count: n)
    }
    let flexible = rows.filter {
      if case .fixed = $0.size { return false }
      return true
    }.count
    let fixed = rows.reduce(CGFloat(0)) { sum, row in
      if case .fixed(let h) = row.size { return sum + h }
      return sum
    }
    let remaining =
      max(0, height - fixed - CGFloat(max(0, rows.count - 1)) * spacing)
      / CGFloat(max(1, flexible))
    return rows.map {
      switch $0.size {
      case .fixed(let h): return h
      case .flexible(let min, let max), .adaptive(let min, let max):
        return Swift.min(max, Swift.max(min, remaining))
      }
    }
  }

  func frames(_ proposal: ProposedViewSize, children: [Element], engine: LayoutEngine) -> [CGRect] {
    let heights = heights(proposal)
    guard !heights.isEmpty else { return [] }
    var frames: [CGRect] = []
    var x: CGFloat = 0
    frames.reserveCapacity(children.count)
    for start in stride(from: 0, to: children.count, by: heights.count) {
      let end = min(start + heights.count, children.count)
      var width: CGFloat = 0
      for i in start..<end {
        let size = engine.sizeThatFits(
          children[i], proposal: ProposedViewSize(width: nil, height: heights[i - start]))
        width = max(width, size.width)
      }
      var y: CGFloat = 0
      for i in start..<end {
        let h = heights[i - start]
        frames.append(CGRect(x: x, y: y, width: width, height: h))
        y += h + spacing
      }
      x += width + spacing
    }
    return frames
  }

  func measure(_ proposal: ProposedViewSize, children: [Element], engine: LayoutEngine) -> CGSize {
    let boxes = frames(proposal, children: children, engine: engine)
    return CGSize(
      width: boxes.map(\.maxX).max() ?? 0,
      height: proposal.height ?? (boxes.map(\.maxY).max() ?? 0))
  }

  func placements(_ bounds: CGRect, children: [Element], engine: LayoutEngine) -> [CGRect] {
    frames(ProposedViewSize(bounds.size), children: children, engine: engine).map {
      $0.offsetBy(dx: bounds.minX, dy: bounds.minY)
    }
  }
}

// MARK: - TabView & tabItem

private struct _TabItemDescriptor {
  let title: String
  let systemImage: String
  let tag: AnyHashable?
  let content: AnyView
}

private struct _TabItemModifierView<Content: View, Label: View>: View, _PrimitiveView {
  typealias Body = Never
  let content: Content
  let label: Label

  var body: Never { fatalError("_TabItemModifierView is primitive") }

  func _makeElement(path: ViewPath) -> Element {
    let labelEl = _render(label, path: path.appending(index: 1))
    func findText(_ el: Element) -> String {
      if el.kind == .text, !el.props.text.isEmpty { return el.props.text }
      for c in el.children {
        let t = findText(c)
        if !t.isEmpty { return t }
      }
      return ""
    }
    func findSymbol(_ el: Element) -> String {
      if el.kind == .image, el.props.imagePath.hasPrefix("sf://") {
        return String(el.props.imagePath.dropFirst(5))
      }
      for c in el.children {
        let s = findSymbol(c)
        if !s.isEmpty { return s }
      }
      return ""
    }
    var el = _render(content, path: path.appending(index: 0))
    el.tabItemTitle = findText(labelEl)
    el.tabItemIcon = findSymbol(labelEl)
    el.tabItemContent = AnyView(content)
    return el
  }
}

extension View {
  public func tabItem<V: View>(@ViewBuilder _ label: () -> V) -> some View {
    _TabItemModifierView(content: self, label: label())
  }
}

@MainActor
private func _extractTabItems<C: View>(from content: C) -> [_TabItemDescriptor] {
  let tree = _render(content, path: ViewPath())
  var results: [_TabItemDescriptor] = []
  func walk(_ el: Element) {
    if let tabContent = el.tabItemContent {
      results.append(
        _TabItemDescriptor(
          title: el.tabItemTitle ?? "",
          systemImage: el.tabItemIcon ?? "",
          tag: el.tagValue ?? el.explicitID,
          content: tabContent
        )
      )
      return
    }
    for c in el.children { walk(c) }
  }
  walk(tree)
  return results
}

public struct TabView<SelectionValue: Hashable, Content: View>: View {
  let selection: Binding<SelectionValue>?
  let content: Content
  @State private var fallbackIndex: Int = 0

  public init(selection: Binding<SelectionValue>?, @ViewBuilder content: () -> Content) {
    self.selection = selection
    self.content = content()
  }

  public init(@ViewBuilder content: () -> Content) where SelectionValue == Int {
    self.selection = nil
    self.content = content()
  }

  public var body: some View {
    let tabs = _extractTabItems(from: content)
    let activeIndex: Int = {
      if let selection {
        let key = AnyHashable(selection.wrappedValue)
        if let idx = tabs.firstIndex(where: { $0.tag == key }) { return idx }
        if let intVal = selection.wrappedValue as? Int, intVal >= 0, intVal < tabs.count {
          return intVal
        }
      }
      return min(max(0, fallbackIndex), max(0, tabs.count - 1))
    }()

    VStack(spacing: 0) {
      Group {
        if !tabs.isEmpty {
          tabs[activeIndex].content
        } else {
          content
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      if !tabs.isEmpty {
        #if !(os(Android) || CROSS_SWIFTUI_HARMONY)
        Divider()
        #endif
        SemanticControlWrapper(
          semantic: SemanticControl(
            kind: "tabBar",
            intValue: activeIndex,
            items: tabs.map(\.title),
            itemIcons: tabs.map(\.systemImage),
            tint: EnvironmentValues.current.tint
          ),
          content: HStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { idx, tab in
              let isSelected = idx == activeIndex
              Button {
                if let selection, let tag = tab.tag?.base as? SelectionValue {
                  selection.wrappedValue = tag
                } else if let selection, let intTag = idx as? SelectionValue {
                  selection.wrappedValue = intTag
                } else {
                  fallbackIndex = idx
                }
              } label: {
                VStack(spacing: 3) {
                  if !tab.systemImage.isEmpty {
                    Image(systemName: tab.systemImage)
                      .font(.system(size: 18))
                  }
                  Text(verbatim: tab.title)
                    .font(.caption)
                }
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 56)
              }
              .buttonStyle(.plain)
            }
          }
          .frame(maxWidth: .infinity, minHeight: 72, maxHeight: 72)
          .background(Color { s in s == .dark ? (0.11, 0.11, 0.12, 1) : (0.97, 0.97, 0.98, 1) }),
          intAction: { idx in
            guard idx >= 0, idx < tabs.count else { return }
            if let selection, let tag = tabs[idx].tag?.base as? SelectionValue {
              selection.wrappedValue = tag
            } else if let selection, let intTag = idx as? SelectionValue {
              selection.wrappedValue = intTag
            } else {
              fallbackIndex = idx
            }
          }
        )
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
