import Foundation

#if (os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)) && canImport(CoreGraphics)
  import CoreGraphics
#endif

// MARK: - Gradient & Stops

public struct Gradient: Equatable, Sendable {
  public struct Stop: Equatable, Hashable, Sendable {
    public var color: Color
    public var location: CGFloat

    public init(color: Color, location: CGFloat) {
      self.color = color
      self.location = location
    }

    public func hash(into hasher: inout Hasher) {
      let c = color.resolved(in: .dark)
      hasher.combine(c.red)
      hasher.combine(c.green)
      hasher.combine(c.blue)
      hasher.combine(c.opacity)
      hasher.combine(location)
    }
  }

  public var stops: [Stop]

  public init(stops: [Stop]) {
    self.stops = stops
  }

  public init(colors: [Color]) {
    if colors.isEmpty {
      self.stops = []
    } else if colors.count == 1 {
      self.stops = [Stop(color: colors[0], location: 0)]
    } else {
      let last = CGFloat(colors.count - 1)
      self.stops = colors.enumerated().map { idx, color in
        Stop(color: color, location: CGFloat(idx) / last)
      }
    }
  }

  func sampledColors(steps: Int = 17) -> [Color] {
    guard !stops.isEmpty else { return [.clear] }
    let sorted = stops.sorted { $0.location < $1.location }
    if sorted.count == 1 { return [sorted[0].color, sorted[0].color] }

    var isUniform = true
    for (idx, s) in sorted.enumerated() {
      let expected = CGFloat(idx) / CGFloat(sorted.count - 1)
      if abs(s.location - expected) > 0.005 {
        isUniform = false
        break
      }
    }
    if isUniform {
      return sorted.map(\.color)
    }

    let count = max(2, steps)
    return (0..<count).map { step in
      let t = Double(step) / Double(count - 1)
      if t <= Double(sorted.first!.location) { return sorted.first!.color }
      if t >= Double(sorted.last!.location) { return sorted.last!.color }
      for i in 0..<(sorted.count - 1) {
        let a = sorted[i]
        let b = sorted[i + 1]
        let locA = Double(a.location)
        let locB = Double(b.location)
        if t >= locA && t <= locB {
          let span = locB - locA
          guard span > 1e-6 else { return b.color }
          let frac = (t - locA) / span
          return Color { scheme in
            let ca = a.color.resolved(in: scheme)
            let cb = b.color.resolved(in: scheme)
            return (
              ca.red + (cb.red - ca.red) * frac,
              ca.green + (cb.green - ca.green) * frac,
              ca.blue + (cb.blue - ca.blue) * frac,
              ca.opacity + (cb.opacity - ca.opacity) * frac
            )
          }
        }
      }
      return sorted.last!.color
    }
  }
}

extension LinearGradient {
  nonisolated public init(gradient: Gradient, startPoint: UnitPoint, endPoint: UnitPoint) {
    self.init(colors: gradient.sampledColors(), startPoint: startPoint, endPoint: endPoint)
  }

  nonisolated public init(stops: [Gradient.Stop], startPoint: UnitPoint, endPoint: UnitPoint) {
    self.init(gradient: Gradient(stops: stops), startPoint: startPoint, endPoint: endPoint)
  }
}

public struct RadialGradient: View, ShapeStyle, Sendable {
  public let gradient: Gradient
  public let center: UnitPoint
  public let startRadius: CGFloat
  public let endRadius: CGFloat

  nonisolated public init(gradient: Gradient, center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) {
    self.gradient = gradient
    self.center = center
    self.startRadius = startRadius
    self.endRadius = endRadius
  }

  nonisolated public init(colors: [Color], center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) {
    self.init(gradient: Gradient(colors: colors), center: center, startRadius: startRadius, endRadius: endRadius)
  }

  nonisolated public init(stops: [Gradient.Stop], center: UnitPoint, startRadius: CGFloat, endRadius: CGFloat) {
    self.init(gradient: Gradient(stops: stops), center: center, startRadius: startRadius, endRadius: endRadius)
  }

