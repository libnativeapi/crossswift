import Foundation

/// Read-only text, with wrapping and explicit newlines on the Windows backend.

/// A native button whose action invalidates mounted state synchronously.

/// Flexible space in the enclosing stack.

/// A view that renders nothing and occupies no space.

/// Flattens fragments and drops empty children.

public struct Text: View {
  public typealias Body = Never

  public enum TruncationMode: Hashable, Sendable { case head, middle, tail }
  public enum Scale: Hashable, Sendable { case `default`, secondary }
  public enum Case: Hashable, Sendable { case uppercase, lowercase }
  public struct DateStyle: Hashable, Sendable {
    let raw: Int
    public static let time = DateStyle(raw: 0)
    public static let date = DateStyle(raw: 1)
    public static let relative = DateStyle(raw: 2)
    public static let offset = DateStyle(raw: 3)
    public static let timer = DateStyle(raw: 4)
  }
  struct Run: Sendable {
    var text: String
    var font: Font?
    var color: Color?
    var tracking: Double = 0
    var link: URL? = nil
  }
  var runs: [Run] = []
  var textTracking: Double = 0
  var textFont: Font?, textColor: Color?
  var localizedKey: LocalizedStringKey?
  public let content: String

  nonisolated public init(verbatim content: String) {
    self.content = content
  }

  @_disfavoredOverload
  nonisolated public init<S: StringProtocol>(_ content: S) {
    self.content = String(content)
  }

  nonisolated public init(_ key: LocalizedStringKey) {
    self.localizedKey = key
    self.content = key.resolved()
  }

  nonisolated public init(
    _ key: LocalizedStringKey,
    tableName: String?,
    bundle: Bundle? = nil,
    comment: StaticString? = nil
  ) {
    self.localizedKey = key
    self.content = key.resolved()
  }

  @_disfavoredOverload
  @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
  nonisolated public init(_ resource: LocalizedStringResource) {
    self.content = String(localized: resource)
  }

  nonisolated public init<F: FormatStyle>(_ input: F.FormatInput, format: F) where F.FormatOutput == String {
    self.content = format.format(input)
  }

  nonisolated public init(_ image: Image) {
    self.content = image.isSystemSymbol ? "" : image.name
  }

  nonisolated public init(_ date: Date, style: Text.DateStyle) {
    switch style {
    case .time:
      self.content = date.formatted(date: .omitted, time: .shortened)
    case .date:
      self.content = date.formatted(date: .abbreviated, time: .omitted)
    default:
      self.content = date.formatted(.relative(presentation: .numeric))
    }
  }

  @_disfavoredOverload
  @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
  public init(_ content: AttributedString) {
    self.content = String(content.characters)
    runs = content.runs.map { run in
      #if !os(macOS)
        let slice = content[run.range]
        let font = slice[AttributeScopes.SwiftUIAttributes.FontAttribute.self]
        let color = slice[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self]
        return Run(text: String(content.characters[run.range]), font: font, color: color, link: run.link)
      #else
        return Run(text: String(content.characters[run.range]), font: nil, color: nil, link: run.link)
      #endif
    }
  }

  public var body: Never { fatalError("Text is a primitive view") }
}
extension Text: _PrimitiveView {
  func _makeElement(path: ViewPath) -> Element {
    var props = NodeProps()
    let resolvedText = localizedKey?.resolved(locale: EnvironmentValues.current.locale) ?? content
    props.text = resolvedText
    props.font = textFont ?? EnvironmentValues.current.font
    props.foreground = textColor
    props.tracking = textTracking
    if !runs.isEmpty {
      let children = runs.map { run -> Element in
        var child = props
        child.text = run.text
        child.font = run.font ?? props.font
        child.foreground = run.color ?? props.foreground
        child.tracking = run.tracking
        guard let url = run.link else { return Element(kind: .text, props: child) }
        let openURL = EnvironmentValues.current.openURL
        child.underline = true
        child.foreground = run.color ?? EnvironmentValues.current.tint
        child.accessibilityTraits = AccessibilityTraits.isLink.rawValue
        return Element(kind: .text, props: child, action: { _ = openURL(url) })
      }
      var container = NodeProps()
      container.spacing = 0
      return Element(kind: .container(.horizontal), props: container, children: children)
    }
    return Element(kind: .text, props: props)
  }
}
public enum ButtonRole { case cancel, destructive }

