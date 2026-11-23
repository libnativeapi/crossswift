import Foundation
#if (os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)) && canImport(CoreGraphics)
  import CoreGraphics
#endif

public struct ViewDimensions {
  public let width: CGFloat, height: CGFloat
  public subscript(_ alignment: HorizontalAlignment) -> CGFloat {
    alignment == .leading ? 0 : alignment == .trailing ? width : width / 2
  }
  public subscript(_ alignment: VerticalAlignment) -> CGFloat {
    alignment == .top ? 0 : alignment == .bottom ? height : height / 2
  }
}
public enum LayoutDirection { case leftToRight, rightToLeft }
public enum ContentMode { case fit, fill }
public struct AnyTransition: Equatable, Sendable {
  public struct Phase: Equatable, Sendable {
    public var opacity: Double = 1
    public var scale: Double = 1
    public var offsetX: Double = 0
    public var offsetY: Double = 0
    public var edge: Edge? = nil

    public init(
      opacity: Double = 1,
      scale: Double = 1,
      offsetX: Double = 0,
      offsetY: Double = 0,
      edge: Edge? = nil
    ) {
      self.opacity = opacity
      self.scale = scale
      self.offsetX = offsetX
      self.offsetY = offsetY
      self.edge = edge
    }

    public var isIdentity: Bool {
      opacity == 1 && scale == 1 && offsetX == 0 && offsetY == 0 && edge == nil
    }

    func combined(with other: Phase) -> Phase {
      Phase(
        opacity: opacity * other.opacity,
        scale: scale * other.scale,
        offsetX: offsetX + other.offsetX,
        offsetY: offsetY + other.offsetY,
        edge: other.edge ?? edge
      )
    }
  }

  public var insertion: Phase
  public var removal: Phase
  public var animationOverride: Animation? = nil

  public var opacity: Double { insertion.opacity }
  public var scale: Double { insertion.scale }

  public init(
    opacity: Double = 1,
    scale: Double = 1,
    offsetX: Double = 0,
    offsetY: Double = 0,
    edge: Edge? = nil
  ) {
    let phase = Phase(opacity: opacity, scale: scale, offsetX: offsetX, offsetY: offsetY, edge: edge)
    self.insertion = phase
    self.removal = phase
  }

  public init(insertion: Phase, removal: Phase, animationOverride: Animation? = nil) {
    self.insertion = insertion
    self.removal = removal
    self.animationOverride = animationOverride
  }

