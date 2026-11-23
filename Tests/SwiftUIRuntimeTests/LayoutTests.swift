@testable import SwiftUIRuntime
import XCTest

final class LayoutTests: XCTestCase {
  private let metrics = TextMetrics.default

  func testTextUsesFakeMetrics() {
    let tree = makeTree(Text("hello"), size: Size(width: 400, height: 200))
    XCTAssertEqual(tree.kind, .text)
    XCTAssertEqual(tree.frame.width, 5 * metrics.characterWidth)
    XCTAssertEqual(tree.frame.height, metrics.lineHeight)
  }

  func testUpdatedTextMetricsReflowTheSameViewport() {
    let viewport = Size(width: 100, height: 100)
    var width = 20.0
    let renderer = Renderer(
      backend: FakeBackend(), root: AnyView(VStack { Text("Label") }), size: viewport,
      layoutEngine: LayoutEngine(textMeasurer: { _, _ in Size(width: width, height: 20) }))
    renderer.mount()
    let label = renderer.tree?.children.first
    XCTAssertEqual(label?.frame, Rect(x: 40, y: 0, width: 20, height: 20))

    width = 40
    renderer.resize(to: viewport, invalidateMeasurements: true)

    let resized = renderer.tree?.children.first
    XCTAssertEqual(resized?.id, label?.id)
    XCTAssertEqual(resized?.frame, Rect(x: 30, y: 0, width: 40, height: 20))
  }

  func testVStackMeasuresAndPlacesChildren() {
    let tree = makeTree(
      VStack(alignment: .leading, spacing: 4) {
        Text("A")
        Text("BB")
      },
      size: Size(width: 200, height: 200)
    )

    XCTAssertEqual(tree.kind, .container(.vertical))
    XCTAssertEqual(tree.children.count, 2)
    XCTAssertEqual(tree.children[0].frame, Rect(x: 0, y: 0, width: 8, height: 20))
    XCTAssertEqual(tree.children[1].frame, Rect(x: 0, y: 24, width: 16, height: 20))
  }

  func testVStackCentersChildrenOnCrossAxis() {
    let tree = makeTree(
      VStack(spacing: 0) {
        Text("A")
      },
      size: Size(width: 100, height: 100)
    )
    XCTAssertEqual(tree.children[0].frame, Rect(x: 46, y: 0, width: 8, height: 20))
  }

  func testHStackSpacerTakesLeftoverSpace() {
    let tree = makeTree(
      HStack(spacing: 0) {
        Text("A")
        Spacer()
        Text("B")
      },
      size: Size(width: 100, height: 20)
    )

    XCTAssertEqual(tree.children.count, 3)
    XCTAssertEqual(tree.children[0].frame, Rect(x: 0, y: 0, width: 8, height: 20))
    XCTAssertEqual(tree.children[1].kind, .spacer)
    XCTAssertEqual(tree.children[1].frame, Rect(x: 8, y: 0, width: 84, height: 20))
    XCTAssertEqual(tree.children[2].frame, Rect(x: 92, y: 0, width: 8, height: 20))
  }

  func testPaddingWrapsAndInsetsContent() {
    let tree = makeTree(
      Text("A").padding(10),
      size: Size(width: 100, height: 100)
    )

    XCTAssertEqual(tree.kind, .padding)
    XCTAssertEqual(tree.children.count, 1)
    XCTAssertEqual(tree.frame, Rect(x: 0, y: 0, width: 100, height: 100))
    XCTAssertEqual(tree.children[0].frame, Rect(x: 10, y: 10, width: 8, height: 20))
  }

  func testFrameOverridesMeasuredSize() {
    let tree = makeTree(
      VStack(spacing: 0) {
        Text("A").frame(width: 40, height: 30)
      },
      size: Size(width: 100, height: 100)
    )
    XCTAssertEqual(tree.children[0].frame.width, 40)
    XCTAssertEqual(tree.children[0].frame.height, 30)
  }

  func testHiddenChildPreservesStackSpace() {
    let tree = makeTree(
      VStack(spacing: 0) {
        Text("A")
        Text("B").hidden()
        Text("C")
      },
      size: Size(width: 100, height: 100)
    )

    XCTAssertEqual(tree.children[1].props.visible, false)
    XCTAssertEqual(tree.children[1].frame, Rect(x: 46, y: 20, width: 8, height: 20))
    XCTAssertEqual(tree.children[2].frame, Rect(x: 46, y: 40, width: 8, height: 20))
  }

  func testForegroundColorIsInherited() {
    let tree = makeTree(
      VStack {
        Text("A")
      }
      .foregroundColor(.red),
      size: Size(width: 100, height: 100)
    )
    XCTAssertEqual(tree.children[0].props.foreground, .red)
  }

