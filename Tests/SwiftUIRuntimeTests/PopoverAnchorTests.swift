import Foundation
import Testing

@testable import SwiftUIRuntime

@Suite("Popover Anchor & Popup Placement", .serialized)
@MainActor
struct PopoverAnchorTests {
  @Test("Popover prefers requested edge and offsets content for arrow beak")
  func popoverPrefersRequestedEdgeAndPositionsArrow() {
    let workArea = Rect(x: 0, y: 0, width: 1440, height: 900)
    let anchor = Rect(x: 600, y: 400, width: 120, height: 30)
    let content = Size(width: 240, height: 180)
    let metrics = PopupPlacementMetrics()

    let top = computePopupPlacement(
      style: .popover, anchorRect: anchor, contentSize: content,
      preferredEdge: .top, workArea: workArea, metrics: metrics)
    #expect(top.resolvedEdge == .top)
    #expect(top.windowRect.width == 240)
    #expect(top.windowRect.height == 180 + metrics.arrowHeight)
    #expect(top.contentRect == Rect(x: 0, y: metrics.arrowHeight, width: 240, height: 180))
    #expect(top.windowRect.minY == anchor.maxY + metrics.anchorGap)
    #expect(abs(top.arrowCenter - 120.0) < 0.5)

    let bottom = computePopupPlacement(
      style: .popover, anchorRect: anchor, contentSize: content,
      preferredEdge: .bottom, workArea: workArea, metrics: metrics)
    #expect(bottom.resolvedEdge == .bottom)
    #expect(bottom.contentRect == Rect(x: 0, y: 0, width: 240, height: 180))
    #expect(bottom.windowRect.maxY == anchor.minY - metrics.anchorGap)

    let leading = computePopupPlacement(
      style: .popover, anchorRect: anchor, contentSize: content,
      preferredEdge: .leading, workArea: workArea, metrics: metrics)
    #expect(leading.resolvedEdge == .leading)
    #expect(leading.contentRect == Rect(x: metrics.arrowHeight, y: 0, width: 240, height: 180))
    #expect(leading.windowRect.minX == anchor.maxX + metrics.anchorGap)

    let trailing = computePopupPlacement(
      style: .popover, anchorRect: anchor, contentSize: content,
      preferredEdge: .trailing, workArea: workArea, metrics: metrics)
    #expect(trailing.resolvedEdge == .trailing)
    #expect(trailing.contentRect == Rect(x: 0, y: 0, width: 240, height: 180))
    #expect(trailing.windowRect.maxX == anchor.minX - metrics.anchorGap)
  }

  @Test("Popover flips across all four monitor work-area edges")
  func popoverFlipsAtAllFourScreenEdges() {
    let workArea = Rect(x: 0, y: 0, width: 1280, height: 720)
    let content = Size(width: 240, height: 180)
    let metrics = PopupPlacementMetrics()

    // Near bottom -> .top (below) flips to .bottom (above)
    let bottomAnchor = Rect(x: 500, y: 660, width: 100, height: 30)
    let flippedUp = computePopupPlacement(
      style: .popover, anchorRect: bottomAnchor, contentSize: content,
      preferredEdge: .top, workArea: workArea, metrics: metrics)
    #expect(flippedUp.resolvedEdge == .bottom)
    #expect(flippedUp.windowRect.maxY <= bottomAnchor.minY)
    #expect(flippedUp.windowRect.minY >= workArea.minY + metrics.screenMargin)

    // Near top -> .bottom (above) flips to .top (below)
    let topAnchor = Rect(x: 500, y: 20, width: 100, height: 30)
    let flippedDown = computePopupPlacement(
      style: .popover, anchorRect: topAnchor, contentSize: content,
      preferredEdge: .bottom, workArea: workArea, metrics: metrics)
    #expect(flippedDown.resolvedEdge == .top)
    #expect(flippedDown.windowRect.minY >= topAnchor.maxY)
    #expect(flippedDown.windowRect.maxY <= workArea.maxY - metrics.screenMargin)

    // Near right -> .leading (right) flips to .trailing (left)
    let rightAnchor = Rect(x: 1180, y: 340, width: 80, height: 30)
    let flippedLeft = computePopupPlacement(
      style: .popover, anchorRect: rightAnchor, contentSize: content,
      preferredEdge: .leading, workArea: workArea, metrics: metrics)
    #expect(flippedLeft.resolvedEdge == .trailing)
    #expect(flippedLeft.windowRect.maxX <= rightAnchor.minX)

    // Near left -> .trailing (left) flips to .leading (right)
    let leftAnchor = Rect(x: 20, y: 340, width: 80, height: 30)
    let flippedRight = computePopupPlacement(
      style: .popover, anchorRect: leftAnchor, contentSize: content,
      preferredEdge: .trailing, workArea: workArea, metrics: metrics)
    #expect(flippedRight.resolvedEdge == .leading)
    #expect(flippedRight.windowRect.minX >= leftAnchor.maxX)
  }

