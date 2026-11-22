public struct ButtonStyleConfiguration {
  public typealias Label = AnyView
  public let label: Label
  public let isPressed: Bool
}
@MainActor @preconcurrency public protocol ButtonStyle {
  associatedtype Body: View
  typealias Configuration = ButtonStyleConfiguration
  @ViewBuilder func makeBody(configuration: Configuration) -> Body
}
struct StyledButton<Label: View, Style: ButtonStyle>: View, _PrimitiveView {
  typealias Body = Never
  let button: Button<Label>
  let style: Style
  @State private var pressed = false
  init(button: Button<Label>, style: Style) {
    self.button = button
    self.style = style
  }
  var body: Never { fatalError("StyledButton is primitive") }
  func _makeElement(path: ViewPath) -> Element {
    let isEnabled = EnvironmentValues.current.isEnabled
    let config = ButtonStyleConfiguration(
      label: AnyView(button.label), isPressed: isEnabled && pressed)
    let content: Style.Body
    if let graph = EvaluationGraph.active {
      content = graph.trackObservation { style.makeBody(configuration: config) }
    } else {
      content = style.makeBody(configuration: config)
    }
    let rendered = _render(content, path: path.appending(index: 0))
    var element = Element(
      kind: .styledButton, children: [rendered], action: button.action)
    element.pressedAction = { if pressed != $0 { pressed = $0 } }

    let styleName: String?
    if style is BorderedProminentButtonStyle {
      styleName = "borderedProminent"
    } else if style is BorderedButtonStyle {
      styleName = "bordered"
    } else if style is BorderlessButtonStyle {
      styleName = "borderless"
    } else if style is LinkButtonStyle {
      styleName = "link"
    } else if style is DefaultButtonStyle {
      styleName = "automatic"
    } else {
      styleName = nil
    }

    if let styleName {
      func hasOnlyText(_ el: Element) -> Bool {
        if el.kind == .image || el.kind == .path || el.kind == .textField { return false }
        return el.children.allSatisfy(hasOnlyText)
      }
      func extractText(_ el: Element) -> String {
        if el.kind == .text { return el.props.text }
        return el.children.map(extractText).filter { !$0.isEmpty }.joined(separator: " ")
      }
      let labelEl = _render(button.label, path: path.appending(index: 1))
      if hasOnlyText(labelEl) {
        let titleText = button.title.isEmpty ? extractText(labelEl) : button.title
        if !titleText.isEmpty {
          let roleStr: String
          switch button.role {
          case .destructive: roleStr = "destructive"
          case .cancel: roleStr = "cancel"
          case nil: roleStr = ""
          }
          element.props.semanticControl = SemanticControl(
            kind: "button",
            title: titleText,
            subtitle: roleStr,
            styleName: styleName,
            tint: EnvironmentValues.current.tint
          )
        }
      }
    }
    return element
  }
}
extension Button {
  public func buttonStyle<S: ButtonStyle>(_ style: S) -> some View {
    StyledButton(button: self, style: style)
  }
}

public struct AccessoryBarButtonStyle: ButtonStyle {
  public init() {}
  public func makeBody(configuration: Configuration) -> some View { configuration.label }
}

public struct AccessoryBarActionButtonStyle: ButtonStyle {
  public init() {}
  public func makeBody(configuration: Configuration) -> some View { configuration.label }
}

extension ButtonStyle where Self == AccessoryBarButtonStyle {
  public static var accessoryBar: AccessoryBarButtonStyle { AccessoryBarButtonStyle() }
}

extension ButtonStyle where Self == AccessoryBarActionButtonStyle {
  public static var accessoryBarAction: AccessoryBarActionButtonStyle { AccessoryBarActionButtonStyle() }
}