  public static let opacity = AnyTransition(opacity: 0)
  public static let identity = AnyTransition()
  public static let slide = AnyTransition(
    insertion: Phase(edge: .leading),
    removal: Phase(edge: .trailing)
  )
  public static func scale(scale: Double = 0, anchor: UnitPoint = .center) -> Self {
    Self(scale: scale)
  }
  public static func move(edge: Edge) -> Self {
    Self(edge: edge)
  }
  public static func push(from edge: Edge) -> Self {
    let opposite: Edge
    switch edge {
    case .top: opposite = .bottom
    case .bottom: opposite = .top
    case .leading: opposite = .trailing
    case .trailing: opposite = .leading
    }
    return Self(insertion: Phase(edge: edge), removal: Phase(edge: opposite))
  }
  public static func offset(x: CGFloat = 0, y: CGFloat = 0) -> Self {
    Self(offsetX: Double(x), offsetY: Double(y))
  }
  public static func offset(_ offset: CGSize) -> Self {
    Self(offsetX: Double(offset.width), offsetY: Double(offset.height))
  }
  public static func asymmetric(insertion: Self, removal: Self) -> Self {
    Self(
      insertion: insertion.insertion,
      removal: removal.removal,
      animationOverride: insertion.animationOverride ?? removal.animationOverride
    )
  }
  public func combined(with other: Self) -> Self {
    Self(
      insertion: insertion.combined(with: other.insertion),
      removal: removal.combined(with: other.removal),
      animationOverride: other.animationOverride ?? animationOverride
    )
  }
  public func animation(_ animation: Animation?) -> Self {
    var copy = self
    copy.animationOverride = animation
    return copy
  }
}
extension Font {
  public func weight(_ value: Weight) -> Font {
    var font = self
    font.weight = value
    return font
  }
}
struct FontTransform<Content: View>: View, _PrimitiveView {
  typealias Body = Never
  let content: Content
  let transform: (Font) -> Font
  var body: Never { fatalError() }
  func _makeElement(path: ViewPath) -> Element {
    let old = EnvironmentValues.current
    EnvironmentValues.current.font = transform(old.font ?? .body)
    defer { EnvironmentValues.current = old }
    return _render(content, path: path)
  }
}
extension View {
  public func background<V: View>(_ background: V, alignment: Alignment = .center) -> some View {
    LayerView(content: self, layer: background, behind: true, alignment: alignment)
  }
  public func background<V: View>(alignment: Alignment, @ViewBuilder content: () -> V) -> some View
  { background(content(), alignment: alignment) }
  public func offset(x: CGFloat = 0, y: CGFloat = 0) -> some View {
    TransformView(content: self) {
      $0.props.offsetX += x
      $0.props.offsetY += y
    }
  }
  public func offset(_ offset: CGSize) -> some View {
    self.offset(x: offset.width, y: offset.height)
  }
  public func scaleEffect(_ scale: CGFloat, anchor: UnitPoint = .center) -> some View {
    TransformView(content: self) {
      $0.props.scaleX *= scale
      $0.props.scaleY *= scale
    }
  }
  public func rotationEffect(_ angle: Angle, anchor: UnitPoint = .center) -> some View {
    TransformView(content: self) { $0.props.rotation += angle.degrees }
  }
  public func zIndex(_ value: Double) -> some View {
    TransformView(content: self) { $0.props.zIndex = value }
  }
  public func allowsHitTesting(_ value: Bool) -> some View {
    TransformView(content: self) { $0.props.hitTesting = value }
  }
  public func fixedSize(horizontal: Bool = true, vertical: Bool = true) -> some View {
    TransformView(content: self) {
      $0.props.fixedWidth = horizontal
      $0.props.fixedHeight = vertical
    }
  }
  public func clipped(antialiased: Bool = false) -> some View { clipShape(Rectangle()) }
  public func cornerRadius(_ radius: CGFloat, antialiased: Bool = true) -> some View {
    clipShape(RoundedRectangle(cornerRadius: radius))
  }
  public func border(_ color: Color, width: CGFloat = 1) -> some View {
    overlay(Rectangle().strokeBorder(color, lineWidth: width))
  }
  public func fontWeight(_ weight: Font.Weight?) -> some View {
    FontTransform(content: self) { $0.weight(weight ?? .regular) }
  }
  public func monospacedDigit() -> some View {
    FontTransform(content: self) {
      var font = $0
      font.family = "Consolas"
      return font
    }
  }
  public func underline(_ active: Bool = true, color: Color? = nil) -> some View {
    TransformView(content: self) { $0.props.underline = active }
  }
  public func scaledToFit() -> some View { aspectRatio(contentMode: .fit) }
  public func aspectRatio(_ ratio: CGFloat? = nil, contentMode: ContentMode) -> some View {
    TransformView(content: self) { element in
      if element.kind == .image {
        element.props.aspectFit = contentMode == .fit
      }
      var props = NodeProps()
      props.hasAspectConstraint = true
      props.aspectRatio = ratio.map { Double($0) }
      props.aspectFit = contentMode == .fit
      element = Element(kind: .frame, props: props, children: [element])
    }
  }
  public func aspectRatio(_ ratio: CGSize, contentMode: ContentMode) -> some View {
    let resolved: CGFloat? = ratio.height > 0 && ratio.width > 0 ? ratio.width / ratio.height : nil
    return aspectRatio(resolved, contentMode: contentMode)
  }
  public func alignmentGuide(
    _ guide: HorizontalAlignment, computeValue: @escaping (ViewDimensions) -> CGFloat
  ) -> some View { TransformView(content: self) { $0.horizontalGuide = computeValue } }
  public func alignmentGuide(
    _ guide: VerticalAlignment, computeValue: @escaping (ViewDimensions) -> CGFloat
  ) -> some View { TransformView(content: self) { $0.verticalGuide = computeValue } }
  public func coordinateSpace<Name: Hashable>(name: Name) -> some View {
    TransformView(content: self) { $0.props.coordinateSpace = AnyHashable(name) }
  }
  public func ignoresSafeArea(_ regions: SafeAreaRegions = .all, edges: Edge.Set = .all)
    -> some View
  { self }  // desktop content has no safe-area insets
  public func transition(_ transition: AnyTransition) -> some View {
    TransformView(content: self) { $0.props.transition = transition }
  }
  public func padding() -> some View { padding(8) }
}
public struct SafeAreaRegions: OptionSet {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }
  public static let all = Self(rawValue: 1)
}
extension Animation {
  public static func linear(duration: Double) -> Self {
    Self(duration: duration, x1: 0, y1: 0, x2: 1, y2: 1)
  }
  public static func easeInOut(duration: Double) -> Self {
    Self(duration: duration, x1: 0.42, y1: 0, x2: 0.58, y2: 1)
  }
  public static func easeOut(duration: Double) -> Self {
    Self(duration: duration, x1: 0, y1: 0, x2: 0.58, y2: 1)
  }
  public static func easeIn(duration: Double) -> Self {
    Self(duration: duration, x1: 0.42, y1: 0, x2: 1, y2: 1)
  }
  public static let `default` = Self(duration: 0.25, x1: 0.25, y1: 0.1, x2: 0.25, y2: 1)
  public func repeatForever(autoreverses: Bool = true) -> Self {
    var animation = self
    animation.repeats = true
    animation.autoreverses = autoreverses
    return animation
  }
  public func delay(_ value: Double) -> Self {
    var animation = self
    animation.delay = value
    return animation
  }
}
public func withAnimation<Result>(_ animation: Animation? = .default, _ body: () throws -> Result)
  rethrows -> Result
{
  let old = AnimationContext.current
  let oldExplicit = AnimationContext.isExplicit
  AnimationContext.current = animation
  AnimationContext.isExplicit = true
  defer {
    AnimationContext.current = old
    AnimationContext.isExplicit = oldExplicit
  }
  return try body()
}
enum AnimationContext {
  static var current: Animation?
  static var isExplicit = false
  static var disablesAnimations = false
  static var renderPass = 0
}
public enum TextAlignment: Equatable { case leading, center, trailing }
extension View {
  public func scaledToFill() -> some View { aspectRatio(contentMode: .fill) }
  public func tracking(_ spacing: CGFloat) -> some View {
    TransformView(content: self) { $0.props.tracking = spacing }
  }
  public func multilineTextAlignment(_ alignment: TextAlignment) -> some View {
    TransformView(content: self) { $0.props.textAlignment = alignment }
  }
  public func truncationMode(_ mode: Text.TruncationMode) -> some View {
    TransformView(content: self) { $0.props.truncationMode = mode }
  }
  public func tint(_ color: Color) -> some View { environment(\.tint, color) }
}
public struct StrokeStyle {
  public var lineWidth: CGFloat, dash: [CGFloat], dashPhase: CGFloat
  public init(
    lineWidth: CGFloat = 1,
    lineCap: CGLineCap = .butt,
    lineJoin: CGLineJoin = .miter,
    miterLimit: CGFloat = 10,
    dash: [CGFloat] = [],
    dashPhase: CGFloat = 0
  ) {
    self.lineWidth = lineWidth
    self.dash = dash
    self.dashPhase = dashPhase
  }
}

#if !(os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS))
  public enum CGLineCap: Int32, Sendable { case butt = 0, round = 1, square = 2 }
  public enum CGLineJoin: Int32, Sendable { case miter = 0, round = 1, bevel = 2 }
#endif

extension View {
  @ViewBuilder public func foregroundColor(_ color: Color?) -> some View {
    if let color { foregroundColor(color) } else { self }
  }
  public func strikethrough(
    _ active: Bool = true, pattern: Text.LineStyle.Pattern = .solid,
    color: Color? = nil
  ) -> some View {
    overlay {
      if active {
        Rectangle().fill(color ?? EnvironmentValues.current.foregroundColor ?? .black)
          .frame(height: 1).allowsHitTesting(false)
      }
    }
  }
}
extension Text {
  public enum LineStyle { public enum Pattern { case solid } }
}