  public var body: some View {
    LinearGradient(gradient: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
  }

  public func _resolvePrimaryColor(in env: EnvironmentValues) -> Color {
    gradient.stops.first?.color ?? .clear
  }

  public func _resolveGradientData() -> LinearGradient.Data? {
    LinearGradient.Data(colors: gradient.sampledColors(), start: .topLeading, end: .bottomTrailing)
  }
}

public struct AngularGradient: View, ShapeStyle, Sendable {
  public let gradient: Gradient
  public let center: UnitPoint

  nonisolated public init(gradient: Gradient, center: UnitPoint, startAngle: Angle = .zero, endAngle: Angle = .degrees(360)) {
    self.gradient = gradient
    self.center = center
  }

  nonisolated public init(colors: [Color], center: UnitPoint, startAngle: Angle = .zero, endAngle: Angle = .degrees(360)) {
    self.init(gradient: Gradient(colors: colors), center: center, startAngle: startAngle, endAngle: endAngle)
  }

  public var body: some View {
    LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing)
  }

  public func _resolvePrimaryColor(in env: EnvironmentValues) -> Color {
    gradient.stops.first?.color ?? .clear
  }

  public func _resolveGradientData() -> LinearGradient.Data? {
    LinearGradient.Data(colors: gradient.sampledColors(), start: .leading, end: .trailing)
  }
}

// MARK: - AnyShape & FillStyle

public struct FillStyle: Equatable, Sendable {
  public var isEOFilled: Bool
  public var isAntialiased: Bool
  public init(eoFill: Bool = false, antialiased: Bool = true) {
    self.isEOFilled = eoFill
    self.isAntialiased = antialiased
  }
}

public struct AnyShape: Shape {
  private let _cornerRadius: CGFloat
  private let _path: @Sendable (CGRect) -> Path

  nonisolated public init<S: Shape>(_ shape: S) {
    self._cornerRadius = shape.cornerRadius
    self._path = { shape.path(in: $0) }
  }

  nonisolated public var cornerRadius: CGFloat { _cornerRadius }
  nonisolated public func path(in rect: CGRect) -> Path { _path(rect) }
}

public struct Ellipse: Shape {
  nonisolated public init() {}
  nonisolated public var cornerRadius: CGFloat { .infinity }
  nonisolated public func path(in rect: CGRect) -> Path {
    Circle().path(in: rect)
  }
}

// MARK: - ShapeStyle Hierarchy

public protocol ShapeStyle {
  func _resolvePrimaryColor(in env: EnvironmentValues) -> Color
  func _resolveGradientData() -> LinearGradient.Data?
}

extension ShapeStyle {
  public func _resolveGradientData() -> LinearGradient.Data? { nil }

  public func opacity(_ opacity: Double) -> AnyShapeStyle {
    AnyShapeStyle(
      colorResolver: { env in self._resolvePrimaryColor(in: env).opacity(opacity) },
      gradientResolver: {
        guard let g = self._resolveGradientData() else { return nil }
        return LinearGradient.Data(colors: g.colors.map { $0.opacity(opacity) }, start: g.start, end: g.end)
      }
    )
  }
}

public struct AnyShapeStyle: ShapeStyle {
  let colorResolver: (EnvironmentValues) -> Color
  let gradientResolver: () -> LinearGradient.Data?

  public init<S: ShapeStyle>(_ style: S) {
    self.colorResolver = { style._resolvePrimaryColor(in: $0) }
    self.gradientResolver = { style._resolveGradientData() }
  }

  init(
    colorResolver: @escaping (EnvironmentValues) -> Color,
    gradientResolver: @escaping () -> LinearGradient.Data? = { nil }
  ) {
    self.colorResolver = colorResolver
    self.gradientResolver = gradientResolver
  }

  public func _resolvePrimaryColor(in env: EnvironmentValues) -> Color {
    colorResolver(env)
  }

  public func _resolveGradientData() -> LinearGradient.Data? {
    gradientResolver()
  }
}

extension Color: ShapeStyle {
  public func _resolvePrimaryColor(in env: EnvironmentValues) -> Color { self }
}

extension LinearGradient: ShapeStyle {
  public func _resolvePrimaryColor(in env: EnvironmentValues) -> Color {
    data.colors.first ?? .clear
  }
  public func _resolveGradientData() -> LinearGradient.Data? { data }
}

