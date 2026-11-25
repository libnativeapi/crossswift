import Foundation

#if (os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)) && canImport(CoreGraphics)
  import CoreGraphics
#endif

/// Backend-neutral vector path. Each command is M(x,y), L(x,y), C(6), or Z.

public struct Angle: Equatable, Hashable, Sendable {
  public static let zero = Angle(radians: 0)
  public var radians: Double
  public var degrees: Double { radians * 180 / .pi }
  public static func degrees(_ value: Double) -> Angle { Angle(radians: value * .pi / 180) }
  public static func radians(_ value: Double) -> Angle { Angle(radians: value) }
}
public struct Path: Equatable {
  public var commands: [Double] = []
  public init() {}
  public init(_ build: (inout Path) -> Void) {
    self.init()
    build(&self)
  }
  public init(_ other: Path) { self = other }
  public var cgPath: Path { self }
  public init(_ rect: CGRect) {
    self.init()
    addRect(rect)
  }
  public init(roundedRect rect: CGRect, cornerRadius: CGFloat, style: RoundedCornerStyle = .circular) {
    self.init()
    let r = min(cornerRadius, rect.width / 2, rect.height / 2)
    move(to: CGPoint(x: rect.minX + r, y: rect.minY))
    addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
    addArc(
      center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r, startAngle: .degrees(-90),
      endAngle: .degrees(0), clockwise: false)
    addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
    addArc(
      center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: .degrees(0),
      endAngle: .degrees(90), clockwise: false)
    addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
    addArc(
      center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: .degrees(90),
      endAngle: .degrees(180), clockwise: false)
    addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
    addArc(
      center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r, startAngle: .degrees(180),
      endAngle: .degrees(270), clockwise: false)
    closeSubpath()
  }
  public mutating func move(to p: CGPoint) { commands += [0, p.x, p.y] }
  public mutating func addLine(to p: CGPoint) { commands += [1, p.x, p.y] }
  public mutating func addCurve(to p: CGPoint, control1: CGPoint, control2: CGPoint) {
    commands += [2, control1.x, control1.y, control2.x, control2.y, p.x, p.y]
  }
  public mutating func closeSubpath() { commands.append(3) }
  public mutating func addRect(_ r: CGRect) {
    move(to: r.origin)
    addLine(to: CGPoint(x: r.maxX, y: r.minY))
    addLine(to: CGPoint(x: r.maxX, y: r.maxY))
    addLine(to: CGPoint(x: r.minX, y: r.maxY))
    closeSubpath()
  }
  public mutating func addEllipse(in r: CGRect) {
    let cx = r.midX, cy = r.midY
    let rx = r.width / 2, ry = r.height / 2
    let kx = rx * 0.5522847498, ky = ry * 0.5522847498
    move(to: CGPoint(x: cx, y: r.minY))
    addCurve(
      to: CGPoint(x: r.maxX, y: cy),
      control1: CGPoint(x: cx + kx, y: r.minY),
      control2: CGPoint(x: r.maxX, y: cy - ky))
    addCurve(
      to: CGPoint(x: cx, y: r.maxY),
      control1: CGPoint(x: r.maxX, y: cy + ky),
      control2: CGPoint(x: cx + kx, y: r.maxY))
    addCurve(
      to: CGPoint(x: r.minX, y: cy),
      control1: CGPoint(x: cx - kx, y: r.maxY),
      control2: CGPoint(x: r.minX, y: cy + ky))
    addCurve(
      to: CGPoint(x: cx, y: r.minY),
      control1: CGPoint(x: r.minX, y: cy - ky),
      control2: CGPoint(x: cx - kx, y: r.minY))
    closeSubpath()
  }
  public mutating func addPath(_ path: Path) { commands += path.commands }
  public mutating func addArc(
    center: CGPoint, radius: CGFloat, startAngle: Angle, endAngle: Angle, clockwise: Bool
  ) {
    var delta = endAngle.radians - startAngle.radians
    if clockwise && delta > 0 { delta -= 2 * .pi }
    if !clockwise && delta < 0 { delta += 2 * .pi }
    let pieces = max(1, Int(ceil(abs(delta) / (.pi / 2))))
    let step = delta / Double(pieces)
    let start = CGPoint(
      x: center.x + radius * cos(startAngle.radians), y: center.y + radius * sin(startAngle.radians)
    )
    if commands.isEmpty { move(to: start) } else { addLine(to: start) }
    for i in 0..<pieces {
      let a = startAngle.radians + Double(i) * step
      let b = a + step
      let k = 4 / 3 * tan(step / 4)
      addCurve(
        to: CGPoint(x: center.x + radius * cos(b), y: center.y + radius * sin(b)),
        control1: CGPoint(
          x: center.x + radius * (cos(a) - k * sin(a)), y: center.y + radius * (sin(a) + k * cos(a))
        ),
        control2: CGPoint(
          x: center.x + radius * (cos(b) + k * sin(b)), y: center.y + radius * (sin(b) - k * cos(b))
        ))
    }
  }
  public mutating func addArc(
    tangent1End p1: CGPoint,
    tangent2End p2: CGPoint,
    radius: CGFloat
  ) {
    addLine(to: p1)
    addLine(to: p2)
  }
  public func transformed(x: Double = 0, y: Double = 0, sx: Double = 1, sy: Double = 1) -> Path {
    transformed(a: sx, b: 0, c: 0, d: sy, tx: x, ty: y)
  }

