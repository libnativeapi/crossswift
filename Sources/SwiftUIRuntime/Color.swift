/// A color in the engine's platform-independent representation.
///
/// The native backend converts this to `NativeAPI.Color`; keeping a separate
/// type is what lets `SwiftUIRuntime` stay free of nativeapi imports. Color
/// components are 0...1; values outside the range are clamped when converted.

private final class DynamicColorProvider: @unchecked Sendable {
  let hover: (phase: HoverPaintPhase, target: Color)?
  let resolve: @Sendable (ColorScheme) -> (Double, Double, Double, Double)
  init(hover: (phase: HoverPaintPhase, target: Color)? = nil,
       _ resolve: @escaping @Sendable (ColorScheme) -> (Double, Double, Double, Double)) {
    self.hover = hover
    self.resolve = resolve
  }
}

public struct Color: Hashable, Sendable {
  public struct Resolved: Equatable, Hashable, Sendable, Codable {
    public var red: Float
    public var green: Float
    public var blue: Float
    public var opacity: Float

    public init(
      colorSpace: RGBColorSpace = .sRGB,
      red: Float,
      green: Float,
      blue: Float,
      opacity: Float = 1
    ) {
      self.red = red
      self.green = green
      self.blue = blue
      self.opacity = opacity
    }
  }

  public init(_ resolved: Color.Resolved) {
    self.init(
      red: Double(resolved.red),
      green: Double(resolved.green),
      blue: Double(resolved.blue),
      opacity: Double(resolved.opacity)
    )
  }

  public func resolve(in environment: EnvironmentValues) -> Color.Resolved {
    let r = resolved(in: environment.colorScheme)
    return Color.Resolved(
      red: Float(r.red),
      green: Float(r.green),
      blue: Float(r.blue),
      opacity: Float(r.opacity)
    )
  }

  public var red: Double
  public var green: Double
  public var blue: Double
  public var opacity: Double
  private var dynamicProvider: DynamicColorProvider?
  private var dynamicOpacityScale: Double = 1

