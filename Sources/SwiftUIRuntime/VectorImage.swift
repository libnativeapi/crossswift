import Foundation

/// SVG path geometry for bundled template images. Parsing is cached by URL.
/// Supports the SVG path grammar, including elliptical arcs and smooth curves.
public struct VectorLayer {
  public let path: Path
  public let fill: Color?
  public let stroke: Color?
  public let strokeWidth: Double

  public init(path: Path, fill: Color?, stroke: Color?, strokeWidth: Double) {
    self.path = path
    self.fill = fill
    self.stroke = stroke
    self.strokeWidth = strokeWidth
  }
}

public struct VectorImage {
  public let bounds: CGRect
  public let layers: [VectorLayer]
  public let strokeWidth: Double

  public var paths: [Path] { layers.map(\.path) }

  package init(bounds: CGRect, paths: [Path], strokeWidth: Double = 0) {
    self.bounds = bounds
    self.strokeWidth = strokeWidth
    self.layers = paths.map { p in
      if strokeWidth > 0 {
        VectorLayer(path: p, fill: nil, stroke: .black, strokeWidth: strokeWidth)
      } else {
        VectorLayer(path: p, fill: .black, stroke: nil, strokeWidth: 0)
      }
    }
  }

  package init(bounds: CGRect, layers: [VectorLayer], strokeWidth: Double = 0) {
    self.bounds = bounds
    self.layers = layers
    self.strokeWidth = strokeWidth
  }
  private static let lock = NSLock()
  nonisolated(unsafe) package static var cache: [String: VectorImage] = [:]
  nonisolated(unsafe) package static var symbolDefinitions: [String: (viewBox: CGRect, strokeWidth: Double, paths: [String])] = [:]

  package static func registerSymbol(
    _ name: String,
    viewBox: CGRect = CGRect(x: 0, y: 0, width: 24, height: 24),
    strokeWidth: Double = 2.0,
    paths: [String]
  ) {
    symbolDefinitions[name] = (viewBox, strokeWidth, paths)
  }

  private static func strippedSymbolVariant(_ name: String) -> String {
    name
      .replacingOccurrences(of: ".filled", with: "")
      .replacingOccurrences(of: ".fill", with: "")
      .replacingOccurrences(of: ".inverse", with: "")
  }

  package static func hasSymbol(_ name: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    ensureBuiltinSFSymbolsRegistered()
    if symbolDefinitions[name] != nil { return true }
    let stripped = strippedSymbolVariant(name)
    return symbolDefinitions[stripped] != nil
  }

  package static func loadSymbol(_ rawName: String) -> VectorImage? {
    lock.lock()
    defer { lock.unlock() }
    ensureBuiltinSFSymbolsRegistered()
    let key = "sf://" + rawName
    if let cached = cache[key] { return cached }
    let def =
      symbolDefinitions[rawName]
      ?? symbolDefinitions[strippedSymbolVariant(rawName)]
      ?? symbolDefinitions["circle"]
    guard let def else { return nil }
    let img = VectorImage(bounds: def.viewBox, paths: def.paths.map { parse($0) }, strokeWidth: def.strokeWidth)
    cache[key] = img
    return img
  }

  public static func load(_ file: String) -> VectorImage? {
    if file.hasPrefix("sf://") {
      return loadSymbol(String(file.dropFirst(5)))
    }
    lock.lock()
    if let cached = cache[file] {
      lock.unlock()
      return cached
    }
    lock.unlock()
    if file.lowercased().hasSuffix(".pdf") {
      guard let image = PDFVectorParser.parse(filePath: file) else { return nil }
      lock.lock()
      cache[file] = image
      lock.unlock()
      return image
    }
    guard let source = try? String(contentsOfFile: file, encoding: .utf8) else { return nil }
    func attribute(_ name: String, in fragment: String) -> String? {
      let pattern = "(?:^|\\s)" + name + "\\s*=\\s*[\"']([^\"']*)[\"']"
      guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: fragment, range: NSRange(fragment.startIndex..., in: fragment)),
            let range = Range(match.range(at: 1), in: fragment)
      else { return nil }
      return String(fragment[range])
    }
    let box =
      attribute("viewBox", in: source)?.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap {
        Double($0)
      } ?? []
    guard box.count == 4, box[2] > 0, box[3] > 0 else { return nil }

    let svgTag: String = {
      guard let regex = try? NSRegularExpression(pattern: "<svg\\b[^>]*>"),
            let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
            let range = Range(match.range, in: source)
      else { return "" }
      return String(source[range])
    }()
    let defaultFillAttr = attribute("fill", in: svgTag)