  public func transformed(
    a: Double, b: Double, c: Double, d: Double, tx: Double, ty: Double
  ) -> Path {
    var output = self
    var i = 0
    while i < commands.count {
      let n = commands[i] == 2 ? 6 : commands[i] == 3 ? 0 : 2
      for j in stride(from: 1, through: n, by: 2) {
        let px = commands[i + j]
        let py = commands[i + j + 1]
        output.commands[i + j] = a * px + c * py + tx
        output.commands[i + j + 1] = b * px + d * py + ty
      }
      i += n + 1
    }
    return output
  }

  public func trimmedPath(from: CGFloat, to: CGFloat) -> Path {
    let f = max(0.0, min(1.0, Double(from)))
    let t = max(0.0, min(1.0, Double(to)))
    guard t > f, !commands.isEmpty else { return Path() }
    if f <= 1e-6 && t >= 1.0 - 1e-6 { return self }

    enum Seg {
      case line(CGPoint, CGPoint)
      case curve(CGPoint, CGPoint, CGPoint, CGPoint)
    }

    func dist(_ a: CGPoint, _ b: CGPoint) -> Double {
      hypot(Double(b.x - a.x), Double(b.y - a.y))
    }

    func evalCubic(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ u: Double) -> CGPoint {
      let mt = 1.0 - u
      let mt2 = mt * mt
      let u2 = u * u
      let x = mt2 * mt * Double(p0.x) + 3 * mt2 * u * Double(p1.x) + 3 * mt * u2 * Double(p2.x) + u2 * u * Double(p3.x)
      let y = mt2 * mt * Double(p0.y) + 3 * mt2 * u * Double(p1.y) + 3 * mt * u2 * Double(p2.y) + u2 * u * Double(p3.y)
      return CGPoint(x: x, y: y)
    }

    func lerpPt(_ a: CGPoint, _ b: CGPoint, _ u: Double) -> CGPoint {
      CGPoint(
        x: Double(a.x) + (Double(b.x) - Double(a.x)) * u,
        y: Double(a.y) + (Double(b.y) - Double(a.y)) * u
      )
    }

    // De Casteljau subdivision of cubic Bezier [0, 1] to sub-interval [u0, u1].
    func splitCubicLeft(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ u: Double)
      -> (CGPoint, CGPoint, CGPoint, CGPoint)
    {
      let q0 = lerpPt(p0, p1, u)
      let q1 = lerpPt(p1, p2, u)
      let q2 = lerpPt(p2, p3, u)
      let r0 = lerpPt(q0, q1, u)
      let r1 = lerpPt(q1, q2, u)
      let s0 = lerpPt(r0, r1, u)
      return (p0, q0, r0, s0)
    }

    func splitCubicRight(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ u: Double)
      -> (CGPoint, CGPoint, CGPoint, CGPoint)
    {
      let q0 = lerpPt(p0, p1, u)
      let q1 = lerpPt(p1, p2, u)
      let q2 = lerpPt(p2, p3, u)
      let r0 = lerpPt(q0, q1, u)
      let r1 = lerpPt(q1, q2, u)
      let s0 = lerpPt(r0, r1, u)
      return (s0, r1, q2, p3)
    }

    func subCubic(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ u0: Double, _ u1: Double)
      -> (CGPoint, CGPoint, CGPoint, CGPoint)
    {
      let right = splitCubicRight(p0, p1, p2, p3, u0)
      let span = max(1e-9, 1.0 - u0)
      let localEnd = max(0.0, min(1.0, (u1 - u0) / span))
      return splitCubicLeft(right.0, right.1, right.2, right.3, localEnd)
    }

    // Build flattened segment list with per-segment chord tables for curves.
    struct MeasuredSeg {
      let seg: Seg
      let length: Double
      let cumTable: [Double]  // For curves: 17 entries from u=0..1; empty for lines
      let startsSubpath: Bool
    }

    var measured: [MeasuredSeg] = []
    var cur = CGPoint.zero
    var subStart = CGPoint.zero
    var nextStartsSubpath = true
    var i = 0
    while i < commands.count {
      let op = Int(commands[i])
      i += 1
      switch op {
      case 0 where i + 1 < commands.count:
        cur = CGPoint(x: commands[i], y: commands[i + 1])
        subStart = cur
        nextStartsSubpath = true
        i += 2
      case 1 where i + 1 < commands.count:
        let p = CGPoint(x: commands[i], y: commands[i + 1])
        let len = dist(cur, p)
        if len > 1e-9 {
          measured.append(MeasuredSeg(seg: .line(cur, p), length: len, cumTable: [], startsSubpath: nextStartsSubpath))
          nextStartsSubpath = false
        }
        cur = p
        i += 2
      case 2 where i + 5 < commands.count:
        let c1 = CGPoint(x: commands[i], y: commands[i + 1])
        let c2 = CGPoint(x: commands[i + 2], y: commands[i + 3])
        let p = CGPoint(x: commands[i + 4], y: commands[i + 5])
        let steps = 16
        var table = [0.0]
        var prev = cur
        var acc = 0.0
        for s in 1...steps {
          let pt = evalCubic(cur, c1, c2, p, Double(s) / Double(steps))
          acc += dist(prev, pt)
          table.append(acc)
          prev = pt
        }
        if acc > 1e-9 {
          measured.append(MeasuredSeg(seg: .curve(cur, c1, c2, p), length: acc, cumTable: table, startsSubpath: nextStartsSubpath))
          nextStartsSubpath = false
        }
        cur = p
        i += 6
      case 3:
        let len = dist(cur, subStart)
        if len > 1e-9 {
          measured.append(MeasuredSeg(seg: .line(cur, subStart), length: len, cumTable: [], startsSubpath: nextStartsSubpath))
          nextStartsSubpath = false
        }
        cur = subStart
        nextStartsSubpath = true
      default:
        break
      }
    }

    let totalLen = measured.reduce(0.0) { $0 + $1.length }
    guard totalLen > 1e-9 else { return Path() }

    let startDist = f * totalLen
    let endDist = t * totalLen

    func paramForArc(_ target: Double, table: [Double]) -> Double {
      guard table.count >= 2 else { return 0 }
      let maxL = table.last ?? 1.0
      if target <= 0 { return 0 }
      if target >= maxL { return 1 }
      let steps = table.count - 1
      for idx in 0..<steps {
        if target >= table[idx] && target <= table[idx + 1] {
          let span = table[idx + 1] - table[idx]
          let frac = span > 1e-9 ? (target - table[idx]) / span : 0
          return (Double(idx) + frac) / Double(steps)
        }
      }
      return 1
    }

    var out = Path()
    var cursor = 0.0
    var hasCurrent = false
    for item in measured {
      let segStart = cursor
      let segEnd = cursor + item.length
      cursor = segEnd
      if segEnd <= startDist + 1e-9 || segStart >= endDist - 1e-9 {
        hasCurrent = false
        continue
      }
      let localStart = max(0.0, startDist - segStart)
      let localEnd = min(item.length, endDist - segStart)
      let needMove = !hasCurrent || item.startsSubpath || localStart > 1e-9

      switch item.seg {
      case .line(let a, let b):
        let u0 = localStart / item.length
        let u1 = localEnd / item.length
        let pStart = lerpPt(a, b, u0)
        let pEnd = lerpPt(a, b, u1)
        if needMove { out.move(to: pStart) }
        out.addLine(to: pEnd)
      case .curve(let p0, let p1, let p2, let p3):
        let u0 = paramForArc(localStart, table: item.cumTable)
        let u1 = paramForArc(localEnd, table: item.cumTable)
        let (sp0, sp1, sp2, sp3) = subCubic(p0, p1, p2, p3, u0, u1)
        if needMove { out.move(to: sp0) }
        out.addCurve(to: sp3, control1: sp1, control2: sp2)
      }
      hasCurrent = localEnd >= item.length - 1e-9
    }
    return out
  }