  @Test("Popover clamps horizontally to monitor work area while keeping arrow pointed at anchor")
  func popoverClampsHorizontallyAndTracksArrow() {
    let workArea = Rect(x: 0, y: 0, width: 1000, height: 700)
    let anchor = Rect(x: 920, y: 200, width: 60, height: 28)
    let content = Size(width: 260, height: 160)
    let metrics = PopupPlacementMetrics()

    let placed = computePopupPlacement(
      style: .popover, anchorRect: anchor, contentSize: content,
      preferredEdge: .top, workArea: workArea, metrics: metrics)
    #expect(placed.resolvedEdge == .top)
    #expect(placed.windowRect.maxX <= workArea.maxX - metrics.screenMargin + 0.01)
    #expect(placed.arrowCenter > 130.0)
    #expect(placed.arrowCenter <= content.width - (metrics.cornerRadius + metrics.arrowWidth * 0.5 + 2.0) + 0.01)
  }

  @Test("Menu popover and context menu flip cleanly near screen edges")
  func menuPopoverAndContextMenuFlip() {
    let workArea = Rect(x: 0, y: 0, width: 1280, height: 720)
    let metrics = PopupPlacementMetrics()

    let menuAnchor = Rect(x: 400, y: 670, width: 140, height: 28)
    let menuPlaced = computePopupPlacement(
      style: .menuPopover, anchorRect: menuAnchor, contentSize: Size(width: 200, height: 180),
      preferredEdge: .top, workArea: workArea, metrics: metrics)
    #expect(menuPlaced.resolvedEdge == .bottom)
    #expect(menuPlaced.windowRect.maxY <= menuAnchor.minY)
    #expect(menuPlaced.windowRect.minY >= workArea.minY + metrics.screenMargin)

    let ctxAnchor = Rect(x: 1100, y: 580, width: 160, height: 120)
    let ctxPlaced = computePopupPlacement(
      style: .contextMenu, anchorRect: ctxAnchor, anchorPoint: CGPoint(x: 120, y: 100),
      contentSize: Size(width: 180, height: 140), workArea: workArea, metrics: metrics)
    #expect(ctxPlaced.resolvedEdge == .bottom)
    #expect(ctxPlaced.windowRect.maxX <= workArea.maxX - metrics.screenMargin + 0.01)
    #expect(ctxPlaced.windowRect.maxY <= workArea.maxY - metrics.screenMargin + 0.01)
    #expect(ctxPlaced.windowRect.maxX <= 1220.0 + 0.01)
    #expect(ctxPlaced.windowRect.maxY <= 680.0 + 0.01)
  }

  @Test("Small host window preserves full ideal popover content size in popup metadata")
  func smallHostWindowPreservesIdealPopoverSize() throws {
    struct CompactHost: View {
      @State var open = true
      var body: some View {
        Button("Icon") { open.toggle() }
          .frame(width: 80, height: 28)
          .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack {
              Text("Icon Picker")
            }
            .frame(width: 260, height: 200)
          }
      }
    }

    let renderer = Renderer(
      backend: FakeBackend(),
      root: AnyView(CompactHost()),
      size: Size(width: 160, height: 80)
    )
    renderer.mount()

    let tree = try #require(renderer.tree)
    #expect(tree.hasActivePresentation)
    #expect(tree.popupPresentations.count == 1)
    let meta = try #require(tree.popupPresentations.first)
    #expect(meta.style == .popover)
    #expect(meta.drawsPopoverChrome)
    #expect(meta.preferredEdge == .bottom)
    #expect(abs(meta.contentSize.width - 260.0) < 1.0)
    #expect(abs(meta.contentSize.height - 200.0) < 1.0)