public struct Button<Label: View>: View {
  public typealias Body = Never

  public let title: String
  public let action: () -> Void
  let label: Label
  let role: ButtonRole?

  public init(_ titleKey: LocalizedStringKey, action: @escaping () -> Void) where Label == Text {
    self.init(titleKey, role: nil, action: action)
  }

  public init(_ titleKey: LocalizedStringKey, role: ButtonRole?, action: @escaping () -> Void)
  where Label == Text {
    let resolved = titleKey.resolved()
    self.title = resolved
    self.role = role
    self.action = action
    self.label = Text(titleKey)
  }

  @_disfavoredOverload
  public init<S: StringProtocol>(_ title: S, action: @escaping () -> Void) where Label == Text {
    self.init(title, role: nil, action: action)
  }

  @_disfavoredOverload
  public init<S: StringProtocol>(_ title: S, role: ButtonRole?, action: @escaping () -> Void)
  where Label == Text {
    let str = String(title)
    self.title = str
    self.role = role
    self.action = action
    self.label = Text(verbatim: str)
  }

  public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
    self.title = ""
    self.role = nil
    self.action = action
    self.label = label()
  }

  public init(role: ButtonRole?, action: @escaping () -> Void, @ViewBuilder label: () -> Label) {
    self.title = ""
    self.role = role
    self.action = action
    self.label = label()
  }

  public var body: Never { fatalError("Button is a primitive view") }
}
extension Button: _PrimitiveView {
  func _makeElement(path: ViewPath) -> Element {
    if let inherited = EnvironmentValues.current.inheritedButtonStyle {
      var el = inherited(AnyView(label), role, path.appending(index: 0), action)
      if role == .cancel && el.props.keyboardShortcut == nil {
        el.props.keyboardShortcut = .cancelAction
      }
      return el
    }
    func hasOnlyText(_ el: Element) -> Bool {
      if el.kind == .image || el.kind == .path || el.kind == .textField || el.kind == .hostedView {
        return false
      }
      return el.children.allSatisfy(hasOnlyText)
    }
    func text(_ element: Element) -> String {
      if element.kind == .text { return element.props.text }
      return element.children.map(text).filter { !$0.isEmpty }.joined(separator: " ")
    }
    let renderedLabel = _render(label, path: path.appending(index: 0))
    let resolvedTitle = title.isEmpty ? text(renderedLabel) : title
    // Native push buttons only render plain text titles. Icon or composite
    // labels (e.g. Image(systemName: "chevron.up")) render through DefaultButtonStyle.
    if !hasOnlyText(renderedLabel) || resolvedTitle.isEmpty {
      var styled = _render(
        StyledButton(button: self, style: DefaultButtonStyle()),
        path: path.appending(index: 1)
      )
      if role == .cancel { styled.props.keyboardShortcut = .cancelAction }
      return styled
    }
    var props = NodeProps()
    if role == .cancel { props.keyboardShortcut = .cancelAction }
    if role == .destructive {
      props.foreground = Color.red._resolvePrimaryColor(in: EnvironmentValues.current)
    }
    props.text = resolvedTitle
    return Element(kind: .button, props: props, action: action)
  }
}
public struct Spacer: View {
  public typealias Body = Never

  public let minLength: Double

  public init(minLength: Double? = nil) {
    self.minLength = minLength ?? 0
  }

  public var body: Never { fatalError("Spacer is a primitive view") }
}
extension Spacer: _PrimitiveView {
  func _makeElement(path: ViewPath) -> Element {
    var props = NodeProps()
    props.flex = 1
    props.spacerMinLength = max(0, minLength)
    return Element(kind: .spacer, props: props)
  }
}
public struct EmptyView: View {
  public typealias Body = Never

  public init() {}