  public func reversed() -> Path {
    enum Seg {
      case line(CGPoint, CGPoint)
      case curve(CGPoint, CGPoint, CGPoint, CGPoint)
    }
    var out = Path()
    var subpaths: [(segs: [Seg], closed: Bool)] = []
    var currentSegs: [Seg] = []
    var cur = CGPoint.zero
    var start = CGPoint.zero
    var hasSub = false
    var i = 0
    while i < commands.count {
      let op = Int(commands[i])
      i += 1
      switch op {
      case 0:
        if hasSub && !currentSegs.isEmpty {
          subpaths.append((currentSegs, false))
          currentSegs = []
        }
        cur = CGPoint(x: commands[i], y: commands[i + 1])
        start = cur
        hasSub = true
        i += 2
      case 1:
        let p = CGPoint(x: commands[i], y: commands[i + 1])
        currentSegs.append(.line(cur, p))
        cur = p
        i += 2
      case 2:
        let c1 = CGPoint(x: commands[i], y: commands[i + 1])
        let c2 = CGPoint(x: commands[i + 2], y: commands[i + 3])
        let p = CGPoint(x: commands[i + 4], y: commands[i + 5])
        currentSegs.append(.curve(cur, c1, c2, p))
        cur = p
        i += 6
      case 3:
        if cur != start {
          currentSegs.append(.line(cur, start))
          cur = start
        }
        if !currentSegs.isEmpty {
          subpaths.append((currentSegs, true))
          currentSegs = []
        }
        hasSub = false
      default:
        break
      }
    }
    if hasSub && !currentSegs.isEmpty {
      subpaths.append((currentSegs, false))
    }
    for sub in subpaths.reversed() {
      guard let last = sub.segs.last else { continue }
      let firstPt: CGPoint
      switch last {
      case .line(_, let b): firstPt = b
      case .curve(_, _, _, let b): firstPt = b
      }
      out.move(to: firstPt)
      for seg in sub.segs.reversed() {
        switch seg {
        case .line(let a, _):
          out.addLine(to: a)
        case .curve(let a, let c1, let c2, _):
          out.addCurve(to: a, control1: c2, control2: c1)
        }
      }
      if sub.closed { out.closeSubpath() }
    }
    return out
  }
}
public struct Circle: Shape {
  nonisolated public init() {}
  nonisolated public var cornerRadius: CGFloat { .infinity }
  nonisolated public func path(in r: CGRect) -> Path {
    var p = Path()
    p.addArc(
      center: CGPoint(x: r.midX, y: r.midY), radius: min(r.width, r.height) / 2,
      startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
    p.closeSubpath()
    return p
  }
}
public struct Capsule: Shape {
  nonisolated public init(style: RoundedCornerStyle = .continuous) {}
  nonisolated public var cornerRadius: CGFloat { .infinity }
}
public struct RectangleCornerRadii: Equatable, Sendable {
  public var topLeading: CGFloat, bottomLeading: CGFloat, bottomTrailing: CGFloat,
    topTrailing: CGFloat
  nonisolated public init(
    topLeading: CGFloat = 0, bottomLeading: CGFloat = 0, bottomTrailing: CGFloat = 0,
    topTrailing: CGFloat = 0
  ) {
    self.topLeading = topLeading
    self.bottomLeading = bottomLeading
    self.bottomTrailing = bottomTrailing
    self.topTrailing = topTrailing
  }
}
public struct UnevenRoundedRectangle: Shape {
  let radii: RectangleCornerRadii
  nonisolated public init(cornerRadii: RectangleCornerRadii, style: RoundedCornerStyle = .continuous) {
    radii = cornerRadii
  }
  nonisolated public init(
    topLeadingRadius: CGFloat = 0,
    bottomLeadingRadius: CGFloat = 0,
    bottomTrailingRadius: CGFloat = 0,
    topTrailingRadius: CGFloat = 0,
    style: RoundedCornerStyle = .continuous
  ) {
    radii = RectangleCornerRadii(
      topLeading: topLeadingRadius,
      bottomLeading: bottomLeadingRadius,
      bottomTrailing: bottomTrailingRadius,
      topTrailing: topTrailingRadius)
  }
  nonisolated public func path(in r: CGRect) -> Path {
    var p = Path()
    let tl = min(radii.topLeading, r.width / 2, r.height / 2)
    let tr = min(radii.topTrailing, r.width / 2, r.height / 2)
    let br = min(radii.bottomTrailing, r.width / 2, r.height / 2)
    let bl = min(radii.bottomLeading, r.width / 2, r.height / 2)
    p.move(to: CGPoint(x: r.minX + tl, y: r.minY))
    p.addLine(to: CGPoint(x: r.maxX - tr, y: r.minY))
    p.addArc(
      center: CGPoint(x: r.maxX - tr, y: r.minY + tr), radius: tr, startAngle: .degrees(-90),
      endAngle: .degrees(0), clockwise: false)
    p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - br))
    p.addArc(
      center: CGPoint(x: r.maxX - br, y: r.maxY - br), radius: br, startAngle: .degrees(0),
      endAngle: .degrees(90), clockwise: false)
    p.addLine(to: CGPoint(x: r.minX + bl, y: r.maxY))
    p.addArc(
      center: CGPoint(x: r.minX + bl, y: r.maxY - bl), radius: bl, startAngle: .degrees(90),
      endAngle: .degrees(180), clockwise: false)
    p.addLine(to: CGPoint(x: r.minX, y: r.minY + tl))
    p.addArc(
      center: CGPoint(x: r.minX + tl, y: r.minY + tl), radius: tl, startAngle: .degrees(180),
      endAngle: .degrees(270), clockwise: false)
    p.closeSubpath()
    return p
  }
}
struct PaintedShape<S: Shape>: View, _PrimitiveView {
  typealias Body = Never
  let shape: S
  let fill: Color
  let stroke: Color
  let width: CGFloat
  let inset: Bool
  var body: Never { fatalError() }
  func _makeElement(path: ViewPath) -> Element {
    var p = NodeProps()
    p.fillWidth = true
    p.fillHeight = true
    p.background = fill
    p.cornerRadius = Double(shape.cornerRadius)
    p.borderColor = stroke
    p.borderWidth = width
    var e = Element(kind: .shape, props: p)
    e.pathBuilder = { r in shape.path(in: inset ? r.insetBy(dx: width / 2, dy: width / 2) : r) }
    return e
  }
}
public struct TrimmedShape<S: Shape>: Shape {
  let shape: S
  let from: CGFloat
  let to: CGFloat
  let inset: CGFloat
  nonisolated public func path(in r: CGRect) -> Path {
    // Circular paths preserve a true arc rather than closing the trimmed span.
    if shape is Circle {
      var p = Path()
      p.addArc(
        center: CGPoint(x: r.midX, y: r.midY), radius: max(0, min(r.width, r.height) / 2 - inset),
        startAngle: .degrees(from * 360), endAngle: .degrees(to * 360), clockwise: false)
      return p
    }
    return shape.path(in: r.insetBy(dx: inset, dy: inset)).trimmedPath(from: from, to: to)
  }
}
extension Shape {
  nonisolated public var cornerRadius: CGFloat { 0 }
  nonisolated public func path(in rect: CGRect) -> Path { Path(roundedRect: rect, cornerRadius: cornerRadius) }
  public var body: some View { fill(.black) }
  nonisolated public func trim(from: CGFloat = 0, to: CGFloat = 1) -> some Shape {
    TrimmedShape(shape: self, from: from, to: to, inset: 0)
  }
  nonisolated public func inset(by amount: CGFloat) -> some Shape { InsetShape(shape: self, amount: amount) }
}
public struct InsetShape<S: Shape>: Shape {
  let shape: S
  let amount: CGFloat
  nonisolated public func path(in rect: CGRect) -> Path { shape.path(in: rect.insetBy(dx: amount, dy: amount)) }
  nonisolated public func trim(from: CGFloat = 0, to: CGFloat = 1) -> some Shape {
    TrimmedShape(shape: shape, from: from, to: to, inset: amount)
  }
}
public enum GradientKind: Int, Equatable, Hashable, Sendable {
  case linear = 0
  case radial = 1
  case angular = 2
}
public struct LinearGradient: View, _PrimitiveView, Sendable {
  public typealias Body = Never
  public struct Data: Equatable, Sendable {
    public let kind: GradientKind
    public let colors: [Color]
    public let locations: [Double]
    public let start: UnitPoint
    public let end: UnitPoint
    public let startRadius: Double
    public let endRadius: Double
    public let startAngle: Double
    public let endAngle: Double