public struct HierarchicalShapeStyle: ShapeStyle, Hashable, Sendable {
  public enum Level: Int, Hashable, Sendable {
    case primary = 0
    case secondary = 1
    case tertiary = 2
    case quaternary = 3
    case quinary = 4
  }

  public let level: Level
  public init(level: Level) { self.level = level }

  public static let primary = HierarchicalShapeStyle(level: .primary)
  public static let secondary = HierarchicalShapeStyle(level: .secondary)
  public static let tertiary = HierarchicalShapeStyle(level: .tertiary)
  public static let quaternary = HierarchicalShapeStyle(level: .quaternary)
  public static let quinary = HierarchicalShapeStyle(level: .quinary)

  public func _resolvePrimaryColor(in env: EnvironmentValues) -> Color {
    let base = env.foregroundColor ?? Color.primary
    switch level {
    case .primary: return base
    case .secondary: return base.opacity(0.60)
    case .tertiary: return base.opacity(0.38)
    case .quaternary: return base.opacity(0.22)
    case .quinary: return base.opacity(0.12)
    }
  }
}

public struct ForegroundStyle: ShapeStyle, Sendable {
  public init() {}
  public func _resolvePrimaryColor(in env: EnvironmentValues) -> Color {
    env.foregroundColor ?? .primary
  }
}

public struct BackgroundStyle: ShapeStyle, Sendable {
  public init() {}
  public func _resolvePrimaryColor(in env: EnvironmentValues) -> Color {
    Color { scheme in
      scheme == .dark ? (0.14, 0.14, 0.16, 1.0) : (0.97, 0.97, 0.98, 1.0)
    }
  }
}

public struct TintShapeStyle: ShapeStyle, Sendable {
  public init() {}
  public func _resolvePrimaryColor(in env: EnvironmentValues) -> Color {
    env.tint
  }
}

public struct SeparatorShapeStyle: ShapeStyle, Sendable {
  public init() {}
  public func _resolvePrimaryColor(in env: EnvironmentValues) -> Color {
    Color { scheme in
      scheme == .dark ? (1.0, 1.0, 1.0, 0.10) : (0.0, 0.0, 0.0, 0.12)
    }
  }
}

public struct Material: ShapeStyle, View, Sendable {
  public enum Kind: Sendable {
    case ultraThin, thin, regular, thick, ultraThick, bar
  }
  let kind: Kind
  public static let ultraThinMaterial = Material(kind: .ultraThin)
  public static let thinMaterial = Material(kind: .thin)
  public static let regularMaterial = Material(kind: .regular)
  public static let thickMaterial = Material(kind: .thick)
  public static let ultraThickMaterial = Material(kind: .ultraThick)
  public static let bar = Material(kind: .bar)

  public func _resolvePrimaryColor(in env: EnvironmentValues) -> Color {
    let alpha: Double = kind == .ultraThin ? 0.55 : (kind == .thin ? 0.70 : 0.84)
    return Color { scheme in
      scheme == .dark ? (0.14, 0.14, 0.16, alpha) : (0.95, 0.95, 0.97, alpha)
    }
  }

  public var body: some View {
    Rectangle().fill(self)
  }
}

extension ShapeStyle where Self == HierarchicalShapeStyle {
  public static var primary: HierarchicalShapeStyle { .primary }
  public static var secondary: HierarchicalShapeStyle { .secondary }
  public static var tertiary: HierarchicalShapeStyle { .tertiary }
  public static var quaternary: HierarchicalShapeStyle { .quaternary }
  public static var quinary: HierarchicalShapeStyle { .quinary }
}

extension ShapeStyle where Self == ForegroundStyle {
  public static var foreground: ForegroundStyle { ForegroundStyle() }
}

extension ShapeStyle where Self == BackgroundStyle {
  public static var background: BackgroundStyle { BackgroundStyle() }
}

extension ShapeStyle where Self == TintShapeStyle {
  public static var tint: TintShapeStyle { TintShapeStyle() }
}