  public init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
    self.red = red
    self.green = green
    self.blue = blue
    self.opacity = opacity
    self.dynamicProvider = nil
    self.dynamicOpacityScale = 1
  }

  public init(_ dynamic: @escaping @Sendable (ColorScheme) -> (r: Double, g: Double, b: Double, a: Double)) {
    let initial = dynamic(.dark)
    self.red = initial.r
    self.green = initial.g
    self.blue = initial.b
    self.opacity = initial.a
    self.dynamicProvider = DynamicColorProvider { scheme in
      let c = dynamic(scheme)
      return (c.r, c.g, c.b, c.a)
    }
    self.dynamicOpacityScale = 1
  }

  /// A gray color with the given brightness (0 = black, 1 = white).
  public init(white: Double, opacity: Double = 1) {
    self.init(red: white, green: white, blue: white, opacity: opacity)
  }

  /// A color from a 0xRRGGBB literal.
  public init(hex: UInt32, opacity: Double = 1) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255.0,
      green: Double((hex >> 8) & 0xFF) / 255.0,
      blue: Double(hex & 0xFF) / 255.0,
      opacity: opacity
    )
  }

  func onHover(_ phase: HoverPaintPhase, color: Color) -> Color {
    guard color != self else { return self }
    var copy = self
    let provider = DynamicColorProvider(hover: (phase, color)) { _ in (self.red, self.green, self.blue, self.opacity) }
    copy.dynamicProvider = provider
    return copy
  }

  package func sampledForPaint(at now: Double) -> Color {
    guard let h = dynamicProvider?.hover else { return self }
    let t = h.phase.fraction(at: now)
    return Color(red: red + (h.target.red - red) * t,
                 green: green + (h.target.green - green) * t,
                 blue: blue + (h.target.blue - blue) * t,
                 opacity: opacity + (h.target.opacity * dynamicOpacityScale - opacity) * t)
  }

  public func resolved(in scheme: ColorScheme) -> Color {
    guard let provider = dynamicProvider else { return self }
    if provider.hover != nil { return self }
    let c = provider.resolve(scheme)
    return Color(red: c.0, green: c.1, blue: c.2, opacity: c.3 * dynamicOpacityScale)
  }

  public static func == (lhs: Color, rhs: Color) -> Bool {
    switch (lhs.dynamicProvider, rhs.dynamicProvider) {
    case (nil, nil):
      return lhs.red == rhs.red && lhs.green == rhs.green && lhs.blue == rhs.blue
        && lhs.opacity == rhs.opacity
    case (let l?, let r?):
      if let a = l.hover, let b = r.hover {
        return a.phase === b.phase && a.target == b.target && lhs.red == rhs.red
          && lhs.green == rhs.green && lhs.blue == rhs.blue && lhs.opacity == rhs.opacity
          && lhs.dynamicOpacityScale == rhs.dynamicOpacityScale
      }
      return l === r && lhs.dynamicOpacityScale == rhs.dynamicOpacityScale
    default:
      return false
    }
  }

  public func hash(into hasher: inout Hasher) {
    if let h = dynamicProvider?.hover {
      hasher.combine(ObjectIdentifier(h.phase))
      hasher.combine(h.target)
      hasher.combine(red)
      hasher.combine(green)
      hasher.combine(blue)
      hasher.combine(opacity)
      hasher.combine(dynamicOpacityScale)
    } else if let p = dynamicProvider {
      hasher.combine(true)
      hasher.combine(ObjectIdentifier(p))
      hasher.combine(dynamicOpacityScale)
    } else {
      hasher.combine(false)
      hasher.combine(red)
      hasher.combine(green)
      hasher.combine(blue)
      hasher.combine(opacity)
    }
  }

  func saturating(_ amount: Double) -> Color {
    let gray = red * 0.2126 + green * 0.7152 + blue * 0.0722
    let base = Color(red: gray + (red - gray) * amount,
                     green: gray + (green - gray) * amount,
                     blue: gray + (blue - gray) * amount, opacity: opacity)
    guard let hover = dynamicProvider?.hover else { return base }
    return base.onHover(hover.phase, color: hover.target.opacity(dynamicOpacityScale).saturating(amount))
  }

  public static let clear = Color(red: 0, green: 0, blue: 0, opacity: 0)
  public static let black = Color(red: 0, green: 0, blue: 0)
  public static let white = Color(red: 1, green: 1, blue: 1)
  public static let red = Color(red: 1.0, green: 0.251, blue: 0.208)
  public static let green = Color(red: 0.196, green: 0.800, blue: 0.349)
  public static let blue = Color(red: 0.039, green: 0.518, blue: 1.0)
  public static let yellow = Color(red: 1.0, green: 0.820, blue: 0.0)
  public static let orange = Color(red: 1.0, green: 0.604, blue: 0.020)
  public static let purple = Color(red: 0.718, green: 0.337, blue: 0.910)
  public static let pink = Color(red: 1.0, green: 0.216, blue: 0.373)
  public static let cyan = Color(red: 0.353, green: 0.784, blue: 0.980)
  public static let mint = Color(red: 0.388, green: 0.902, blue: 0.886)
  public static let teal = Color(red: 0.251, green: 0.784, blue: 0.878)
  public static let indigo = Color(red: 0.369, green: 0.361, blue: 0.902)
  public static let brown = Color(red: 0.635, green: 0.518, blue: 0.369)
  public static let gray = Color(white: 0.5)
  public static let accentColor = Color(red: 0.039, green: 0.518, blue: 1.0)
  public static let primary = Color { scheme in
    scheme == .dark ? (1, 1, 1, 1) : (0, 0, 0, 1)
  }
  public static let secondary = Color { scheme in
    scheme == .dark ? (0.68, 0.68, 0.72, 1) : (0.35, 0.35, 0.35, 1)
  }
}
extension Color: View {
  public var body: some View { ShapeView(radius: 0, fill: self) }
}
extension Color {
  public enum RGBColorSpace { case sRGB, sRGBLinear, displayP3 }
  public init(_ space: RGBColorSpace, red: Double, green: Double, blue: Double, opacity: Double = 1)
  {
    self.init(red: red, green: green, blue: blue, opacity: opacity)
  }
  public init(_ space: RGBColorSpace, white: Double, opacity: Double = 1) {
    self.init(white: white, opacity: opacity)
  }
  public func opacity(_ value: Double) -> Color {
    if let provider = dynamicProvider {
      var copy = self
      copy.opacity = opacity * value
      copy.dynamicOpacityScale = dynamicOpacityScale * value
      _ = provider
      return copy
    }
    return Color(red: red, green: green, blue: blue, opacity: opacity * value)
  }
}