  func testDisabledIsInheritedAndCanBeOverridden() {
    let tree = makeTree(
      VStack {
        Button("A") {}
        Button("B") {}.disabled(false)
      }
      .disabled(),
      size: Size(width: 100, height: 100)
    )

    XCTAssertEqual(tree.children[0].props.enabled, false)
    XCTAssertEqual(tree.children[1].props.enabled, true)
  }

  func testAnchorPreferencePositionsOverlayCalloutBelowRightAlignedRecorder() {
    struct RecorderAnchorKey: PreferenceKey {
      static let defaultValue: Anchor<CGRect>? = nil
      static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
      }
    }

    var resolvedField: CGRect?
    let root = HStack(spacing: 0) {
      Color.gray.frame(width: 200)
      Form {
        Section {
          HStack(spacing: 16) {
            Text("Show Launcher")
            Spacer(minLength: 16)
            Text("Record Hotkey")
              .frame(width: 120, height: 24)
              .anchorPreference(key: RecorderAnchorKey.self, value: .bounds) { $0 }
          }
        } header: {
          Text("Global Shortcuts")
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .overlayPreferenceValue(RecorderAnchorKey.self) { anchor in
        GeometryReader { proxy in
          let field = anchor.map { proxy[$0] }
          let _ = { resolvedField = field }()
          Color.clear.overlay {
            if let field {
              let calloutSize = CGSize(width: 176, height: 104)
              let gap: CGFloat = 8
              let centerX = min(max(field.midX, calloutSize.width / 2 + 4), proxy.size.width - calloutSize.width / 2 - 4)
              let centerY = field.maxY + gap + calloutSize.height / 2
              Text("CalloutPopup")
                .frame(width: calloutSize.width, height: calloutSize.height)
                .position(x: centerX, y: centerY)
            }
          }
        }
      }
    }

    let renderer = Renderer(backend: FakeBackend(), root: AnyView(root), size: Size(width: 780, height: 560))
    renderer.mount()

    guard let field = resolvedField else {
      return XCTFail("Expected anchorPreference to resolve non-nil CGRect")
    }
    XCTAssertEqual(field.width, 120, accuracy: 0.5)
    XCTAssertEqual(field.height, 24, accuracy: 0.5)
    XCTAssertGreaterThan(field.minX, 400, "Recorder should sit near the right edge of the detail pane")
    XCTAssertGreaterThan(field.minY, 30)
    XCTAssertLessThan(field.minY, 112, "Top row should place callout below the recorder")

    func findNode(named label: String, in node: Element) -> Element? {
      if node.props.text == label { return node }
      for child in node.children {
        if let hit = findNode(named: label, in: child) { return hit }
      }
      return nil
    }
    guard let tree = renderer.tree, let calloutText = findNode(named: "CalloutPopup", in: tree) else {
      return XCTFail("Expected CalloutPopup to be mounted in overlay")
    }
    let globalRecorderMinX = 200.0 + Double(field.minX)
    let globalRecorderMaxY = Double(field.maxY)
    let calloutMidX = calloutText.frame.minX + calloutText.frame.width / 2
    XCTAssertGreaterThan(calloutText.frame.minY, globalRecorderMaxY, "Callout text should render below the recorder control")
    XCTAssertGreaterThan(calloutMidX, globalRecorderMinX - 40, "Callout should align horizontally under the recorder")
  }

  func testAspectRatioFitPreviewCardsInEqualWidthHStackColumns() {
    struct GridDotsShape: Shape {
      let columns: Int
      func path(in rect: CGRect) -> Path {
        var p = Path()
        let subdivisions = columns * 4
        guard subdivisions > 0 else { return p }
        let stepX = rect.width / CGFloat(subdivisions)
        let stepY = rect.height / CGFloat(subdivisions)
        for row in 1..<subdivisions where row.isMultiple(of: 4) {
          for col in 1..<subdivisions where col.isMultiple(of: 4) {
            p.addEllipse(
              in: CGRect(
                x: rect.minX + CGFloat(col) * stepX - 0.5,
                y: rect.minY + CGFloat(row) * stepY - 0.5,
                width: 1, height: 1))
          }
        }
        return p
      }
    }

    let cardShape = RoundedRectangle(cornerRadius: 10, style: .continuous)
    let picker = VStack(alignment: .leading, spacing: 16) {
      Text("Column Count")
      HStack(spacing: 16) {
        ForEach([5, 6, 7, 8, 9], id: \.self) { cols in
          Button {} label: {
            VStack(spacing: 6) {
              GridDotsShape(columns: cols)
                .fill(cols == 7 ? Color.white : Color.gray)
                .background(cardShape.fill(cols == 7 ? Color.gray.opacity(0.2) : Color.clear))
                .overlay(cardShape.strokeBorder(Color.gray, lineWidth: 1))
                .clipShape(cardShape)
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: 72)
              Text("\(cols)")
            }
            .frame(maxWidth: .infinity)
          }
          .buttonStyle(.plain)
        }
      }
    }

    let wideRenderer = Renderer(
      backend: FakeBackend(), root: AnyView(picker), size: Size(width: 600, height: 300))
    wideRenderer.mount()
    guard let wideTree = wideRenderer.tree else { return XCTFail("Missing mounted tree") }

    func collectDotShapes(_ node: Element, into out: inout [Element]) {
      if node.kind == .shape, node.pathBuilder != nil, node.props.borderWidth == 0,
         node.props.background != .clear, node.props.background != Color.gray.opacity(0.2)
      {
        out.append(node)
      }
      for c in node.children { collectDotShapes(c, into: &out) }
    }
    func findText(_ label: String, in node: Element) -> Element? {
      if node.kind == .text, node.props.text == label { return node }
      for c in node.children {
        if let hit = findText(label, in: c) { return hit }
      }
      return nil
    }

    var dotShapes: [Element] = []
    collectDotShapes(wideTree, into: &dotShapes)
    XCTAssertEqual(dotShapes.count, 5, "Expected 5 column-count preview dot shapes")
    for (idx, dotNode) in dotShapes.enumerated() {
      XCTAssertEqual(dotNode.frame.width, 72, accuracy: 0.5, "Preview \(idx) width should cap at maxWidth 72")
      XCTAssertEqual(dotNode.frame.height, 72, accuracy: 0.5, "Preview \(idx) height should match 1:1 aspect ratio")
      let built = dotNode.pathBuilder?(
        CGRect(
          x: dotNode.frame.minX, y: dotNode.frame.minY,
          width: dotNode.frame.width, height: dotNode.frame.height))
      XCTAssertNotNil(built)
      XCTAssertFalse(built?.commands.isEmpty ?? true, "GridDotsShape path should emit dot ellipses")
      let colNumber = 5 + idx
      guard let numberText = findText("\(colNumber)", in: wideTree) else {
        return XCTFail("Missing label \(colNumber)")
      }
      XCTAssertGreaterThanOrEqual(
        numberText.frame.minY, dotNode.frame.maxY + 5.5,
        "Number label \(colNumber) should sit below the 72x72 preview card")
      let dotCenter = dotNode.frame.minX + dotNode.frame.width / 2
      let labelCenter = numberText.frame.minX + numberText.frame.width / 2
      XCTAssertEqual(dotCenter, labelCenter, accuracy: 1.0, "Preview card should center above its label")
    }

    // Also verify shrinking below maxWidth when viewport is narrow (e.g. 5 columns in 314pt -> 50pt each).
    let narrowRenderer = Renderer(
      backend: FakeBackend(), root: AnyView(picker), size: Size(width: 314, height: 300))
    narrowRenderer.mount()
    guard let narrowTree = narrowRenderer.tree else { return XCTFail("Missing narrow tree") }
    var narrowDots: [Element] = []
    collectDotShapes(narrowTree, into: &narrowDots)
    XCTAssertEqual(narrowDots.count, 5)
    for dotNode in narrowDots {
      XCTAssertEqual(dotNode.frame.width, 50, accuracy: 0.5)
      XCTAssertEqual(dotNode.frame.height, 50, accuracy: 0.5)
    }
  }