extension ShapeStyle where Self == SeparatorShapeStyle {
  public static var separator: SeparatorShapeStyle { SeparatorShapeStyle() }
}

extension ShapeStyle where Self == Material {
  public static var ultraThinMaterial: Material { .ultraThinMaterial }
  public static var thinMaterial: Material { .thinMaterial }
  public static var regularMaterial: Material { .regularMaterial }
  public static var thickMaterial: Material { .thickMaterial }
  public static var ultraThickMaterial: Material { .ultraThickMaterial }
  public static var bar: Material { .bar }
}

extension ShapeStyle where Self == Color {
  public static var clear: Color { .clear }
  public static var black: Color { .black }
  public static var white: Color { .white }
  public static var gray: Color { .gray }
  public static var red: Color { .red }
  public static var green: Color { .green }
  public static var blue: Color { .blue }
  public static var orange: Color { .orange }
  public static var yellow: Color { .yellow }
  public static var pink: Color { .pink }
  public static var purple: Color { .purple }
  public static var cyan: Color { .cyan }
  public static var mint: Color { .mint }
  public static var teal: Color { .teal }
  public static var indigo: Color { .indigo }
  public static var brown: Color { .brown }
  public static var accentColor: Color { .accentColor }
}

// MARK: - Shape & View ShapeStyle Operations

private struct StyledShapeView<S: Shape, Style: ShapeStyle>: View, _PrimitiveView {
  typealias Body = Never
  let shape: S
  let style: Style
  let isStroke: Bool
  let lineWidth: CGFloat
  let inset: Bool
  let dash: [Double]

  var body: Never { fatalError("StyledShapeView is primitive") }

  func _makeElement(path: ViewPath) -> Element {
    let env = EnvironmentValues.current
    if !isStroke, let grad = style._resolveGradientData() {
      var gp = NodeProps()
      gp.gradient = grad
      gp.fillWidth = true
      gp.fillHeight = true
      gp.cornerRadius = Double(shape.cornerRadius)
      gp.clipped = true
      var el = Element(kind: .gradient, props: gp)
      el.clipPathBuilder = { shape.path(in: $0) }
      return el
    }
    let resolved = style._resolvePrimaryColor(in: env)
    var p = NodeProps()
    p.fillWidth = true
    p.fillHeight = true
    p.background = isStroke ? .clear : resolved
    p.cornerRadius = Double(shape.cornerRadius)
    p.borderColor = isStroke ? resolved : .clear
    p.borderWidth = isStroke ? Double(lineWidth) : 0
    p.dash = dash
    var e = Element(kind: .shape, props: p)
    e.pathBuilder = { r in shape.path(in: inset ? r.insetBy(dx: lineWidth / 2, dy: lineWidth / 2) : r) }
    return e
  }
}

extension Shape {
  public func fill<S: ShapeStyle>(_ content: S, style: FillStyle = FillStyle()) -> some View {
    StyledShapeView(shape: self, style: content, isStroke: false, lineWidth: 0, inset: false, dash: [])
  }

  public func stroke<S: ShapeStyle>(_ content: S, lineWidth: CGFloat = 1) -> some View {
    StyledShapeView(shape: self, style: content, isStroke: true, lineWidth: lineWidth, inset: false, dash: [])
  }

  public func stroke(lineWidth: CGFloat = 1) -> some View {
    StyledShapeView(shape: self, style: ForegroundStyle(), isStroke: true, lineWidth: lineWidth, inset: false, dash: [])
  }

  public func stroke(style: StrokeStyle) -> some View {
    StyledShapeView(
      shape: self, style: ForegroundStyle(), isStroke: true, lineWidth: style.lineWidth, inset: false,
      dash: style.dash.map { Double($0) }
    )
  }

  public func strokeBorder(lineWidth: CGFloat = 1, antialiased: Bool = true) -> some View {
    StyledShapeView(shape: self, style: ForegroundStyle(), isStroke: true, lineWidth: lineWidth, inset: true, dash: [])
  }

  public func stroke<S: ShapeStyle>(_ content: S, style: StrokeStyle) -> some View {
    StyledShapeView(
      shape: self, style: content, isStroke: true, lineWidth: style.lineWidth, inset: false,
      dash: style.dash.map { Double($0) }
    )
  }