    var layers: [VectorLayer] = []
    if let pathRegex = try? NSRegularExpression(pattern: "<path\\b[^>]*/?>") {
      let matches = pathRegex.matches(in: source, range: NSRange(source.startIndex..., in: source))
      for match in matches {
        guard let range = Range(match.range, in: source) else { continue }
        let tag = String(source[range])
        guard let d = attribute("d", in: tag) else { continue }
        let fillAttr = attribute("fill", in: tag) ?? defaultFillAttr
        let fillColor: Color?
        if let fillAttr {
          fillColor = parseSVGColor(fillAttr)
        } else {
          // SVG default fill is black when omitted.
          fillColor = .black
        }
        let strokeAttr = attribute("stroke", in: tag)
        let strokeColor = strokeAttr.flatMap(parseSVGColor)
        let strokeW: Double
        if strokeColor != nil {
          strokeW = attribute("stroke-width", in: tag).flatMap(Double.init) ?? 1.0
        } else {
          strokeW = 0
        }
        layers.append(VectorLayer(
          path: parse(d),
          fill: fillColor,
          stroke: strokeColor,
          strokeWidth: strokeW
        ))
      }
    }

    let image = VectorImage(
      bounds: CGRect(x: box[0], y: box[1], width: box[2], height: box[3]),
      layers: layers,
      strokeWidth: 0
    )
    lock.lock()
    cache[file] = image
    lock.unlock()
    return image
  }

  private static func parseSVGColor(_ raw: String) -> Color? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if trimmed.isEmpty || trimmed == "none" || trimmed == "transparent" {
      return nil
    }
    if trimmed == "currentcolor" || trimmed == "black" {
      return .black
    }
    if trimmed == "white" {
      return .white
    }
    if trimmed.hasPrefix("#") {
      let hex = String(trimmed.dropFirst())
      if hex.count == 3, let val = UInt32(hex, radix: 16) {
        let r = Double((val >> 8) & 0xF) / 15.0
        let g = Double((val >> 4) & 0xF) / 15.0
        let b = Double(val & 0xF) / 15.0
        return Color(red: r, green: g, blue: b)
      }
      if hex.count == 6, let val = UInt32(hex, radix: 16) {
        let r = Double((val >> 16) & 0xFF) / 255.0
        let g = Double((val >> 8) & 0xFF) / 255.0
        let b = Double(val & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
      }
      if hex.count == 8, let val = UInt32(hex, radix: 16) {
        let r = Double((val >> 24) & 0xFF) / 255.0
        let g = Double((val >> 16) & 0xFF) / 255.0
        let b = Double((val >> 8) & 0xFF) / 255.0
        let a = Double(val & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b, opacity: a)
      }
    }
    return .black
  }

  private static func parse(_ source: String) -> Path {
    let regex = try! NSRegularExpression(
      pattern: "[a-zA-Z]|[-+]?(?:[0-9]*[.])?[0-9]+(?:[eE][-+]?[0-9]+)?")
    let tokens = regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).map {
      String(source[Range($0.range, in: source)!])
    }
    var i = 0
    var command = "M"
    var previous = ""
    var point = CGPoint.zero
    var start = CGPoint.zero
    var control = CGPoint.zero
    var path = Path()
    func number() -> Double {
      defer { i += 1 }
      return Double(tokens[i]) ?? 0
    }
    func isCommand(_ token: String) -> Bool { token.count == 1 && token.first!.isLetter }
    while i < tokens.count {
      if isCommand(tokens[i]) {
        command = tokens[i]
        i += 1
      }
      let upper = command.uppercased()
      let relative = command != upper
      let count: Int
      switch upper {
      case "Z": count = 0
      case "H", "V": count = 1
      case "M", "L", "T": count = 2
      case "S", "Q": count = 4
      case "C": count = 6
      case "A": count = 7
      default: return path
      }
      if count > 0 && (i + count > tokens.count || tokens[i..<i + count].contains(where: isCommand))
      {
        return path
      }
      let base = relative ? point : .zero
      func pair() -> CGPoint {
        let x = number()
        let y = number()
        return CGPoint(x: x + base.x, y: y + base.y)
      }
      switch upper {
      case "M":
        point = pair()
        start = point
        path.move(to: point)
        command = relative ? "l" : "L"
      case "L":
        point = pair()
        path.addLine(to: point)
      case "H":
        point.x = number() + base.x
        path.addLine(to: point)
      case "V":
        point.y = number() + base.y
        path.addLine(to: point)
      case "C":
        let c1 = pair()
        let c2 = pair()
        let end = pair()
        path.addCurve(to: end, control1: c1, control2: c2)
        control = c2
        point = end
      case "S":
        let c1 =
          (previous == "C" || previous == "S")
          ? CGPoint(x: 2 * point.x - control.x, y: 2 * point.y - control.y) : point
        let c2 = pair()
        let end = pair()
        path.addCurve(to: end, control1: c1, control2: c2)
        control = c2
        point = end
      case "Q", "T":
        let c: CGPoint
        if upper == "Q" {
          c = pair()
        } else {
          c =
            (previous == "Q" || previous == "T")
            ? CGPoint(x: 2 * point.x - control.x, y: 2 * point.y - control.y) : point
        }
        let end = pair()
        path.addCurve(
          to: end,
          control1: CGPoint(
            x: point.x + (c.x - point.x) * 2 / 3, y: point.y + (c.y - point.y) * 2 / 3),
          control2: CGPoint(x: end.x + (c.x - end.x) * 2 / 3, y: end.y + (c.y - end.y) * 2 / 3))
        control = c
        point = end
      case "A":
        let rx = number()
        let ry = number()
        let rotation = number()
        let large = number() != 0
        let sweep = number() != 0
        let end = pair()
        arc(
          &path, from: point, to: end, rx: rx, ry: ry, rotation: rotation, large: large,
          sweep: sweep)
        point = end
      case "Z":
        path.closeSubpath()
        point = start
        command = "M"
      default: break
      }
      previous = upper
    }
    return path
  }
  private static func arc(
    _ path: inout Path, from p: CGPoint, to q: CGPoint, rx rX: Double, ry rY: Double,
    rotation: Double, large: Bool, sweep: Bool
  ) {
    var rx = abs(rX)
    var ry = abs(rY)
    if rx == 0 || ry == 0 {
      path.addLine(to: q)
      return
    }
    if p == q { return }
    let phi = rotation * .pi / 180
    let c = cos(phi)
    let s = sin(phi)
    let dx = (p.x - q.x) / 2
    let dy = (p.y - q.y) / 2
    let x = c * dx + s * dy
    let y = -s * dx + c * dy
    let lambda = x * x / (rx * rx) + y * y / (ry * ry)
    if lambda > 1 {
      rx *= sqrt(lambda)
      ry *= sqrt(lambda)
    }
    let numerator = max(0, rx * rx * ry * ry - rx * rx * y * y - ry * ry * x * x)
    let denominator = rx * rx * y * y + ry * ry * x * x
    let factor = (large == sweep ? -1.0 : 1.0) * sqrt(numerator / max(denominator, 1e-20))
    let cxp = factor * rx * y / ry
    let cyp = -factor * ry * x / rx
    let cx = c * cxp - s * cyp + (p.x + q.x) / 2
    let cy = s * cxp + c * cyp + (p.y + q.y) / 2
    let a = atan2((y - cyp) / ry, (x - cxp) / rx)
    let end = atan2((-y - cyp) / ry, (-x - cxp) / rx)
    var delta = end - a
    if sweep && delta < 0 { delta += 2 * .pi }
    if !sweep && delta > 0 { delta -= 2 * .pi }
    let pieces = max(1, Int(ceil(abs(delta) / (.pi / 2))))
    let step = delta / Double(pieces)
    func transform(_ x: Double, _ y: Double) -> CGPoint {
      CGPoint(x: cx + c * rx * x - s * ry * y, y: cy + s * rx * x + c * ry * y)
    }
    for i in 0..<pieces {
      let a = a + Double(i) * step
      let b = a + step
      let k = 4 / 3 * tan(step / 4)
      path.addCurve(
        to: transform(cos(b), sin(b)),
        control1: transform(cos(a) - k * sin(a), sin(a) + k * cos(a)),
        control2: transform(cos(b) + k * sin(b), sin(b) - k * cos(b)))
    }
  }

  package func toSVG() -> String {
    let minX = bounds.minX
    let minY = bounds.minY
    let width = bounds.width
    let height = bounds.height
    var lines: [String] = [
      "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"\(minX) \(minY) \(width) \(height)\">"
    ]
    for path in paths {
      let d = path.svgData
      guard !d.isEmpty else { continue }
      if strokeWidth > 0 {
        lines.append(
          "  <path d=\"\(d)\" fill=\"none\" stroke=\"currentColor\" stroke-width=\"\(strokeWidth)\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>"
        )
      } else {
        lines.append("  <path d=\"\(d)\" fill=\"currentColor\" fill-rule=\"evenodd\"/>")
      }
    }
    lines.append("</svg>")
    return lines.joined(separator: "\n") + "\n"
  }
}

extension Path {
  package var svgData: String {
    var result = ""
    var index = 0
    while index < commands.count {
      let command: String
      let count: Int
      switch commands[index] {
      case 0: (command, count) = ("M", 2)
      case 1: (command, count) = ("L", 2)
      case 2: (command, count) = ("C", 6)
      case 3: (command, count) = ("Z", 0)
      default: return result
      }
      let end = index + 1 + count
      guard end <= commands.count else { break }
      result += command
      for coordinate in commands[(index + 1)..<end] { result += " \(coordinate)" }
      index = end
    }
    return result
  }
}