  func testResizableImageScaledToFitAndFillPreservesIntrinsicAspectRatio() {
    let fitTree = makeTree(
      Image(filePath: "wide.png", size: Size(width: 80, height: 40), isTemplate: false)
        .resizable()
        .scaledToFit()
        .frame(width: 40, height: 40),
      size: Size(width: 100, height: 100)
    )
    func findImage(_ node: Element) -> Element? {
      if node.kind == .image { return node }
      for c in node.children {
        if let hit = findImage(c) { return hit }
      }
      return nil
    }
    guard let fittedImg = findImage(fitTree) else { return XCTFail("Expected fitted image") }
    XCTAssertEqual(fittedImg.frame.width, 40, accuracy: 0.5)
    XCTAssertEqual(fittedImg.frame.height, 20, accuracy: 0.5)

    let fillTree = makeTree(
      Image(filePath: "wide.png", size: Size(width: 80, height: 40), isTemplate: false)
        .resizable()
        .scaledToFill()
        .frame(width: 40, height: 40)
        .clipped(),
      size: Size(width: 100, height: 100)
    )
    guard let filledImg = findImage(fillTree) else { return XCTFail("Expected filled image") }
    XCTAssertEqual(filledImg.frame.width, 80, accuracy: 0.5)
    XCTAssertEqual(filledImg.frame.height, 40, accuracy: 0.5)
  }
}