  public func strokeBorder<S: ShapeStyle>(_ content: S, lineWidth: CGFloat = 1, antialiased: Bool = true) -> some View {
    StyledShapeView(shape: self, style: content, isStroke: true, lineWidth: lineWidth, inset: true, dash: [])
  }

  public func strokeBorder<S: ShapeStyle>(_ content: S, style: StrokeStyle, antialiased: Bool = true) -> some View {
    StyledShapeView(
      shape: self, style: content, isStroke: true, lineWidth: style.lineWidth, inset: true,
      dash: style.dash.map { Double($0) }
    )
  }
}

private struct ForegroundStyleView<Content: View, Style: ShapeStyle>: View, _PrimitiveView {
  typealias Body = Never
  let content: Content
  let style: Style

  var body: Never { fatalError("ForegroundStyleView is primitive") }

  func _makeElement(path: ViewPath) -> Element {
    let saved = EnvironmentValues.current
    let color = style._resolvePrimaryColor(in: saved)
    EnvironmentValues.current.foregroundColor = color
    var el = _render(content, path: path)
    EnvironmentValues.current = saved
    if el.props.foreground == nil {
      el.props.foreground = color
    }
    return el
  }
}

extension View {
  public func foregroundStyle<S: ShapeStyle>(_ style: S) -> some View {
    ForegroundStyleView(content: self, style: style)
  }

  public func foregroundStyle<S1: ShapeStyle, S2: ShapeStyle>(_ primary: S1, _ secondary: S2) -> some View {
    ForegroundStyleView(content: self, style: primary)
  }

  public func foregroundStyle<S1: ShapeStyle, S2: ShapeStyle, S3: ShapeStyle>(
    _ primary: S1, _ secondary: S2, _ tertiary: S3
  ) -> some View {
    ForegroundStyleView(content: self, style: primary)
  }

  public func background<S: ShapeStyle, Sh: Shape>(
    _ style: S, in shape: Sh, fillStyle: FillStyle = FillStyle()
  ) -> some View {
    background { shape.fill(style, style: fillStyle) }
  }

  @_disfavoredOverload
  public func background<S: ShapeStyle>(_ style: S) -> some View {
    background { Rectangle().fill(style) }
  }
}

extension Text {
  public func foregroundStyle<S: ShapeStyle>(_ style: S) -> Text {
    foregroundColor(style._resolvePrimaryColor(in: EnvironmentValues.current))
  }
}

// MARK: - Semantic Typography & Font Modifiers

extension Font {
  public enum TextStyle: Hashable, CaseIterable, Sendable {
    case largeTitle
    case title
    case title2
    case title3
    case headline
    case subheadline
    case body
    case callout
    case footnote
    case caption
    case caption2

    var defaultMetrics: (size: CGFloat, weight: Weight) {
      switch self {
      case .largeTitle: return (26, .regular)
      case .title: return (22, .regular)
      case .title2: return (17, .regular)
      case .title3: return (15, .regular)
      case .headline: return (13, .semibold)
      case .subheadline: return (11, .regular)
      case .body: return (13, .regular)
      case .callout: return (12, .regular)
      case .footnote: return (10, .regular)
      case .caption: return (10, .regular)
      case .caption2: return (10, .medium)
      }
    }
  }

  public enum Leading: Hashable, Sendable {
    case standard, tight, loose
  }

  public struct Width: Hashable, Sendable {
    public let value: CGFloat
    public init(_ value: CGFloat) { self.value = value }
    public static let compressed = Width(-0.2)
    public static let condensed = Width(-0.1)
    public static let standard = Width(0)
    public static let expanded = Width(0.1)
  }

  public static let largeTitle = Font.system(.largeTitle)
  public static let title = Font.system(.title)
  public static let title2 = Font.system(.title2)
  public static let title3 = Font.system(.title3)
  public static let headline = Font.system(.headline)
  public static let subheadline = Font.system(.subheadline)
  public static let callout = Font.system(.callout)
  public static let footnote = Font.system(.footnote)
  public static let caption = Font.system(.caption)
  public static let caption2 = Font.system(.caption2)

