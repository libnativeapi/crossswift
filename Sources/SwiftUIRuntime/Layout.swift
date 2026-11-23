/// Deterministic metrics for tests and backends without a text measurer.
/// Windows supplies real font measurement to LayoutEngine instead.
import Foundation

#if (os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)) && canImport(CoreGraphics)
  import CoreGraphics
#endif

/// A proposal-based layout shared by deterministic tests and native drawing.
public struct TextMetrics: Equatable {
  public var characterWidth: Double
  public var lineHeight: Double
  public var buttonHorizontalPadding: Double
  public var buttonVerticalPadding: Double

  public init(
    characterWidth: Double = 8,
    lineHeight: Double = 20,
    buttonHorizontalPadding: Double = 12,
    buttonVerticalPadding: Double = 6
  ) {
    self.characterWidth = characterWidth
    self.lineHeight = lineHeight
    self.buttonHorizontalPadding = buttonHorizontalPadding
    self.buttonVerticalPadding = buttonVerticalPadding
  }

  public static let `default` = TextMetrics()
}
public struct LayoutEngine {
  private final class Cache {
    enum Flexibility { case horizontal, vertical, both, neither }
    struct TextKey: Hashable {
      let text: String
      let font: Font?
      let width: Double?
      let limit: Int?
      let spacing: Double
      let truncation: Text.TruncationMode
    }
    struct TextLayout {
      let text: String
      let size: Size
    }
    struct Placement {
      let offered: Rect
      let element: Element
    }
    struct Identity {
      let kind: ElementKind
      let props: NodeProps
      let children: [Int]
      let id: Int
      let revision: Int
    }
    var nextID = 1
    var identities: [Int: Identity] = [:]
    var measurements: [Pass.Key: Size] = [:]
    var flexibility: [Int: Flexibility] = [:]
    var placements: [Int: Placement] = [:]
    var geometryContent: [Int: Element] = [:]
    var geometryNormalized: [Int: Element] = [:]
    var text: [TextKey: TextLayout] = [:]
    var timings: [String: Double] = [:]
    var passes = 0
    func reset() {
      identities.removeAll()
      measurements.removeAll()
      flexibility.removeAll()
      placements.removeAll()
      geometryContent.removeAll()
      geometryNormalized.removeAll()
      text.removeAll()
    }
  }
  private let cache = Cache()
  private final class Pass {
    let prunes: Bool
    let animator: LayoutAnimator?
    let evaluations: EvaluationGraph?
    let mountedGeometryChildren: [Int: Element]
    let renderPass: Int
    let now: TimeInterval
    init(
      prunes: Bool,
      animator: LayoutAnimator? = nil,
      evaluations: EvaluationGraph? = nil,
      mountedGeometryChildren: [Int: Element] = [:],
      renderPass: Int = 0,
      now: TimeInterval = 0
    ) {
      self.prunes = prunes
      self.animator = animator
      self.evaluations = evaluations
      self.mountedGeometryChildren = mountedGeometryChildren
      self.renderPass = renderPass
      self.now = now
    }
    struct Key: Hashable {
      let id: Int
      let width: CGFloat?, height: CGFloat?
    }
    var liveViews = Set<Int>()
    var liveMeasurements = Set<Int>()
    var geometryMilliseconds = 0.0
    var activeScrollContentOrigin: CGPoint?
    var activeScrollViewportSize: Size?
  }
  private var pass: Pass?
  public var lastTimings: [String: Double] { cache.timings }
  public var metrics: TextMetrics { didSet { cache.reset() } }
  public var textMeasurer: ((String, Font) -> Size)? { didSet { cache.reset() } }
  public init(metrics: TextMetrics = .default, textMeasurer: ((String, Font) -> Size)? = nil) {
    self.metrics = metrics
    self.textMeasurer = textMeasurer
  }
  package func invalidateMeasurements() { cache.reset() }
  public func measuredSize(of element: Element) -> Size { measure(element) }
  public func sizeThatFits(_ element: Element, proposal: ProposedViewSize) -> CGSize {
    let s = measure(element, proposal)
    return CGSize(width: s.width, height: s.height)
  }
  /// Re-run opaque layout placement before retaining translated content. A
  /// custom Layout may depend on bounds.origin; never assume it is invariant.
  func canTranslateScroll(_ element: Element, dx: Double, dy: Double) -> Bool {
    if !element.hasDynamicLayout { return true }
    if element.geometrySnapshot?.dependsOnPosition == true { return false }
    if element.kind == .presentation && element.children.count > 1 { return false }
    if let layout = element.layout, !layout.translatesWithBounds {
      var engine = self
      engine.pass = Pass(prunes: false)
      let bounds = CGRect(
        x: element.frame.minX + dx, y: element.frame.minY + dy,
        width: element.frame.width, height: element.frame.height)
      let next = layout.placements(bounds, children: element.children, engine: engine)
      guard next.count == element.customLayoutFrames.count else { return false }
      for (actual, old) in zip(next, element.customLayoutFrames) {
        let expected = old.offsetBy(dx: dx, dy: dy)
        if abs(actual.minX - expected.minX) > 1e-8 || abs(actual.minY - expected.minY) > 1e-8
          || abs(actual.width - expected.width) > 1e-8
          || abs(actual.height - expected.height) > 1e-8
        {
          return false
        }
      }
    }
    return element.children.allSatisfy { canTranslateScroll($0, dx: dx, dy: dy) }
  }
  public func layout(root: inout Element, in size: Size) {
    layout(root: &root, in: size, animator: nil, renderPass: 0, now: 0)
  }
  func layout(
    root: inout Element,
    in size: Size,
    animator: LayoutAnimator?,
    evaluations: EvaluationGraph? = nil,
    mountedGeometryChildren: [Int: Element] = [:],
    renderPass: Int,
    now: TimeInterval
  ) {
    var engine = self
    cache.passes += 1
    // IDs are never recycled. Reclaim obsolete proposals and snapshots in
    // bounded batches instead of rebuilding three dictionaries on every tick.
    engine.pass = Pass(
      prunes: cache.passes % 8 == 0,
      animator: animator,
      evaluations: evaluations,
      mountedGeometryChildren: mountedGeometryChildren,
      renderPass: renderPass,
      now: now)
    var started = Date.timeIntervalSinceReferenceDate
    engine.identify(&root)
    cache.timings["identify"] = (Date.timeIntervalSinceReferenceDate - started) * 1000
    started = Date.timeIntervalSinceReferenceDate
    engine.layoutRoot(root: &root, in: size)
    cache.timings["place"] = (Date.timeIntervalSinceReferenceDate - started) * 1000
    cache.timings["geometry"] = engine.pass?.geometryMilliseconds ?? 0
    started = Date.timeIntervalSinceReferenceDate
    if engine.pass!.prunes {
      for key in cache.identities.keys.filter({ !engine.pass!.liveViews.contains($0) }) {
        cache.identities.removeValue(forKey: key)
      }
      for key in cache.geometryNormalized.keys.filter({ !engine.pass!.liveViews.contains($0) }) {
        cache.geometryNormalized.removeValue(forKey: key)
      }
      for key in cache.measurements.keys.filter({ !engine.pass!.liveMeasurements.contains($0.id) })
      {
        cache.measurements.removeValue(forKey: key)
      }
      for key in cache.flexibility.keys.filter({ !engine.pass!.liveMeasurements.contains($0) }) {
        cache.flexibility.removeValue(forKey: key)
      }
      for key in cache.placements.keys.filter({ !engine.pass!.liveMeasurements.contains($0) }) {
        cache.placements.removeValue(forKey: key)
      }
      for key in cache.geometryContent.keys.filter({ !engine.pass!.liveMeasurements.contains($0) })
      {
        cache.geometryContent.removeValue(forKey: key)
      }
    }
    cache.timings["prune"] = (Date.timeIntervalSinceReferenceDate - started) * 1000
  }
  private func identify(_ element: inout Element, previousGeometry: Element? = nil) {
    guard let pass else { return }
    if element.reusesLayout {
      retainIdentities(element)
      return
    }
    let previous = previousGeometry.flatMap { $0.kind == element.kind ? $0 : nil }
    var dynamic =
      element.geometryBuilder != nil || element.kind == .presentation || element.layout != nil
      || element.scrollTarget != nil || !element.scrollGeometryHandlers.isEmpty
      || !element.geometryChangeHandlers.isEmpty
    var presentation = element.kind == .presentation
    var preferences =
      element.geometryBuilder != nil || !element.preferences.isEmpty
      || !element.anchorPreferences.isEmpty
      || element.preferenceAction != nil || !element.preferenceTransforms.isEmpty
    for i in element.children.indices {
      let priorChild = previous.flatMap { i < $0.children.count ? $0.children[i] : nil }
      identify(&element.children[i], previousGeometry: priorChild)
      let child = element.children[i]
      dynamic = dynamic || child.hasDynamicLayout
      presentation = presentation || child.hasPresentation
      preferences = preferences || child.hasPreferences
    }
    element.hasDynamicLayout = dynamic
    element.hasPresentation = presentation
    element.hasPreferences = preferences
    let opaqueLayout =
      element.layout != nil || element.horizontalGuide != nil || element.verticalGuide != nil
    if element.evaluationID != 0,
      let previous = cache.identities[element.evaluationID],
      !opaqueLayout || previous.revision == element.evaluationRevision,
      previous.kind == element.kind, previous.children.count == element.children.count,
      zip(previous.children, element.children).allSatisfy({ $0 == $1.layoutID }),
      sameSizing(previous.props, element.props)
    {
      element.layoutID = previous.id
    } else if element.evaluationID == 0, let previous, !opaqueLayout,
      previous.layoutID != 0, sameSizing(previous.props, element.props),
      element.kind == .geometry
        || (previous.children.count == element.children.count
          && zip(previous.children, element.children).allSatisfy { $0.layoutID == $1.layoutID })
    {
      element.layoutID = previous.layoutID
    } else {
      element.layoutID = cache.nextID
      cache.nextID += 1
      if element.evaluationID != 0 {
        cache.identities[element.evaluationID] = Cache.Identity(
          kind: element.kind, props: element.props, children: element.children.map(\.layoutID),
          id: element.layoutID,
          revision: element.evaluationRevision)
      }
    }
    if pass.prunes {
      pass.liveViews.insert(element.evaluationID)
      pass.liveMeasurements.insert(element.layoutID)
    }
  }
  private func retainIdentities(_ element: Element) {
    guard pass?.prunes == true else { return }
    pass?.liveViews.insert(element.evaluationID)
    pass?.liveMeasurements.insert(element.layoutID)
    for child in element.children { retainIdentities(child) }
  }
  private func sameSizing(_ a: NodeProps, _ b: NodeProps) -> Bool {
    a.text == b.text && a.font == b.font && a.lineLimit == b.lineLimit
      && a.lineSpacing == b.lineSpacing && a.truncationMode == b.truncationMode
      && a.frameWidth == b.frameWidth && a.frameHeight == b.frameHeight && a.minWidth == b.minWidth
      && a.minHeight == b.minHeight && a.maxWidth == b.maxWidth && a.maxHeight == b.maxHeight
      && a.idealWidth == b.idealWidth && a.idealHeight == b.idealHeight
      && a.fixedWidth == b.fixedWidth && a.fixedHeight == b.fixedHeight
      && a.fillWidth == b.fillWidth && a.fillHeight == b.fillHeight && a.padding == b.padding
      && a.spacing == b.spacing && a.flex == b.flex && a.spacerMinLength == b.spacerMinLength
      && a.layoutPriority == b.layoutPriority && a.scrollAxes == b.scrollAxes
      && a.gridUnsizedAxes == b.gridUnsizedAxes && a.visible == b.visible
      && a.multiline == b.multiline && a.offsetX == b.offsetX && a.offsetY == b.offsetY
      && a.scrollOffset == b.scrollOffset && a.scrollContentInsets == b.scrollContentInsets
      && a.alignment == b.alignment
      && a.horizontalAlignment == b.horizontalAlignment
      && a.verticalAlignment == b.verticalAlignment && a.coordinateSpace == b.coordinateSpace
      && a.layerBehind == b.layerBehind
      && a.hasAspectConstraint == b.hasAspectConstraint && a.aspectRatio == b.aspectRatio
      && a.aspectFit == b.aspectFit
      && a.intrinsicImageWidth == b.intrinsicImageWidth
      && a.intrinsicImageHeight == b.intrinsicImageHeight
  }
  private func layoutRoot(root: inout Element, in size: Size) {
    let natural = measure(root, ProposedViewSize(width: size.width, height: size.height))
    let extent =
      root.isContainer
      ? size : Size(width: min(natural.width, size.width), height: min(natural.height, size.height))
    place(
      &root,
      in: Rect(
        x: 0, y: 0, width: root.props.frameWidth ?? extent.width,
        height: root.props.frameHeight ?? extent.height))
  }
  private func textSize(_ text: String, _ font: Font?) -> Size {
    textMeasurer?(text, font ?? .body)
      ?? Size(
        width: Double(text.count) * metrics.characterWidth,
        height: font.map { Double($0.size) } ?? metrics.lineHeight)
  }
  private func textLayout(_ props: NodeProps, width: Double?) -> Cache.TextLayout {
    let effectiveWidth = props.fixedWidth ? nil : width
    if !props.text.utf8.contains(10) {
      let natural = textSize(props.text, props.font)
      if effectiveWidth == nil || natural.width <= effectiveWidth! {
        return Cache.TextLayout(text: props.text, size: natural)
      }
    }
    let key = Cache.TextKey(
      text: props.text, font: props.font, width: effectiveWidth,
      limit: props.lineLimit, spacing: props.lineSpacing, truncation: props.truncationMode)
    if let cached = cache.text[key] { return cached }
    let wrapped = lines(props, width: key.width)
    var size = Size(height: Double(max(0, wrapped.count - 1)) * props.lineSpacing)
    for line in wrapped {
      let measured = textSize(line, props.font)
      size.width = max(size.width, measured.width)
      size.height += measured.height
    }
    let result = Cache.TextLayout(text: wrapped.joined(separator: "\n"), size: size)
    if cache.text.count >= 8192 { cache.text.removeAll(keepingCapacity: true) }
    cache.text[key] = result
    return result
  }
  private func lines(_ p: NodeProps, width: Double?) -> [String] {
    var result: [String] = []
    let paragraphs: [String] =
      p.text.utf8.contains(10)
      ? p.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
      : [p.text]
    for paragraph in paragraphs {
      guard let width, width > 0, !p.fixedWidth, p.lineLimit != 1,
        textSize(paragraph, p.font).width > width
      else {
        result.append(paragraph)
        continue
      }
      var line = ""
      let words = paragraph.split(separator: " ", omittingEmptySubsequences: false)
      for wordSlice in words {
        let word = String(wordSlice)
        let next = line.isEmpty ? word : line + " " + word
        if !line.isEmpty && textSize(next, p.font).width > width {
          result.append(line)
          line = word
        } else {
          line = next
        }
        while textSize(line, p.font).width > width && line.count > 1 {
          let chars = Array(line)
          var lo = 1
          var hi = chars.count - 1
          while lo < hi {
            let mid = (lo + hi + 1) / 2
            if textSize(String(chars[..<mid]), p.font).width <= width {
              lo = mid
            } else {
              hi = mid - 1
            }
          }
          result.append(String(chars[..<lo]))
          line = String(chars[lo...])
        }
      }
      result.append(line)
    }
    if let limit = p.lineLimit, result.count > limit {
      result = Array(result.prefix(max(1, limit)))
    }
    if let width, p.lineLimit != nil, !p.fixedWidth {
      result = result.map { line in
        guard textSize(line, p.font).width > width else { return line }
        let chars = Array(line)
        var lo = 0
        var hi = chars.count
        if p.truncationMode == .head {
          while lo < hi {
            let mid = (lo + hi + 1) / 2
            let candidate = "…" + String(chars[(chars.count - mid)...])
            if textSize(candidate, p.font).width <= width {
              lo = mid
            } else {
              hi = mid - 1
            }
          }
          return "…" + String(chars[(chars.count - lo)...])
        } else {
          while lo < hi {
            let mid = (lo + hi + 1) / 2
            let candidate = String(chars[..<mid]) + "…"
            if textSize(candidate, p.font).width <= width {
              lo = mid
            } else {
              hi = mid - 1
            }
          }
          return String(chars[..<lo]) + "…"
        }
      }
    }
    return result
  }
  func measure(_ e: Element, _ proposal: ProposedViewSize = .unspecified) -> Size {
    guard pass != nil, e.layoutID != 0 else { return measureUncached(e, proposal) }
    let key = Pass.Key(id: e.layoutID, width: proposal.width, height: proposal.height)
    if let result = cache.measurements[key] { return result }
    let result = measureUncached(e, proposal)
    cache.measurements[key] = result
    return result
  }
  private func measureUncached(_ e: Element, _ proposal: ProposedViewSize) -> Size {
    let p = e.props
    let width: Double? =
      p.frameWidth ?? proposal.width.map {
        min(p.maxWidth ?? .infinity, max(p.minWidth ?? 0, Double($0)))
      } ?? p.idealWidth
    let height: Double? =
      p.frameHeight ?? proposal.height.map {
        min(p.maxHeight ?? .infinity, max(p.minHeight ?? 0, Double($0)))
      } ?? p.idealHeight
    let offer = ProposedViewSize(
      width: p.fixedWidth ? nil : width.map { CGFloat($0) },
      height: p.fixedHeight ? nil : height.map { CGFloat($0) })
    let knownWidth: Double? =
      p.gridUnsizedAxes.contains(.horizontal) ? 0
      : p.frameWidth
        ?? (p.minWidth != nil && p.minWidth == p.maxWidth ? p.minWidth : nil)
        ?? (p.fillWidth
          ? offer.width.flatMap {
            let w = Double($0)
            return w.isFinite ? min(p.maxWidth ?? .infinity, max(p.minWidth ?? 0, w)) : nil
          } : nil)
    let knownHeight: Double? =
      p.gridUnsizedAxes.contains(.vertical) ? 0
      : p.frameHeight
        ?? (p.minHeight != nil && p.minHeight == p.maxHeight ? p.minHeight : nil)
        ?? (p.fillHeight
          ? offer.height.flatMap {
            let h = Double($0)
            return h.isFinite ? min(p.maxHeight ?? .infinity, max(p.minHeight ?? 0, h)) : nil
          } : nil)
    if let knownWidth, let knownHeight {
      return Size(
        width: knownWidth.isFinite ? max(0, knownWidth) : 0,
        height: knownHeight.isFinite ? max(0, knownHeight) : 0)
    }
    var size = Size.zero
    switch e.kind {
    case .text, .button:
      var textProps = p
      if e.kind == .button, textProps.font == nil, textMeasurer != nil {
        textProps.font = .callout
      }
      size = textLayout(textProps, width: e.kind == .button ? nil : offer.width.map { Double($0) }).size
      if e.kind == .button {
        size.width += metrics.buttonHorizontalPadding * 2
        if textMeasurer != nil {
          size.height = max(24, size.height + 10)
        } else {
          size.height += metrics.buttonVerticalPadding * 2
        }
      }
    case .textField:
      size = textSize(p.text.isEmpty ? " " : p.text, p.font)
      size.width = offer.width.map { Double($0) } ?? max(80, size.width)
      #if os(Android) || CROSS_SWIFTUI_HARMONY
      size.height = max(size.height + 28, 56)
      #else
      if textMeasurer == nil { size.height = max(size.height, 20) }
      #endif
      if p.multiline { size.height *= 3 }
    case .image:
      if let iw = p.idealWidth ?? p.intrinsicImageWidth,
         let ih = p.idealHeight ?? p.intrinsicImageHeight
      {
        size = Size(width: iw, height: ih)
      } else if p.imagePath.hasPrefix("sf://") {
        let s = Double(p.font?.size ?? 16)
        size = Size(width: s, height: s)
      } else if (p.imagePath.hasSuffix(".svg") || p.imagePath.hasSuffix(".SVG")
                 || p.imagePath.hasSuffix(".pdf") || p.imagePath.hasSuffix(".PDF")),
                let vec = VectorImage.load(p.imagePath), vec.bounds.width > 0, vec.bounds.height > 0
      {
        size = Size(width: Double(vec.bounds.width), height: Double(vec.bounds.height))
      } else {
        size = Size(width: 20, height: 20)
      }
    case .hostedView:
      if let measureFn = e.hostedViewMeasure {
        size = measureFn(offer)
      } else {
        size = Size(width: Double(offer.width ?? 0), height: Double(offer.height ?? 0))
      }
    case .padding:
      let child = ProposedViewSize(
        width: offer.width.map { max(0, $0 - p.padding.horizontal) },
        height: offer.height.map { max(0, $0 - p.padding.vertical) })
      size = e.children.first.map { measure($0, child) } ?? .zero
      size.width += p.padding.horizontal
      size.height += p.padding.vertical
    case .frame:
      if p.hasAspectConstraint, let child = e.children.first {
        let constrained = aspectProposal(p, child: child, offer: offer)
        size = measure(child, constrained)
      } else {
        size = e.children.first.map { measure($0, offer) } ?? .zero
      }
    case .presentation, .layer, .styledButton:
      size = e.children.first.map { measure($0, offer) } ?? .zero
    case .zStack:
      let sizes = e.children.map { measure($0, offer) }
      size = Size(width: sizes.map(\.width).max() ?? 0, height: sizes.map(\.height).max() ?? 0)
    case .geometry: size = Size(width: offer.width ?? 10, height: offer.height ?? 10)
    case .grid:
      let columns = gridColumns(e, proposal: offer)
      let totalWidth =
        columns.reduce(0, +) + Double(max(0, columns.count - 1)) * p.padding.leading
      let heights = e.children.map { row -> Double in
        if row.kind == .container(.horizontal) && !row.children.isEmpty {
          return row.children.enumerated().map { i, cell in
            let colW = i < columns.count ? columns[i] : nil
            return measure(cell, ProposedViewSize(width: colW.map { CGFloat($0) }, height: nil)).height
          }.max() ?? 0
        }
        return measure(row, ProposedViewSize(width: totalWidth > 0 ? CGFloat(totalWidth) : offer.width, height: nil)).height
      }
      size = Size(
        width: totalWidth,
        height: heights.reduce(0, +) + Double(max(0, heights.count - 1)) * p.spacing)
    case .customLayout:
      if let layout = e.layout {
        let result = layout.measure(offer, children: e.children, engine: self)
        size = Size(width: result.width, height: result.height)
      }
    case .scroll:
      let content = ProposedViewSize(
        width: p.scrollAxes.contains(.horizontal) ? nil : offer.width,
        height: p.scrollAxes.contains(.vertical) ? nil : offer.height)
      size = e.children.first.map { measure($0, content) } ?? .zero
      if let width = offer.width {
        size.width = min(Double(width), size.width)
      } else if p.scrollAxes.contains(.horizontal) {
        size.width = 10
      }
      if let height = offer.height {
        size.height = min(Double(height), size.height)
      } else if p.scrollAxes.contains(.vertical) {
        size.height = 10
      }
    case .fragment, .container:
      let horizontal = e.kind == .container(.horizontal)
      let childOffer = ProposedViewSize(
        width: horizontal ? nil : offer.width, height: horizontal ? offer.height : nil)
      let children = e.children
      let spacings = Double(max(0, children.count - 1)) * p.spacing
      var measuredChildren = Array(repeating: Size.zero, count: children.count)
      let stackKey = e.lazyCacheKey
      for i in children.indices where !children[i].props.isLazyPlaceholder {
        let child = children[i]
        let sz: Size
        if child.kind == .spacer {
          sz = horizontal
            ? Size(width: child.props.spacerMinLength, height: 0)
            : Size(width: 0, height: child.props.spacerMinLength)
        } else {
          sz = measure(child, childOffer)
        }
        measuredChildren[i] = sz
        if let stackKey, let itemID = child.explicitID, !child.children.isEmpty {
          LazyHeightCache.shared.record(
            stack: stackKey, item: itemID, height: horizontal ? sz.width : sz.height)
        }
      }
      for i in children.indices where children[i].props.isLazyPlaceholder {
        let child = children[i]
        if let stackKey, let itemID = child.explicitID {
          let est = LazyHeightCache.shared.estimatedHeight(stack: stackKey, item: itemID)
          measuredChildren[i] = horizontal
            ? Size(width: est, height: 0)
            : Size(width: 0, height: est)
        } else {
          measuredChildren[i] = measure(child, childOffer)
        }
      }
      var main =
        measuredChildren.reduce(0) { $0 + (horizontal ? $1.width : $1.height) } + spacings
      if horizontal, let offeredWidth = offer.width, offeredWidth.isFinite {
        let nonFlex = children.indices.filter { i in
          let c = children[i]
          return c.kind != .spacer && c.props.flex <= 0 && !fills(c, horizontal: true)
        }
        let flexIndices = children.indices.filter { i in
          let c = children[i]
          return c.props.flex > 0 || fills(c, horizontal: true)
        }
        let spacerReserve = children.reduce(0.0) { $0 + ($1.kind == .spacer ? $1.props.spacerMinLength : 0) }
        let nonFlexBudget = max(0, Double(offeredWidth) - spacings - spacerReserve)
        let nonFlexNatural = nonFlex.reduce(0.0) { $0 + measuredChildren[$1].width }
        if nonFlexNatural > nonFlexBudget + 0.5 {
          let widths = allocateMainSizes(
            ideals: nonFlex.map { measuredChildren[$0].width },
            priorities: nonFlex.map { children[$0].props.layoutPriority },
            budget: nonFlexBudget)
          for (idx, allocated) in zip(nonFlex, widths)
          where allocated + 0.5 < measuredChildren[idx].width {
            measuredChildren[idx] = measure(
              children[idx],
              ProposedViewSize(width: CGFloat(allocated), height: offer.height))
          }
        }
        if flexIndices.contains(where: { children[$0].kind != .spacer }) {
          let nonFlexUsed = nonFlex.reduce(0.0) { $0 + measuredChildren[$1].width }
          var available = max(0, Double(offeredWidth) - spacings - spacerReserve - nonFlexUsed)
          let distinctFlexPriorities = Array(Set(flexIndices.map { children[$0].props.layoutPriority })).sorted(by: >)
          for tier in distinctFlexPriorities {
            guard available > 1e-6 else { break }
            let tierIndices = flexIndices.filter { children[$0].props.layoutPriority == tier }
            let tierFlex = tierIndices.reduce(0.0) { $0 + max(1, children[$1].props.flex) }
            var used = 0.0
            for idx in tierIndices {
              let c = children[idx]
              let flexWeight = max(1, c.props.flex)
              let rawShare = available * flexWeight / max(1, tierFlex)
              let minSpacer = c.kind == .spacer ? c.props.spacerMinLength : 0
              let capped: Double
              if let maxCap = c.props.maxWidth, maxCap.isFinite {
                capped = min(rawShare, max(0, maxCap - minSpacer))
              } else {
                capped = rawShare
              }
              used += capped
              if c.kind != .spacer {
                let shareWidth = minSpacer + capped
                measuredChildren[idx] = measure(
                  c, ProposedViewSize(width: CGFloat(shareWidth), height: offer.height))
              } else {
                measuredChildren[idx] = Size(width: minSpacer + capped, height: 0)
              }
            }
            available = max(0, available - used)
          }
        }
        if main > Double(offeredWidth) || flexIndices.contains(where: { children[$0].kind != .spacer }) {
          main = min(Double(offeredWidth), measuredChildren.reduce(0) { $0 + $1.width } + spacings)
        }
      }
      let cross = measuredChildren.map { horizontal ? $0.height : $0.width }.max() ?? 0
      size = horizontal ? Size(width: main, height: cross) : Size(width: cross, height: main)
    case .shape, .path, .gradient: size = Size(width: offer.width ?? 0, height: offer.height ?? 0)
    case .spacer, .empty: break
    }
    if p.fillWidth, let width = offer.width, width.isFinite { size.width = width }
    if p.fillHeight, let height = offer.height, height.isFinite { size.height = height }
    if case .container = e.kind {
      if let width = offer.width, fills(e, horizontal: true) { size.width = width }
      if let height = offer.height, fills(e, horizontal: false) { size.height = height }
    }
    size.width = p.frameWidth ?? min(p.maxWidth ?? .infinity, max(p.minWidth ?? 0, size.width))
    size.height = p.frameHeight ?? min(p.maxHeight ?? .infinity, max(p.minHeight ?? 0, size.height))
    if p.gridUnsizedAxes.contains(.horizontal) { size.width = 0 }
    if p.gridUnsizedAxes.contains(.vertical) { size.height = 0 }
    return Size(
      width: size.width.isFinite ? max(0, size.width) : 0,
      height: size.height.isFinite ? max(0, size.height) : 0)
  }
  private func gridColumns(_ e: Element, proposal: ProposedViewSize) -> [Double] {
    let rows = e.children.filter { $0.kind == .container(.horizontal) && !$0.children.isEmpty }
    let count = rows.map { $0.children.count }.max() ?? 0
    guard count > 0 else { return [] }
    let ideal: [Double] = (0..<count).map { i in
      rows.compactMap { row -> Double? in
        guard i < row.children.count else { return nil }
        return measure(row.children[i], ProposedViewSize(width: nil, height: nil)).width
      }.max() ?? 0
    }
    guard let proposedWidth = proposal.width else { return ideal }
    let spacingTotal = Double(max(0, count - 1)) * e.props.padding.leading
    let budget = max(0, Double(proposedWidth) - spacingTotal)
    let totalIdeal = ideal.reduce(0, +)
    if totalIdeal <= budget + 0.5 || totalIdeal <= 0 {
      return ideal
    }
    let scale = budget / totalIdeal
    let allotted = ideal.map { $0 * scale }
    return (0..<count).map { i in
      let limit = allotted[i]
      let measured = rows.compactMap { row -> Double? in
        guard i < row.children.count else { return nil }
        return measure(row.children[i], ProposedViewSize(width: CGFloat(limit), height: nil)).width
      }.max() ?? 0
      return min(limit, measured)
    }
  }
  private func fills(_ e: Element, horizontal: Bool) -> Bool {
    guard pass != nil, e.layoutID != 0 else { return fillsUncached(e, horizontal: horizontal) }
    let flexibility: Cache.Flexibility
    if let result = cache.flexibility[e.layoutID] {
      flexibility = result
    } else {
      let width = fillsUncached(e, horizontal: true)
      let height = fillsUncached(e, horizontal: false)
      flexibility = width ? (height ? .both : .horizontal) : (height ? .vertical : .neither)
      cache.flexibility[e.layoutID] = flexibility
    }
    return flexibility == .both || flexibility == (horizontal ? .horizontal : .vertical)
  }
  private func aspectProposal(
    _ p: NodeProps, child: Element, offer: ProposedViewSize
  ) -> ProposedViewSize {
    let resolvedRatio: Double?
    if let explicit = p.aspectRatio, explicit.isFinite, explicit > 0 {
      resolvedRatio = explicit
    } else {
      let ideal = measure(child, .unspecified)
      resolvedRatio = (ideal.width > 0 && ideal.height > 0) ? (ideal.width / ideal.height) : nil
    }
    guard let r = resolvedRatio, r > 0 else { return offer }
    let pw = offer.width.flatMap { $0.isFinite ? max(0, Double($0)) : nil }
    let ph = offer.height.flatMap { $0.isFinite ? max(0, Double($0)) : nil }
    let w: Double
    let h: Double
    switch (pw, ph) {
    case let (pw?, ph?):
      if p.aspectFit {
        w = min(pw, ph * r)
        h = w / r
      } else {
        w = max(pw, ph * r)
        h = w / r
      }
    case let (pw?, nil):
      w = pw
      h = pw / r
    case let (nil, ph?):
      h = ph
      w = ph * r
    case (nil, nil):
      let ideal = measure(child, .unspecified)
      if ideal.width > 0 && ideal.height > 0 {
        if p.aspectRatio == nil {
          w = ideal.width
          h = ideal.height
        } else if p.aspectFit {
          w = min(ideal.width, ideal.height * r)
          h = w / r
        } else {
          w = max(ideal.width, ideal.height * r)
          h = w / r
        }
      } else if ideal.width > 0 {
        w = ideal.width
        h = ideal.width / r
      } else if ideal.height > 0 {
        h = ideal.height
        w = ideal.height * r
      } else {
        return offer
      }
    }
    return ProposedViewSize(width: CGFloat(max(0, w)), height: CGFloat(max(0, h)))
  }
  private func fillsUncached(_ e: Element, horizontal: Bool) -> Bool {
    let p = e.props
    if p.hasAspectConstraint { return false }
    if horizontal ? p.frameWidth != nil || p.fixedWidth : p.frameHeight != nil || p.fixedHeight {
      return false
    }
    if horizontal ? p.fillWidth : p.fillHeight { return true }
    switch e.kind {
    case .presentation, .padding, .frame, .layer, .styledButton:
      return e.children.first.map { fills($0, horizontal: horizontal) } ?? false
    case .zStack: return e.children.contains { fills($0, horizontal: horizontal) }
    case .customLayout:
      guard let layout = e.layout else { return false }
      let ideal = layout.measure(.unspecified, children: e.children, engine: self)
      if horizontal {
        let probe = max(1, ideal.width) + 64
        let expanded = layout.measure(
          ProposedViewSize(width: probe, height: nil), children: e.children, engine: self)
        return expanded.width > ideal.width + 0.5
      } else {
        let probe = max(1, ideal.height) + 64
        let expanded = layout.measure(
          ProposedViewSize(width: nil, height: probe), children: e.children, engine: self)
        return expanded.height > ideal.height + 0.5
      }
    case .hostedView:
      guard let measureFn = e.hostedViewMeasure else { return true }
      let ideal = measureFn(.unspecified)
      if horizontal {
        let probe = max(1, ideal.width) + 64
        let expanded = measureFn(ProposedViewSize(width: probe, height: nil))
        return expanded.width > ideal.width + 0.5
      } else {
        let probe = max(1, ideal.height) + 64
        let expanded = measureFn(ProposedViewSize(width: nil, height: probe))
        return expanded.height > ideal.height + 0.5
      }
    case .container(let axis):
      if (axis == .horizontal) == horizontal {
        return e.children.contains { $0.kind == .spacer || fills($0, horizontal: horizontal) }
      }
      return e.children.contains { fills($0, horizontal: horizontal) }
    default: return false
    }
  }
  private func fit(_ e: Element, in size: Size) -> Size {
    let p = e.props
    let knownWidth: Double? =
      p.frameWidth
      ?? (fills(e, horizontal: true)
        ? max(p.minWidth ?? 0, min(size.width, p.maxWidth ?? .infinity)) : nil)
    let knownHeight: Double? =
      p.frameHeight
      ?? (fills(e, horizontal: false)
        ? max(p.minHeight ?? 0, min(size.height, p.maxHeight ?? .infinity)) : nil)
    if let knownWidth, let knownHeight {
      return Size(width: knownWidth, height: knownHeight)
    }
    let natural = measure(e, ProposedViewSize(width: size.width, height: size.height))
    return Size(width: knownWidth ?? natural.width, height: knownHeight ?? natural.height)
  }
  private func aligned(_ size: Size, in rect: Rect, alignment: Alignment, child: Element? = nil)
    -> Rect
  {
    let dx =
      alignment.horizontal == .leading
      ? 0
      : alignment.horizontal == .trailing ? rect.width - size.width : (rect.width - size.width) / 2
    let dy =
      alignment.vertical == .top
      ? 0
      : alignment.vertical == .bottom ? rect.height - size.height : (rect.height - size.height) / 2
    let dimensions = ViewDimensions(width: size.width, height: size.height)
    return Rect(
      x: rect.minX + dx
        + (child?.horizontalGuide.map { dimensions[alignment.horizontal] - $0(dimensions) } ?? 0),
      y: rect.minY + dy
        + (child?.verticalGuide.map { dimensions[alignment.vertical] - $0(dimensions) } ?? 0),
      width: size.width, height: size.height)
  }
  private func place(_ e: inout Element, in offered: Rect) {
    if e.reusesLayout {
      let origin = Point(x: offered.minX + e.props.offsetX, y: offered.minY + e.props.offsetY)
      let stationary = origin == e.frame.origin && e.layoutContext == GeometryContext.current
      let dx = origin.x - e.frame.minX
      let dy = origin.y - e.frame.minY
      if offered.size == e.frame.size
        && (stationary || e.supportsTranslation || canTranslateScroll(e, dx: dx, dy: dy))
      {
        retainGeometry(e)
        if !stationary {
          translate(&e, dx: origin.x - e.frame.minX, dy: origin.y - e.frame.minY)
        }
        return
      }
      e.reusesLayout = false
    }
    if !e.hasDynamicLayout, !e.children.isEmpty, e.layoutID != 0,
      let previous = cache.placements[e.layoutID],
      previous.offered == offered, previous.element.layoutContext == GeometryContext.current
    {
      applyFrames(&e, from: previous.element)
      return
    }
    defer {
      if !e.geometryChangeHandlers.isEmpty {
        let snap = GeometrySnapshot(
          rect: CGRect(x: e.frame.minX, y: e.frame.minY, width: e.frame.width, height: e.frame.height),
          namedOrigins: e.layoutContext
        )
        let proxy = GeometryProxy(snapshot: snap)
        let handlers = e.geometryChangeHandlers
        LifecycleRegistry.shared.enqueue {
          for h in handlers { h(proxy) }
        }
      }
      e.updateOverflow()
      e.hasPresentation = e.kind == .presentation || e.children.contains { $0.hasPresentation }
      e.hasLayoutAnimation = e.hasLayoutAnimation || e.children.contains { $0.hasLayoutAnimation }
      e.hasScopedAnimation = e.hasScopedAnimation || e.children.contains { $0.hasScopedAnimation }
      if !e.hasDynamicLayout && !e.children.isEmpty && e.layoutID != 0 {
        cache.placements[e.layoutID] = Cache.Placement(offered: offered, element: e)
      }
    }
    let rect = Rect(
      x: offered.minX + e.props.offsetX, y: offered.minY + e.props.offsetY, width: offered.width,
      height: offered.height)
    e.frame = rect
    e.layoutContext = GeometryContext.current
    let namedOrigins = GeometryContext.current
    if let name = e.props.coordinateSpace {
      GeometryContext.current[name] = CGPoint(x: rect.minX, y: rect.minY)
    }
    defer { GeometryContext.current = namedOrigins }
    switch e.kind {
    case .text: e.props.renderedText = textLayout(e.props, width: rect.width).text
    case .frame:
      if !e.children.isEmpty {
        let child = e.children[0]
        let targetSize: Size
        if e.props.hasAspectConstraint {
          let constrained = aspectProposal(
            e.props, child: child,
            offer: ProposedViewSize(width: CGFloat(rect.width), height: CGFloat(rect.height)))
          targetSize = Size(
            width: constrained.width.map { Double($0) } ?? rect.width,
            height: constrained.height.map { Double($0) } ?? rect.height)
        } else {
          targetSize = rect.size
        }
        place(
          &e.children[0],
          in: aligned(
            fit(child, in: targetSize), in: rect, alignment: e.props.alignment, child: child))
      }
    case .padding:
      if !e.children.isEmpty {
        let inner = rect.inset(by: e.props.padding)
        let child = e.children[0]
        let size = child.isContainer ? inner.size : fit(child, in: inner.size)
        place(&e.children[0], in: Rect(origin: inner.origin, size: size))
      }
    case .layer:
      guard e.children.count == 2 else { return }
      place(&e.children[0], in: rect)
      let child = e.children[1]
      place(
        &e.children[1],
        in: aligned(fit(child, in: rect.size), in: rect, alignment: e.props.alignment, child: child)
      )
    case .presentation:
      if !e.children.isEmpty { place(&e.children[0], in: rect) }
      if e.children.count > 1 {
        let size = measure(e.children[1], ProposedViewSize(width: 640, height: nil))
        place(
          &e.children[1],
          in: Rect(x: rect.minX, y: rect.maxY, width: size.width, height: size.height))
      }
    case .styledButton: if !e.children.isEmpty { place(&e.children[0], in: rect) }
    case .zStack:
      for i in e.children.indices {
        let child = e.children[i]
        place(
          &e.children[i],
          in: aligned(
            fit(child, in: rect.size), in: rect, alignment: e.props.alignment, child: child))
      }
    case .geometry:
      if let builder = e.geometryBuilder {
        let priorMountedChild =
          (e.evaluationID != 0 ? pass?.mountedGeometryChildren[e.evaluationID] : nil)
          ?? e.children.first
        let cgRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
        let snapshot = GeometrySnapshot(
          rect: cgRect,
          namedOrigins: GeometryContext.current)
        snapshot.capture {
          let started = Date.timeIntervalSinceReferenceDate
          var child: Element
          if let evaluations = pass?.evaluations, e.evaluationID != 0 {
            child = evaluations.evaluateGeometry(
              ownerID: e.evaluationID,
              rect: cgRect,
              namedOrigins: GeometryContext.current
            ) {
              builder(cgRect)
            }
          } else {
            child = builder(cgRect)
          }
          child = normalize(
            child,
            previous: e.evaluationID != 0 ? cache.geometryNormalized[e.evaluationID] : nil)
          if e.evaluationID != 0 {
            cache.geometryNormalized[e.evaluationID] = child
          }
          pass?.geometryMilliseconds += (Date.timeIntervalSinceReferenceDate - started) * 1000
          resolveEnvironment(
            &child, inheritedForeground: e.props.foreground, inheritedDisabled: !e.props.enabled,
            inheritedOpacity: e.props.opacity, inheritedVisible: e.props.visible,
            inheritedLineLimit: e.props.lineLimit, inheritedLineSpacing: e.props.lineSpacing,
            previous: priorMountedChild)
          if let pass, let animator = pass.animator {
            animator.applyGeometryChild(
              &child,
              geometryID: e.id,
              fallbackPrevious: priorMountedChild,
              renderPass: pass.renderPass,
              now: pass.now)
          }
          identify(&child, previousGeometry: cache.geometryContent[e.layoutID])
          e.children = [child]
          place(&e.children[0], in: rect)
          if e.layoutID != 0 { cache.geometryContent[e.layoutID] = e.children[0] }
        }
        e.geometrySnapshot = snapshot
        e.hasPresentation = e.children.contains { $0.hasPresentation }
        e.hasLayoutAnimation = e.hasLayoutAnimation || e.children.contains { $0.hasLayoutAnimation }
        e.hasScopedAnimation = e.hasScopedAnimation || e.children.contains { $0.hasScopedAnimation }
      }
    case .grid:
      let columns = gridColumns(
        e, proposal: ProposedViewSize(width: rect.width, height: rect.height))
      let totalWidth =
        columns.reduce(0, +) + Double(max(0, columns.count - 1)) * e.props.padding.leading
      let spanWidth = max(rect.width, totalWidth)
      var y = rect.minY
      for row in e.children.indices {
        // Grid places row children directly, bypassing place(row). Their
        // proposals can change even when the row's outer frame stays fixed.
        // Reconcile the row so rebuilt GeometryReader content receives keys
        // and mounted IDs instead of retaining placeholder IDs.
        e.children[row].reusesLayout = false
        if e.children[row].kind == .container(.horizontal) && !e.children[row].children.isEmpty {
          let height =
            e.children[row].children.enumerated().map { i, cell in
              let colW = i < columns.count ? columns[i] : nil
              return measure(cell, ProposedViewSize(width: colW.map { CGFloat($0) }, height: nil)).height
            }.max() ?? 0
          e.children[row].frame = Rect(x: rect.minX, y: y, width: spanWidth, height: height)
          var x = rect.minX
          for col in e.children[row].children.indices {
            let colW = col < columns.count ? columns[col] : 0
            place(
              &e.children[row].children[col],
              in: Rect(x: x, y: y, width: colW, height: height))
            x += colW + e.props.padding.leading
          }
          e.children[row].updateOverflow()
          y += height + e.props.spacing
        } else {
          let rowHeight = measure(
            e.children[row], ProposedViewSize(width: CGFloat(spanWidth), height: nil)
          ).height
          place(
            &e.children[row],
            in: Rect(x: rect.minX, y: y, width: spanWidth, height: rowHeight))
          y += rowHeight + e.props.spacing
        }
      }
    case .customLayout:
      if let layout = e.layout {
        if let stackKey = e.lazyCacheKey,
          let origin = pass?.activeScrollContentOrigin,
          let vp = pass?.activeScrollViewportSize
        {
          LazyHeightCache.shared.recordStackViewport(
            stack: stackKey,
            offsetX: max(0, rect.minX - Double(origin.x)),
            offsetY: max(0, rect.minY - Double(origin.y)),
            viewportWidth: vp.width,
            viewportHeight: vp.height)
        }
        let frames = layout.placements(
          CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height),
          children: e.children, engine: self)
        e.customLayoutFrames = frames
        for i in e.children.indices {
          let f = frames[i]
          place(&e.children[i], in: Rect(x: f.minX, y: f.minY, width: f.width, height: f.height))
          if let stackKey = e.lazyCacheKey, let itemID = e.children[i].explicitID,
             !e.children[i].children.isEmpty
          {
            let h = Double(f.height)
            let w = Double(f.width)
            if h > 1 {
              LazyHeightCache.shared.record(stack: stackKey, item: itemID, height: h)
              LazyHeightCache.shared.record(stack: stackKey, item: AnyHashable("__grid_row"), height: h)
            }
            if w > 1 {
              LazyHeightCache.shared.record(stack: stackKey, item: AnyHashable("__grid_col"), height: w)
            }
          }
        }
      }
    case .scroll:
      guard !e.children.isEmpty else { return }
      GeometryContext.current[AnyHashable(ScrollCoordinateSpaceKey.shared)] = CGPoint(
        x: rect.minX, y: rect.minY
      )
      let insets = e.props.scrollContentInsets
      let visibleHeight = max(0, rect.height - insets.top - insets.bottom)
      let visibleWidth = max(0, rect.width - insets.leading - insets.trailing)
      let natural = measure(
        e.children[0],
        ProposedViewSize(
          width: e.props.scrollAxes.contains(.horizontal) ? nil : rect.width,
          height: e.props.scrollAxes.contains(.vertical) ? nil : visibleHeight))
      let size = Size(
        width: e.props.scrollAxes.contains(.horizontal)
          ? natural.width : max(visibleWidth, natural.width),
        height: e.props.scrollAxes.contains(.vertical)
          ? natural.height : max(visibleHeight, natural.height))
      let minX = -insets.leading
      let maxX = max(minX, size.width + insets.trailing - rect.width)
      let minY = -insets.top
      let maxY = max(minY, size.height + insets.bottom - rect.height)
      let offset = Point(
        x: max(minX, min(e.props.scrollOffset.x, maxX)),
        y: max(minY, min(e.props.scrollOffset.y, maxY)))
      func frame(at offset: Point) -> Rect {
        Rect(
          x: rect.minX - offset.x, y: rect.minY - offset.y,
          width: size.width, height: size.height)
      }
      e.props.scrollOffset = offset
      let savedScrollOrigin = pass?.activeScrollContentOrigin
      let savedScrollViewport = pass?.activeScrollViewportSize
      defer {
        pass?.activeScrollContentOrigin = savedScrollOrigin
        pass?.activeScrollViewportSize = savedScrollViewport
      }
      let initialContentFrame = frame(at: offset)
      pass?.activeScrollContentOrigin = CGPoint(
        x: initialContentFrame.minX, y: initialContentFrame.minY)
      pass?.activeScrollViewportSize = Size(width: visibleWidth, height: visibleHeight)
      place(&e.children[0], in: initialContentFrame)
      var finalOffset = offset
      if let target = e.scrollTarget, let match = scrollTargetFrame(target.id, in: e.children[0]) {
        let anchor = target.anchor ?? .topLeading
        let next = Point(
          x: e.props.scrollAxes.contains(.horizontal)
            ? max(
              minX,
              min(
                maxX,
                offset.x + match.minX - (rect.minX + insets.leading) + anchor.x * (match.width - visibleWidth)))
            : offset.x,
          y: e.props.scrollAxes.contains(.vertical)
            ? max(
              minY,
              min(
                maxY,
                offset.y + match.minY - (rect.minY + insets.top) + anchor.y * (match.height - visibleHeight)))
            : offset.y)
        finalOffset = next
        e.props.scrollOffset = next
        let targetContentFrame = frame(at: next)
        pass?.activeScrollContentOrigin = CGPoint(
          x: targetContentFrame.minX, y: targetContentFrame.minY)
        place(&e.children[0], in: targetContentFrame)
        let scroll = e.scrollAction
        let complete = e.completeScrollTarget
        LifecycleRegistry.shared.enqueue {
          complete?()
          scroll?(next)
        }
      }
      if !e.scrollGeometryHandlers.isEmpty {
        let geo = ScrollGeometry(
          contentOffset: CGPoint(x: finalOffset.x, y: finalOffset.y),
          contentSize: CGSize(width: size.width, height: size.height),
          contentInsets: insets,
          containerSize: CGSize(width: rect.width, height: rect.height)
        )
        let handlers = e.scrollGeometryHandlers
        LifecycleRegistry.shared.enqueue {
          for h in handlers { h(geo) }
        }
      }
    case .container(let axis): placeStack(&e, axis: axis, in: rect)
    case .fragment: placeStack(&e, axis: .vertical, in: rect)
    default: break
    }
  }
  private func scrollTargetFrame(_ id: AnyHashable, in element: Element) -> Rect? {
    if element.explicitID == id { return element.frame }
    for child in element.children {
      if let match = scrollTargetFrame(id, in: child) { return match }
    }
    return nil
  }
  private func placeStack(_ e: inout Element, axis: Axis, in rect: Rect) {
    let vertical = axis == .vertical
    if let stackKey = e.lazyCacheKey,
      let origin = pass?.activeScrollContentOrigin,
      let vp = pass?.activeScrollViewportSize
    {
      LazyHeightCache.shared.recordStackViewport(
        stack: stackKey,
        offsetX: max(0, rect.minX - Double(origin.x)),
        offsetY: max(0, rect.minY - Double(origin.y)),
        viewportWidth: vp.width,
        viewportHeight: vp.height)
    }
    let indices = Array(e.children.indices)
    let mainExtent = vertical ? rect.height : rect.width
    let crossExtent = vertical ? rect.width : rect.height
    let proposal = ProposedViewSize(
      width: vertical ? rect.width : nil, height: vertical ? nil : rect.height)
    let alignment = Alignment(
      horizontal: e.props.horizontalAlignment, vertical: e.props.verticalAlignment)
    let spacings = Double(max(0, indices.count - 1)) * e.props.spacing
    var fixed = spacings
    var sizes: [(natural: Size, flex: Double, minSpacer: Double, priority: Double)] =
      Array(repeating: (.zero, 0, 0, 0), count: indices.count)
    for (pos, i) in indices.enumerated() where !e.children[i].props.isLazyPlaceholder {
      let child = e.children[i]
      let minSpacer = child.kind == .spacer ? child.props.spacerMinLength : 0
      let flex =
        child.props.flex > 0 || fills(child, horizontal: !vertical)
        ? max(1, child.props.flex) : 0
      let crossFills = child.props.flex > 0 || fills(child, horizontal: vertical)
      let natural: Size
      if flex > 0 && crossFills {
        natural = .zero
      } else {
        natural = measure(child, proposal)
      }
      sizes[pos] = (natural, flex, minSpacer, child.props.layoutPriority)
      if let stackKey = e.lazyCacheKey, let itemID = child.explicitID, !child.children.isEmpty,
        flex == 0
      {
        LazyHeightCache.shared.record(
          stack: stackKey, item: itemID, height: vertical ? natural.height : natural.width)
      }
      if flex > 0 {
        fixed += minSpacer
      } else {
        fixed += vertical ? natural.height : natural.width
      }
    }
    for (pos, i) in indices.enumerated() where e.children[i].props.isLazyPlaceholder {
      if let stackKey = e.lazyCacheKey, let itemID = e.children[i].explicitID {
        let est = LazyHeightCache.shared.estimatedHeight(stack: stackKey, item: itemID)
        if vertical {
          e.children[i].props.frameHeight = est
        } else {
          e.children[i].props.frameWidth = est
        }
      }
      let child = e.children[i]
      let natural = measure(child, proposal)
      sizes[pos] = (natural, 0, 0, child.props.layoutPriority)
      fixed += vertical ? natural.height : natural.width
    }
    var cursor = vertical ? rect.minY : rect.minX
    let hasDistinctPriorities = Set(sizes.map(\.priority)).count > 1
    if (!vertical && fixed > mainExtent) || (vertical && fixed > mainExtent && hasDistinctPriorities) {
      let nonFlexPositions = sizes.indices.filter { sizes[$0].flex == 0 }
      let spacerReserve = sizes.reduce(0.0) { $0 + $1.minSpacer }
      let allocated = allocateMainSizes(
        ideals: nonFlexPositions.map { vertical ? sizes[$0].natural.height : sizes[$0].natural.width },
        priorities: nonFlexPositions.map { sizes[$0].priority },
        budget: max(0, mainExtent - spacings - spacerReserve))
      for (pos, extent) in zip(nonFlexPositions, allocated) {
        let naturalMain = vertical ? sizes[pos].natural.height : sizes[pos].natural.width
        if extent + 0.5 < naturalMain {
          let child = e.children[indices[pos]]
          if vertical {
            let compressed = measure(
              child, ProposedViewSize(width: CGFloat(rect.width), height: CGFloat(extent)))
            sizes[pos].natural = Size(width: compressed.width, height: extent)
          } else {
            let compressed = measure(
              child, ProposedViewSize(width: CGFloat(extent), height: CGFloat(rect.height)))
            sizes[pos].natural = Size(width: extent, height: compressed.height)
          }
        }
      }
      fixed =
        spacings + spacerReserve
        + sizes.reduce(0) { $0 + ($1.flex > 0 ? 0 : (vertical ? $1.natural.height : $1.natural.width)) }
    }
    var available = max(0, mainExtent - fixed)
    var flexShares = [Double](repeating: 0, count: sizes.count)
    let flexPositions = sizes.indices.filter { sizes[$0].flex > 0 }
    if !flexPositions.isEmpty && available > 0 {
      let distinctFlexPriorities = Array(Set(flexPositions.map { sizes[$0].priority })).sorted(by: >)
      for tier in distinctFlexPriorities {
        guard available > 1e-6 else { break }
        let tierPositions = flexPositions.filter { sizes[$0].priority == tier }
        let tierFlex = tierPositions.reduce(0.0) { $0 + sizes[$1].flex }
        var used = 0.0
        for pos in tierPositions {
          let rawShare = available * sizes[pos].flex / max(1, tierFlex)
          let child = e.children[indices[pos]]
          let maxCap = vertical ? child.props.maxHeight : child.props.maxWidth
          let capped: Double
          if let maxCap, maxCap.isFinite {
            capped = min(rawShare, max(0, maxCap - sizes[pos].minSpacer))
          } else {
            capped = rawShare
          }
          flexShares[pos] = capped
          used += capped
        }
        available = max(0, available - used)
      }
    }
    for (pos, i) in indices.enumerated() {
      let child = e.children[i]
      let sizing = sizes[pos]
      let natural = sizing.natural
      let main =
        sizing.flex > 0
        ? sizing.minSpacer + flexShares[pos] : (vertical ? natural.height : natural.width)
      let cross: Double
      if fills(child, horizontal: vertical) || child.props.flex > 0 {
        let minCross = (vertical ? child.props.minWidth : child.props.minHeight) ?? 0
        let maxCross = (vertical ? child.props.maxWidth : child.props.maxHeight) ?? .infinity
        cross = max(minCross, min(crossExtent, maxCross))
      } else {
        cross = min(crossExtent, vertical ? natural.width : natural.height)
      }
      let size = vertical ? Size(width: cross, height: main) : Size(width: main, height: cross)
      let slot =
        vertical
        ? Rect(x: rect.minX, y: cursor, width: crossExtent, height: main)
        : Rect(x: cursor, y: rect.minY, width: main, height: crossExtent)
      place(
        &e.children[i],
        in: aligned(size, in: slot, alignment: alignment, child: child))
      if let stackKey = e.lazyCacheKey, let itemID = e.children[i].explicitID,
         !e.children[i].children.isEmpty
      {
        LazyHeightCache.shared.record(stack: stackKey, item: itemID, height: main)
      }
      cursor += main + e.props.spacing
    }
  }
  private func applyFrames(_ element: inout Element, from previous: Element) {
    if element.frame != previous.frame { element.reusesLayout = false }
    element.frame = previous.frame
    element.hasOverflow = previous.hasOverflow
    element.layoutContext = previous.layoutContext
    element.props.renderedText = previous.props.renderedText
    element.props.scrollOffset = previous.props.scrollOffset
    for i in element.children.indices {
      applyFrames(&element.children[i], from: previous.children[i])
    }
  }
  private func translate(_ element: inout Element, dx: Double, dy: Double) {
    element.reusesLayout = false
    element.frame.origin.x += dx
    element.frame.origin.y += dy
    element.customLayoutFrames = element.customLayoutFrames.map { $0.offsetBy(dx: dx, dy: dy) }
    element.layoutContext = GeometryContext.current
    let saved = GeometryContext.current
    if let name = element.props.coordinateSpace {
      GeometryContext.current[name] = CGPoint(x: element.frame.minX, y: element.frame.minY)
    }
    defer { GeometryContext.current = saved }
    if let snapshot = element.geometrySnapshot {
      snapshot.rect.origin = CGPoint(x: element.frame.minX, y: element.frame.minY)
      snapshot.namedOrigins = GeometryContext.current
    }
    for i in element.children.indices { translate(&element.children[i], dx: dx, dy: dy) }
  }
  private func allocateMainSizes(
    ideals: [Double], priorities: [Double], budget: Double
  ) -> [Double] {
    guard !ideals.isEmpty else { return [] }
    var allocated = [Double](repeating: 0, count: ideals.count)
    var pool = max(0, budget)
    let tiers = Array(Set(priorities)).sorted(by: >)
    for tier in tiers {
      var remaining = ideals.indices.filter { priorities[$0] == tier }
      guard !remaining.isEmpty else { continue }
      if pool <= 1e-6 {
        for idx in remaining { allocated[idx] = 0 }
        continue
      }
      while !remaining.isEmpty {
        let share = pool / Double(remaining.count)
        let small = remaining.filter { ideals[$0] <= share + 1e-6 }
        if small.isEmpty {
          for index in remaining { allocated[index] = share }
          pool = 0
          break
        }
        for index in small {
          allocated[index] = ideals[index]
          pool = max(0, pool - ideals[index])
        }
        remaining.removeAll { ideals[$0] <= share + 1e-6 }
      }
    }
    return allocated
  }
  private func retainGeometry(_ element: Element) {
    if let snapshot = element.geometrySnapshot {
      snapshot.retain()
      pass?.evaluations?.retainGeometry(ownerID: element.evaluationID)
      for child in element.children where child.hasDynamicLayout { retainGeometry(child) }
      return
    }
    for child in element.children where child.hasDynamicLayout { retainGeometry(child) }
  }
}