    let workArea = Rect(x: 0, y: 0, width: 1920, height: 1080)
    let hostScreenOrigin = Point(x: 500, y: 400)
    let anchorOnScreen = Rect(
      x: hostScreenOrigin.x + meta.anchorRect.minX,
      y: hostScreenOrigin.y + meta.anchorRect.minY,
      width: meta.anchorRect.width,
      height: meta.anchorRect.height
    )
    let placed = computePopupPlacement(
      style: meta.style, anchorRect: anchorOnScreen, contentSize: meta.contentSize,
      preferredEdge: meta.preferredEdge, workArea: workArea)
    // Popover freely escapes the tiny 160x80 host window!
    #expect(placed.windowRect.width >= 260.0)
    #expect(placed.windowRect.height >= 200.0)
    #expect(placed.windowRect.minY < hostScreenOrigin.y)
  }

  @Test("Popups populate popupPresentations while modal sheets and alerts stay in-window")
  func popupVsModalSeparation() throws {
    struct SheetHost: View {
      @State var showSheet = true
      var body: some View {
        Text("Base")
          .sheet(isPresented: $showSheet) {
            Text("Modal Sheet").frame(width: 240, height: 160)
          }
      }
    }
    let sheetRenderer = Renderer(
      backend: FakeBackend(), root: AnyView(SheetHost()), size: Size(width: 400, height: 300))
    sheetRenderer.mount()
    let sheetTree = try #require(sheetRenderer.tree)
    #expect(sheetTree.hasActivePresentation)
    #expect(sheetTree.popupPresentations.isEmpty)
    #expect(sheetTree.children.allSatisfy { $0.popupPresentationIndex == nil })

    struct AlertHost: View {
      @State var showAlert = true
      var body: some View {
        Text("Base")
          .alert("Confirm", isPresented: $showAlert) {
            Button("OK") {}
          }
      }
    }
    let alertRenderer = Renderer(
      backend: FakeBackend(), root: AnyView(AlertHost()), size: Size(width: 400, height: 300))
    alertRenderer.mount()
    let alertTree = try #require(alertRenderer.tree)
    #expect(alertTree.hasActivePresentation)
    #expect(alertTree.popupPresentations.isEmpty)
    #expect(alertTree.children.allSatisfy { $0.popupPresentationIndex == nil })

    struct ContextHost: View {
      var body: some View {
        Text("Target")
          .frame(width: 120, height: 40)
          .contextMenu {
            Button("Copy") {}
            Button("Delete") {}
          }
      }
    }
    let ctxRenderer = Renderer(
      backend: FakeBackend(), root: AnyView(ContextHost()), size: Size(width: 400, height: 300))
    ctxRenderer.mount()
    let ctxBase = try #require(ctxRenderer.tree)
    _ = ctxRenderer.input(event: 9, point: CGPoint(x: ctxBase.frame.minX + 12, y: ctxBase.frame.minY + 12))
    ctxRenderer.renderIfNeeded()
    let ctxTree = try #require(ctxRenderer.tree)
    #expect(ctxTree.popupPresentations.count == 1)
    #expect(ctxTree.popupPresentations[0].style == .contextMenu)
    #expect(ctxTree.popupPresentations[0].dismissOnAction)
  }

  @Test("Nested popup orders outer beneath inner with relative parent anchor")
  func nestedPopupOrderingAndRelativeAnchor() throws {
    struct NestedHost: View {
      @State var outerOpen = true
      @State var innerOpen = true
      var body: some View {
        Button("Outer") { outerOpen = true }
          .frame(width: 80, height: 28)
          .popover(isPresented: $outerOpen, arrowEdge: .top) {
            VStack(spacing: 8) {
              Text("Outer Content")
              Button("Inner") { innerOpen = true }
                .frame(width: 70, height: 24)
                ._menuPopover(isPresented: $innerOpen, arrowEdge: .top) {
                  Text("Inner Menu Item").frame(width: 140, height: 40)
                }
            }
            .padding(12)
            .frame(width: 220, height: 120)
          }
      }
    }

    let renderer = Renderer(
      backend: FakeBackend(), root: AnyView(NestedHost()), size: Size(width: 400, height: 300))
    renderer.mount()

    let tree = try #require(renderer.tree)
    #expect(tree.popupPresentations.count == 2)
    #expect(tree.popupPresentations[0].style == .popover)
    #expect(tree.popupPresentations[0].parentPresentationIndex == nil)
    #expect(tree.popupPresentations[1].style == .menuPopover)
    #expect(tree.popupPresentations[1].parentPresentationIndex == 0)
    // Inner anchor rect is expressed relative to the outer popover panel's origin.
    #expect(tree.popupPresentations[1].anchorRect.minX >= 0)
    #expect(tree.popupPresentations[1].anchorRect.minY >= 0)
    #expect(tree.popupPresentations[1].anchorRect.maxX <= 220.5)
    #expect(tree.popupPresentations[1].anchorRect.maxY <= 120.5)
  }
}