  public static func system(
    _ style: TextStyle,
    design: Design? = nil,
    weight: Weight? = nil
  ) -> Font {
    let m = style.defaultMetrics
    return Font.system(size: m.size, weight: weight ?? m.weight, design: design ?? .default)
  }

  public func monospaced() -> Font {
    var copy = self
    copy.family = "Consolas"
    return copy
  }

  public func monospacedDigit() -> Font {
    var copy = self
    copy.family = "Consolas"
    return copy
  }

  public func bold(_ isActive: Bool = true) -> Font {
    isActive ? weight(.bold) : weight(.regular)
  }

  public func italic(_ isActive: Bool = true) -> Font {
    self
  }

  public func leading(_ leading: Leading) -> Font {
    self
  }

  public func width(_ width: Width) -> Font {
    self
  }
}

extension Text {
  public func bold(_ isActive: Bool = true) -> Text {
    font((textFont ?? .body).bold(isActive))
  }

  public func italic(_ isActive: Bool = true) -> Text {
    self
  }

  public func monospaced(_ isActive: Bool = true) -> Text {
    isActive ? font((textFont ?? .body).monospaced()) : self
  }

  public func monospacedDigit() -> Text {
    font((textFont ?? .body).monospacedDigit())
  }

  public func fontDesign(_ design: Font.Design?) -> Text {
    guard let design else { return self }
    var f = textFont ?? .body
    f.family = design == .monospaced ? "Consolas" : (design == .serif ? "Georgia" : "Segoe UI")
    return font(f)
  }
}

extension View {
  public func fontDesign(_ design: Font.Design?) -> some View {
    FontTransform(content: self) { font in
      guard let design else { return font }
      var copy = font
      copy.family = design == .monospaced ? "Consolas" : (design == .serif ? "Georgia" : "Segoe UI")
      return copy
    }
  }

  public func monospaced(_ isActive: Bool = true) -> some View {
    FontTransform(content: self) { isActive ? $0.monospaced() : $0 }
  }

  public func bold(_ isActive: Bool = true) -> some View {
    FontTransform(content: self) { $0.bold(isActive) }
  }

  public func italic(_ isActive: Bool = true) -> some View {
    self
  }
}

// MARK: - Spring Animations & Transactions

extension Animation {
  public static func spring(
    response: Double = 0.5,
    dampingFraction: Double = 0.825,
    blendDuration: Double = 0
  ) -> Animation {
    let dur = max(0.08, response)
    let y2 = dampingFraction < 0.8 ? 1.06 : 1.0
    return Animation(duration: dur, x1: 0.2, y1: 0.8, x2: 0.25, y2: y2)
  }

  public static func spring(
    duration: Double = 0.5,
    bounce: Double = 0.0,
    blendDuration: Double = 0
  ) -> Animation {
    let y2 = bounce > 0.1 ? 1.0 + min(0.25, bounce * 0.4) : 1.0
    return Animation(duration: max(0.08, duration), x1: 0.2, y1: 0.85, x2: 0.25, y2: y2)
  }

  public static var spring: Animation { .spring(response: 0.5, dampingFraction: 0.825) }
  public static var interactiveSpring: Animation { .spring(response: 0.15, dampingFraction: 0.86) }
  public static func interactiveSpring(
    response: Double = 0.15,
    dampingFraction: Double = 0.86,
    blendDuration: Double = 0.25
  ) -> Animation {
    .spring(response: response, dampingFraction: dampingFraction, blendDuration: blendDuration)
  }

  public static var smooth: Animation { .spring(duration: 0.35, bounce: 0) }
  public static func smooth(duration: Double = 0.35, extraBounce: Double = 0) -> Animation {
    .spring(duration: duration, bounce: extraBounce)
  }

  public static var snappy: Animation { .spring(duration: 0.25, bounce: 0.05) }
  public static func snappy(duration: Double = 0.25, extraBounce: Double = 0) -> Animation {
    .spring(duration: duration, bounce: 0.05 + extraBounce)
  }

  public static var bouncy: Animation { .spring(duration: 0.45, bounce: 0.25) }
  public static func bouncy(duration: Double = 0.45, extraBounce: Double = 0) -> Animation {
    .spring(duration: duration, bounce: 0.25 + extraBounce)
  }