    nonisolated public init(
      kind: GradientKind = .linear,
      colors: [Color],
      locations: [Double] = [],
      start: UnitPoint,
      end: UnitPoint = .bottomTrailing,
      startRadius: Double = 0,
      endRadius: Double = 0,
      startAngle: Double = 0,
      endAngle: Double = 360
    ) {
      self.kind = kind
      self.colors = colors
      if locations.count == colors.count && !locations.isEmpty {
        self.locations = locations
      } else if colors.count <= 1 {
        self.locations = colors.isEmpty ? [] : [0]
      } else {
        let last = Double(colors.count - 1)
        self.locations = (0..<colors.count).map { Double($0) / last }
      }
      self.start = start
      self.end = end
      self.startRadius = startRadius
      self.endRadius = endRadius
      self.startAngle = startAngle
      self.endAngle = endAngle
    }
  }
  let data: Data
  nonisolated public init(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) {
    data = Data(kind: .linear, colors: colors, start: startPoint, end: endPoint)
  }
  nonisolated init(data: Data) {
    self.data = data
  }
  public var body: Never { fatalError() }
  func _makeElement(path: ViewPath) -> Element {
    var p = NodeProps()
    p.gradient = data
    p.fillWidth = true
    p.fillHeight = true
    return Element(kind: .gradient, props: p)
  }
}
public struct Image: View, _PrimitiveView {
  public typealias Body = Never
  public enum TemplateRenderingMode { case template, original }
  public enum Interpolation { case none, low, medium, high }
  public enum Scale: Hashable, Sendable { case small, medium, large }