  public var body: Never { fatalError("EmptyView is a primitive view") }
}
extension EmptyView: _PrimitiveView {
  func _makeElement(path: ViewPath) -> Element {
    Element(kind: .empty)
  }
}
func flattenChildren(_ element: Element) -> [Element] {
  if element.kind == .fragment {
    var children: [Element] = []
    children.reserveCapacity(element.children.count)
    func append(
      _ child: Element,
      inheritedTag: AnyHashable?,
      inheritedID: AnyHashable?,
      inheritedLineLimit: Int?,
      inheritedLineSpacing: Double,
      inheritedForeground: Color?,
      inheritedFont: Font?
    ) {
      let tag = child.tagValue ?? inheritedTag
      let eid = child.explicitID ?? inheritedID
      let lineLimit = child.props.lineLimit ?? inheritedLineLimit
      let lineSpacing = child.props.lineSpacing != 0 ? child.props.lineSpacing : inheritedLineSpacing
      let foreground = child.props.foreground ?? inheritedForeground
      let font = child.props.font ?? inheritedFont
      switch child.kind {
      case .fragment:
        let propagateID = child.children.count == 1 ? eid : nil
        for nested in child.children {
          append(
            nested,
            inheritedTag: tag,
            inheritedID: propagateID,
            inheritedLineLimit: lineLimit,
            inheritedLineSpacing: lineSpacing,
            inheritedForeground: foreground,
            inheritedFont: font)
        }
      case .empty: break
      default:
        var resolved = child
        if resolved.tagValue == nil { resolved.tagValue = tag }
        if resolved.explicitID == nil { resolved.explicitID = eid }
        if resolved.props.lineLimit == nil, let lineLimit { resolved.props.lineLimit = lineLimit }
        if resolved.props.lineSpacing == 0, lineSpacing != 0 {
          resolved.props.lineSpacing = lineSpacing
        }
        if resolved.props.foreground == nil, let foreground {
          resolved.props.foreground = foreground
        }
        if resolved.props.font == nil, let font { resolved.props.font = font }
        children.append(resolved)
      }
    }
    let rootPropagateID = element.children.count == 1 ? element.explicitID : nil
    for child in element.children {
      append(
        child,
        inheritedTag: element.tagValue,
        inheritedID: rootPropagateID,
        inheritedLineLimit: element.props.lineLimit,
        inheritedLineSpacing: element.props.lineSpacing,
        inheritedForeground: element.props.foreground,
        inheritedFont: element.props.font)
    }
    return children
  }
  return element.kind == .empty ? [] : [element]
}
extension Text {
  nonisolated public func textScale(_ scale: Text.Scale, isEnabled: Bool = true) -> Text {
    self
  }

  nonisolated public func baselineOffset(_ baselineOffset: CGFloat) -> Text {
    self
  }

  public func kerning(_ spacing: CGFloat) -> Text {
    var text = self
    text.textTracking = Double(spacing)
    for index in text.runs.indices { text.runs[index].tracking = Double(spacing) }
    return text
  }

  public func font(_ font: Font?) -> Text {
    var text = self
    text.textFont = font
    return text
  }
  public func fontWeight(_ weight: Font.Weight?) -> Text {
    font((textFont ?? .body).weight(weight ?? .regular))
  }
  public func foregroundColor(_ color: Color) -> Text {
    var text = self
    text.textColor = color
    return text
  }
  public func foregroundColor(_ color: Color?) -> Text {
    var text = self
    text.textColor = color
    return text
  }
  public static func + (lhs: Text, rhs: Text) -> Text {
    var text = Text(lhs.content + rhs.content)
    text.runs =
      (lhs.runs.isEmpty
        ? [
          Run(
            text: lhs.content, font: lhs.textFont, color: lhs.textColor, tracking: lhs.textTracking)
        ] : lhs.runs)
      + (rhs.runs.isEmpty
        ? [
          Run(
            text: rhs.content, font: rhs.textFont, color: rhs.textColor, tracking: rhs.textTracking)
        ] : rhs.runs)
    return text
  }
}