  public func speed(_ speed: Double) -> Animation {
    guard speed > 0 else { return self }
    return Animation(
      duration: duration / speed,
      x1: x1, y1: y1, x2: x2, y2: y2,
      repeats: repeats, autoreverses: autoreverses, delay: delay
    )
  }

  public func repeatCount(_ repeatCount: Int, autoreverses: Bool = true) -> Animation {
    var copy = self
    copy.autoreverses = autoreverses
    return copy
  }
}

public func withTransaction<Result>(_ transaction: Transaction, _ body: () throws -> Result) rethrows -> Result {
  if transaction.disablesAnimations {
    let oldDisabled = AnimationContext.disablesAnimations
    AnimationContext.disablesAnimations = true
    defer { AnimationContext.disablesAnimations = oldDisabled }
    return try withAnimation(nil) { try body() }
  }
  return try withAnimation(transaction.animation) { try body() }
}

public func withTransaction<V, Result>(
  _ keyPath: WritableKeyPath<Transaction, V>, _ value: V, _ body: () throws -> Result
) rethrows -> Result {
  var tx = Transaction(animation: AnimationContext.current)
  tx[keyPath: keyPath] = value
  return try withTransaction(tx, body)
}

public struct EquatableView<Content: Equatable & View>: View, Equatable {
  public var content: Content
  public init(content: Content) { self.content = content }
  public var body: Content { content }
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.content == rhs.content
  }
}

extension View where Self: Equatable {
  public func equatable() -> EquatableView<Self> {
    EquatableView(content: self)
  }
}

public struct ScrollAnchorRole: Equatable, Hashable, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  public static let initialOffset = ScrollAnchorRole(rawValue: 1)
  public static let sizeChanges = ScrollAnchorRole(rawValue: 2)
  public static let alignment = ScrollAnchorRole(rawValue: 3)
}

extension View {
  public func defaultScrollAnchor(_ anchor: UnitPoint?) -> some View { self }
  public func defaultScrollAnchor(_ anchor: UnitPoint?, for role: ScrollAnchorRole) -> some View { self }

  public func animation<V: View>(
    _ animation: Animation?,
    @ViewBuilder body: (Self) -> V
  ) -> some View {
    body(self)
  }

  public func animation(_ animation: Animation?) -> some View {
    self
  }
}

#if !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS))
  public struct _SwiftUILineStyle: Equatable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let single = _SwiftUILineStyle(rawValue: 1)
  }

  extension AttributeScopes {
    public struct SwiftUIAttributes: AttributeScope {
      public let foregroundColor: ForegroundColorAttribute
      public let backgroundColor: BackgroundColorAttribute
      public let font: FontAttribute
      public let strikethroughStyle: StrikethroughStyleAttribute
      public let underlineStyle: UnderlineStyleAttribute
      public let foundation: FoundationAttributes

      public enum ForegroundColorAttribute: AttributedStringKey {
        public typealias Value = Color
        public static let name = "SwiftUI.ForegroundColor"
      }

      public enum BackgroundColorAttribute: AttributedStringKey {
        public typealias Value = Color
        public static let name = "SwiftUI.BackgroundColor"
      }

      public enum FontAttribute: AttributedStringKey {
        public typealias Value = Font
        public static let name = "SwiftUI.Font"
      }

      public enum StrikethroughStyleAttribute: AttributedStringKey {
        public typealias Value = _SwiftUILineStyle
        public static let name = "SwiftUI.StrikethroughStyle"
      }

      public enum UnderlineStyleAttribute: AttributedStringKey {
        public typealias Value = _SwiftUILineStyle
        public static let name = "SwiftUI.UnderlineStyle"
      }
    }

    public var swiftUI: SwiftUIAttributes.Type { SwiftUIAttributes.self }
  }

  extension AttributeDynamicLookup {
    public subscript<T: AttributedStringKey>(
      dynamicMember keyPath: KeyPath<AttributeScopes.SwiftUIAttributes, T>
    ) -> T {
      self[T.self]
    }
  }
#endif