  nonisolated(unsafe) package static var assetPathResolver: ((String, Bundle?) -> String?)?

  let name: String
  let bundle: Bundle?
  var isSystemSymbol = false
  var naturalSize: Size?
  var template = false
  var flexible = false

  nonisolated public init(_ name: String, bundle: Bundle? = nil) {
    self.name = name
    self.bundle = bundle
  }

  nonisolated public init(systemName: String) {
    self.name = systemName
    self.bundle = nil
    self.isSystemSymbol = true
    self.template = true
  }

  package init(filePath: String, size: Size?, isTemplate: Bool = false) {
    self.name = filePath
    self.bundle = nil
    self.naturalSize = size
    self.template = isTemplate
  }

  public var body: Never { fatalError() }

  public func resizable() -> Image {
    var image = self
    image.flexible = true
    return image
  }

  public func renderingMode(_ mode: TemplateRenderingMode?) -> Image {
    var image = self
    image.template = mode == .template
    return image
  }

  public func interpolation(_ interpolation: Interpolation) -> Image {
    self
  }

  public func antialiased(_ isAntialiased: Bool) -> Image {
    self
  }

  func _makeElement(path: ViewPath) -> Element {
    var p = NodeProps()
    if isSystemSymbol {
      p.imagePath = "sf://" + name
      p.font = EnvironmentValues.current.font
    } else {
      #if os(WASI) || CROSS_SWIFTUI_HARMONY
        if let resolved = Self.assetPathResolver?(name, bundle) {
          p.imagePath = resolved
        } else {
          p.imagePath = name
        }
      #else
        if FileManager.default.fileExists(atPath: name) {
          p.imagePath = name
        } else if let resolved = Self.assetPathResolver?(name, bundle) {
          p.imagePath = resolved
        } else {
          let resources = bundle ?? .main
          p.imagePath =
            resources.url(forResource: name, withExtension: "svg")?.path
            ?? resources.url(forResource: name, withExtension: "pdf")?.path
            ?? resources.url(forResource: name, withExtension: "png")?.path
            ?? name
        }
      #endif
    }
    if let naturalSize {
      p.intrinsicImageWidth = naturalSize.width
      p.intrinsicImageHeight = naturalSize.height
      if !flexible {
        p.idealWidth = naturalSize.width
        p.idealHeight = naturalSize.height
      }
    }
    p.imageTemplate = template
    p.fillWidth = flexible
    p.fillHeight = flexible
    return Element(kind: .image, props: p)
  }
}
public struct GraphicsContext {
  public struct ClipOptions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let inverse = ClipOptions(rawValue: 1 << 0)
  }

  public struct DrawingOptions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let disablesSubpixelQuantization = DrawingOptions(rawValue: 1 << 0)
  }

  public struct FilterOptions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let linearColor = FilterOptions(rawValue: 1 << 0)
  }

  public struct Filter: Sendable {
    public static func blur(
      radius: CGFloat,
      options: BlurOptions = BlurOptions()
    ) -> Filter {
      Filter()
    }
    public static func shadow(
      color: Color = Color(red: 0, green: 0, blue: 0, opacity: 0.33),
      radius: CGFloat,
      x: CGFloat = 0,
      y: CGFloat = 0,
      blendMode: GraphicsContext.BlendMode = .normal,
      options: ShadowOptions = ShadowOptions()
    ) -> Filter {
      Filter()
    }
  }

  public struct BlurOptions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let opaque = BlurOptions(rawValue: 1 << 0)
    public static let dithersResult = BlurOptions(rawValue: 1 << 1)
  }

  public struct ShadowOptions: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let shadowAbove = ShadowOptions(rawValue: 1 << 0)
    public static let shadowOnly = ShadowOptions(rawValue: 1 << 1)
    public static let invertsAlpha = ShadowOptions(rawValue: 1 << 2)
    public static let disablesGroup = ShadowOptions(rawValue: 1 << 3)
  }

  public enum BlendMode: Sendable {
    case normal, multiply, screen, overlay, darken, lighten
  }

  public enum Shading {
    case color(Color)
    case linearGradient(Gradient, startPoint: CGPoint, endPoint: CGPoint)
    case radialGradient(Gradient, center: CGPoint, startRadius: CGFloat, endRadius: CGFloat)
    case conicGradient(Gradient, center: CGPoint, angle: Angle = .zero)
    case style(any ShapeStyle)
  }

  public struct ResolvedText {
    let text: Text
  }

  public struct ResolvedImage {
    let image: Image
    public var size: CGSize {
      if let s = image.naturalSize {
        return CGSize(width: s.width, height: s.height)
      }
      return CGSize(width: 24, height: 24)
    }
  }

  var elements: [Element] = []
  var canvasSize: CGSize = .zero
  // 2D affine matrix: x' = a*x + c*y + tx, y' = b*x + d*y + ty
  var ma: Double = 1, mb: Double = 0, mc: Double = 0, md: Double = 1, tx: Double = 0, ty: Double = 0
  public var opacity: Double = 1.0
  var clipPath: Path?

  init(size: CGSize = .zero) {
    self.canvasSize = size
  }

  private mutating func multiply(a: Double, b: Double, c: Double, d: Double, e: Double, f: Double) {
    let na = ma * a + mc * b
    let nb = mb * a + md * b
    let nc = ma * c + mc * d
    let nd = mb * c + md * d
    let ntx = ma * e + mc * f + tx
    let nty = mb * e + md * f + ty
    ma = na; mb = nb; mc = nc; md = nd; tx = ntx; ty = nty
  }

  private func transformPoint(_ pt: CGPoint) -> CGPoint {
    CGPoint(
      x: ma * Double(pt.x) + mc * Double(pt.y) + tx,
      y: mb * Double(pt.x) + md * Double(pt.y) + ty
    )
  }

  public mutating func translateBy(x: CGFloat, y: CGFloat) {
    multiply(a: 1, b: 0, c: 0, d: 1, e: Double(x), f: Double(y))
  }

  public mutating func scaleBy(x: CGFloat, y: CGFloat) {
    multiply(a: Double(x), b: 0, c: 0, d: Double(y), e: 0, f: 0)
  }

  public mutating func rotate(by angle: Angle) {
    let c = cos(angle.radians)
    let s = sin(angle.radians)
    multiply(a: c, b: s, c: -s, d: c, e: 0, f: 0)
  }

  public mutating func concatenate(_ matrix: (a: CGFloat, b: CGFloat, c: CGFloat, d: CGFloat, tx: CGFloat, ty: CGFloat)) {
    multiply(a: Double(matrix.a), b: Double(matrix.b), c: Double(matrix.c), d: Double(matrix.d), e: Double(matrix.tx), f: Double(matrix.ty))
  }

  private func resolveSolidColor(_ shading: Shading) -> Color {
    switch shading {
    case .color(let c):
      return c.opacity(opacity)
    case .linearGradient(let g, _, _),
      .radialGradient(let g, _, _, _),
      .conicGradient(let g, _, _):
      return (g.stops.first?.color ?? .clear).opacity(opacity)
    case .style(let style):
      return style._resolvePrimaryColor(in: EnvironmentValues.current).opacity(opacity)
    }
  }

  private func resolveGradient(_ shading: Shading) -> LinearGradient.Data? {
    let w = max(1.0, Double(canvasSize.width))
    let h = max(1.0, Double(canvasSize.height))
    switch shading {
    case .color:
      return nil
    case .linearGradient(let g, let sp, let ep):
      let p1 = transformPoint(sp)
      let p2 = transformPoint(ep)
      let sorted = g.stops.sorted { $0.location < $1.location }
      return LinearGradient.Data(
        kind: .linear,
        colors: sorted.map { $0.color.opacity(opacity) },
        locations: sorted.map { Double($0.location) },
        start: UnitPoint(x: Double(p1.x) / w, y: Double(p1.y) / h),
        end: UnitPoint(x: Double(p2.x) / w, y: Double(p2.y) / h)
      )
    case .radialGradient(let g, let center, let startRadius, let endRadius):
      let c = transformPoint(center)
      let scaleMag = hypot(ma, mb)
      let sorted = g.stops.sorted { $0.location < $1.location }
      return LinearGradient.Data(
        kind: .radial,
        colors: sorted.map { $0.color.opacity(opacity) },
        locations: sorted.map { Double($0.location) },
        start: UnitPoint(x: Double(c.x) / w, y: Double(c.y) / h),
        end: UnitPoint(x: Double(endRadius) * scaleMag, y: Double(startRadius) * scaleMag),
        startRadius: Double(startRadius) * scaleMag,
        endRadius: Double(endRadius) * scaleMag
      )
    case .conicGradient(let g, let center, let angle):
      let c = transformPoint(center)
      let rotDeg = atan2(mb, ma) * 180.0 / .pi
      let sorted = g.stops.sorted { $0.location < $1.location }
      return LinearGradient.Data(
        kind: .angular,
        colors: sorted.map { $0.color.opacity(opacity) },
        locations: sorted.map { Double($0.location) },
        start: UnitPoint(x: Double(c.x) / w, y: Double(c.y) / h),
        end: .trailing,
        startAngle: angle.degrees + rotDeg,
        endAngle: angle.degrees + rotDeg + 360
      )
    case .style(let style):
      guard let data = style._resolveGradientData() else { return nil }
      return LinearGradient.Data(
        kind: data.kind,
        colors: data.colors.map { $0.opacity(opacity) },
        locations: data.locations,
        start: data.start,
        end: data.end,
        startRadius: data.startRadius,
        endRadius: data.endRadius,
        startAngle: data.startAngle,
        endAngle: data.endAngle
      )
    }
  }

  public mutating func fill(_ path: Path, with shading: Shading, style: FillStyle = FillStyle()) {
    let transformed = path.transformed(a: ma, b: mb, c: mc, d: md, tx: tx, ty: ty)
    if let grad = resolveGradient(shading) {
      var p = NodeProps()
      p.gradient = grad
      p.fillWidth = true
      p.fillHeight = true
      var el = Element(kind: .gradient, props: p)
      el.clipPathBuilder = { _ in transformed }
      elements.append(el)
      return
    }
    var p = NodeProps()
    p.path = transformed
    p.background = resolveSolidColor(shading)
    p.fillWidth = true
    p.fillHeight = true
    elements.append(Element(kind: .path, props: p))
  }

  public mutating func stroke(_ path: Path, with shading: Shading, style: StrokeStyle) {
    let transformed = path.transformed(a: ma, b: mb, c: mc, d: md, tx: tx, ty: ty)
    var p = NodeProps()
    p.path = transformed
    p.background = .clear
    p.borderColor = resolveSolidColor(shading)
    let scaleMag = max(0.01, hypot(ma, mb))
    p.borderWidth = Double(style.lineWidth) * scaleMag
    p.dash = style.dash.map { Double($0) * scaleMag }
    p.fillWidth = true
    p.fillHeight = true
    elements.append(Element(kind: .path, props: p))
  }

  public mutating func stroke(_ path: Path, with shading: Shading, lineWidth: CGFloat = 1) {
    stroke(path, with: shading, style: StrokeStyle(lineWidth: lineWidth))
  }

  public func resolve(_ text: Text) -> ResolvedText {
    ResolvedText(text: text)
  }

  public func resolve(_ image: Image) -> ResolvedImage {
    ResolvedImage(image: image)
  }

  public mutating func draw(_ text: Text, at point: CGPoint, anchor: UnitPoint = .center) {
    draw(resolve(text), at: point, anchor: anchor)
  }

  public mutating func draw(_ text: ResolvedText, at point: CGPoint, anchor: UnitPoint = .center) {
    let pt = transformPoint(point)
    var el = text.text._makeElement(path: ViewPath())
    el.props.opacity *= opacity
    let rotDeg = atan2(mb, ma) * 180.0 / .pi
    if abs(rotDeg) > 1e-4 { el.props.rotation = rotDeg }
    let w = max(20.0, Double(el.props.text.count) * Double((el.props.font ?? .body).size) * 0.65)
    let h = Double((el.props.font ?? .body).size) * 1.35
    let ox = Double(pt.x) - w * anchor.x
    let oy = Double(pt.y) - h * anchor.y
    var wrap = NodeProps()
    wrap.offsetX = ox
    wrap.offsetY = oy
    wrap.alignment = .topLeading
    wrap.fillWidth = true
    wrap.fillHeight = true
    elements.append(Element(kind: .frame, props: wrap, children: [el]))
  }

  public mutating func draw(_ text: Text, in rect: CGRect) {
    draw(resolve(text), in: rect)
  }

  public mutating func draw(_ text: ResolvedText, in rect: CGRect) {
    let origin = transformPoint(rect.origin)
    let sx = hypot(ma, mb)
    let sy = hypot(mc, md)
    var el = text.text._makeElement(path: ViewPath())
    el.props.opacity *= opacity
    el.props.frameWidth = Double(rect.width) * sx
    el.props.frameHeight = Double(rect.height) * sy
    var wrap = NodeProps()
    wrap.offsetX = Double(origin.x)
    wrap.offsetY = Double(origin.y)
    wrap.alignment = .topLeading
    wrap.fillWidth = true
    wrap.fillHeight = true
    elements.append(Element(kind: .frame, props: wrap, children: [el]))
  }

  public mutating func draw(_ image: Image, in rect: CGRect, style: FillStyle = FillStyle()) {
    draw(resolve(image), in: rect, style: style)
  }

  public mutating func draw(_ image: ResolvedImage, in rect: CGRect, style: FillStyle = FillStyle()) {
    let origin = transformPoint(rect.origin)
    let sx = hypot(ma, mb)
    let sy = hypot(mc, md)
    var el = image.image.resizable()._makeElement(path: ViewPath())
    el.props.opacity *= opacity
    el.props.frameWidth = Double(rect.width) * sx
    el.props.frameHeight = Double(rect.height) * sy
    var wrap = NodeProps()
    wrap.offsetX = Double(origin.x)
    wrap.offsetY = Double(origin.y)
    wrap.alignment = .topLeading
    wrap.fillWidth = true
    wrap.fillHeight = true
    elements.append(Element(kind: .frame, props: wrap, children: [el]))
  }

  public mutating func draw(_ image: Image, at point: CGPoint, anchor: UnitPoint = .center) {
    let resolved = resolve(image)
    let s = resolved.size
    let rect = CGRect(
      x: point.x - s.width * anchor.x,
      y: point.y - s.height * anchor.y,
      width: s.width,
      height: s.height
    )
    draw(resolved, in: rect)
  }

  public mutating func drawLayer(content: (inout GraphicsContext) throws -> Void) rethrows {
    var sub = GraphicsContext(size: canvasSize)
    sub.ma = ma; sub.mb = mb; sub.mc = mc; sub.md = md; sub.tx = tx; sub.ty = ty
    sub.opacity = 1.0
    sub.clipPath = nil
    try content(&sub)
    var groupProps = NodeProps()
    groupProps.opacity = opacity
    groupProps.fillWidth = true
    groupProps.fillHeight = true
    groupProps.compositingGroup = true
    var group = Element(kind: .zStack, props: groupProps, children: sub.elements)
    if let subClip = sub.clipPath {
      group.clipPathBuilder = { _ in subClip }
    }
    elements.append(group)
  }

  public mutating func clip(
    to path: Path, style: FillStyle = FillStyle(), options: ClipOptions = ClipOptions()
  ) {
    clipPath = path.transformed(a: ma, b: mb, c: mc, d: md, tx: tx, ty: ty)
  }

  public mutating func addFilter(_ filter: Filter, options: FilterOptions = FilterOptions()) {}

  public mutating func draw(_ slice: Text.Layout.RunSlice, options: DrawingOptions = []) {
    guard !slice.text.isEmpty else { return }
    draw(Text(verbatim: slice.text), in: slice.typographicBounds)
  }

  public mutating func draw(_ run: Text.Layout.Run, options: DrawingOptions = []) {
    for slice in run {
      draw(slice, options: options)
    }
  }

  public mutating func draw(_ line: Text.Layout.Line, options: DrawingOptions = []) {
    for run in line {
      draw(run, options: options)
    }
  }
}
public struct Canvas: View, _PrimitiveView {
  public typealias Body = Never
  let renderer: (inout GraphicsContext, CGSize) -> Void
  public init(renderer: @escaping (inout GraphicsContext, CGSize) -> Void) {
    self.renderer = renderer
  }
  public var body: Never { fatalError() }
  func _makeElement(path: ViewPath) -> Element {
    var p = NodeProps()
    p.fillWidth = true
    p.fillHeight = true
    var e = Element(kind: .geometry, props: p)
    e.geometryBuilder = { rect in
      var context = GraphicsContext(size: rect.size)
      renderer(&context, rect.size)
      var result = Element(kind: .zStack, children: context.elements)
      if let clip = context.clipPath { result.clipPathBuilder = { _ in clip } }
      return result
    }
    return e
  }
}
