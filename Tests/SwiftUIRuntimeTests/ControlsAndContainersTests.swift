import Foundation
import Observation
import XCTest
@testable import SwiftUIRuntime

private enum SidebarTestTab: String, CaseIterable, Identifiable, Hashable {
  case general, about
  var id: Self { self }
}

@MainActor
@Observable
private final class SidebarTestNav {
  var tab: SidebarTestTab = .general
}

@MainActor
@Observable
private final class PaletteModel {
  var query = ""
  var isCollapsed: Bool { query.isEmpty }
}

@MainActor
@Observable
private final class ExpandState {
  var query = ""
  var isCollapsed: Bool { query.isEmpty }
}

final class ControlsAndContainersTests: XCTestCase {
  @MainActor
  func testGroupedFormTogglePickerAndSectionRenderAndMutate() async {
    struct FormDemo: View {
      @State var launchAtLogin = false
      @State var mode = "compact"

      var body: some View {
        Form {
          Section("General") {
            Toggle("Launch at login", isOn: $launchAtLogin)
            Picker("Window mode", selection: $mode) {
              Text(verbatim: "Compact").tag("compact")
              Text(verbatim: "Expanded").tag("expanded")
            }
            .pickerStyle(.segmented)
          }
        }
        .formStyle(.grouped)
      }
    }

    let backend = FakeBackend()
    let renderer = Renderer(backend: backend, root: AnyView(FormDemo()), size: Size(width: 600, height: 400))
    renderer.mount()

    let root = renderer.tree!
    XCTAssertNotNil(findNode(in: root, text: "General"))
    XCTAssertNotNil(findNode(in: root, text: "Launch at login"))
    XCTAssertNotNil(findNode(in: root, text: "Expanded"))
  }

  @MainActor
  func testSafeAreaInsetUpdatesScrollContentInsetsAndScrollGeometry() async {
    var capturedInsetTop: Double = -1
    var capturedOffset: Double = 999

    struct PaletteLikeScroll: View {
      let onGeo: (ScrollGeometry) -> Void
      var body: some View {
        ScrollView {
          VStack(spacing: 8) {
            ForEach(0..<20) { idx in
              Text(verbatim: "Row \(idx)").frame(height: 36)
            }
          }
        }
        .onScrollGeometryChange(for: ScrollGeometry.self, of: { $0 }) { _, new in
          onGeo(new)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
          Rectangle().fill(.blue).frame(height: 56)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
          Rectangle().fill(.green).frame(height: 52)
        }
      }
    }

    let backend = FakeBackend()
    let renderer = Renderer(
      backend: backend,
      root: AnyView(PaletteLikeScroll { geo in
        capturedInsetTop = geo.contentInsets.top
        capturedOffset = Double(geo.contentOffset.y)
      }),
      size: Size(width: 750, height: 475)
    )
    renderer.mount()
    renderer.renderIfNeeded()

    XCTAssertEqual(capturedInsetTop, 56, accuracy: 0.5)
    XCTAssertEqual(capturedOffset, -56, accuracy: 0.5)
  }

  @MainActor
  func testLazyVStackVirtualizesLargeCollectionsInScrollView() async {
    var evaluatedCount = 0
    struct CountingRow: View {
      let index: Int
      let onEval: () -> Void
      var body: some View {
        let _ = onEval()
        return Text(verbatim: "Item \(index)").frame(height: 40)
      }
    }

    struct BigList: View {
      let onEval: () -> Void
      var body: some View {
        ScrollView {
          LazyVStack(spacing: 0) {
            ForEach(0..<400) { i in
              CountingRow(index: i, onEval: onEval)
            }
          }
        }
      }
    }

    let backend = FakeBackend()
    let renderer = Renderer(
      backend: backend,
      root: AnyView(BigList { evaluatedCount += 1 }),
      size: Size(width: 400, height: 500)
    )
    renderer.mount()
    // Should evaluate only the visible/buffer slice rather than all 400 rows
    XCTAssertLessThan(evaluatedCount, 80)
  }

  func testXCStringsCatalogLoadsTranslationsAndPlurals() throws {
    let sampleJSON = """
    {
      "sourceLanguage" : "en",
      "strings" : {
        "Show Launcher" : {
          "localizations" : {
            "zh-Hans" : {
              "stringUnit" : { "state" : "translated", "value" : "显示启动器" }
            }
          }
        },
        "%@ (%lld items)" : {
          "localizations" : {
            "en" : {
              "variations" : {
                "plural" : {
                  "one" : { "stringUnit" : { "state" : "translated", "value" : "%@ (%lld item)" } },
                  "other" : { "stringUnit" : { "state" : "translated", "value" : "%@ (%lld items)" } }
                }
              }
            },
            "zh-Hans" : {
              "variations" : {
                "plural" : {
                  "other" : { "stringUnit" : { "state" : "translated", "value" : "%@（%lld 项）" } }
                }
              }
            }
          }
        }
      }
    }
    """
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("test-\(UUID().uuidString).xcstrings")
    try sampleJSON.data(using: .utf8)!.write(to: tempURL)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let catalog = XCStringsCatalog()
    XCTAssertTrue(catalog.load(from: tempURL))

    catalog.preferredLanguage = "zh-Hans"
    XCTAssertEqual(catalog.resolve(key: "Show Launcher"), "显示启动器")
    XCTAssertEqual(
      catalog.resolve(key: "%@ (%lld items)", arguments: [.string("Emoji"), .int(5)]),
      "Emoji（5 项）"
    )

    catalog.preferredLanguage = "en"
    XCTAssertEqual(
      catalog.resolve(key: "%@ (%lld items)", arguments: [.string("Emoji"), .int(1)]),
      "Emoji (1 item)"
    )
    XCTAssertEqual(
      catalog.resolve(key: "%@ (%lld items)", arguments: [.string("Emoji"), .int(3)]),
      "Emoji (3 items)"
    )
  }

  @MainActor
  func testSidebarListSelectionSwitchesObservableTab() async {
    struct Sidebar: View {
      @Environment(SidebarTestNav.self) private var nav
      private var selection: Binding<SidebarTestTab?> {
        Binding(get: { nav.tab }, set: { if let t = $0 { nav.tab = t } })
      }
      var body: some View {
        List(selection: selection) {
          ForEach(["Section1"], id: \.self) { title in
            Section(title) {
              ForEach(SidebarTestTab.allCases) { tab in
                Label {
                  Text(tab.rawValue)
                } icon: {
                  Image(systemName: "gear")
                }
                .tag(tab)
              }
            }
          }
        }
        .listStyle(.sidebar)
        .labelStyle(.titleAndIcon)
      }
    }
    struct Root: View {
      @Environment(SidebarTestNav.self) private var nav
      var body: some View {
        NavigationSplitView {
          Sidebar()
        } detail: {
          Text("Detail: \(nav.tab.rawValue)")
        }
      }
    }

    let nav = SidebarTestNav()
    let backend = FakeBackend()
    let renderer = Renderer(
      backend: backend,
      root: AnyView(Root().environment(nav)),
      size: Size(width: 800, height: 600)
    )
    renderer.mount()

    func findButtons(_ el: Element) -> [Element] {
      var out: [Element] = []
      if el.kind == .styledButton || el.kind == .button { out.append(el) }
      for c in el.children { out.append(contentsOf: findButtons(c)) }
      return out
    }
    func findTexts(_ el: Element) -> [String] {
      var out: [String] = []
      if el.kind == .text { out.append(el.props.text) }
      for c in el.children { out.append(contentsOf: findTexts(c)) }
      return out
    }

    let buttons = findButtons(renderer.tree!)
    XCTAssertEqual(buttons.count, 2, "Expected 2 sidebar tab buttons, got \(buttons.count)")
    XCTAssertTrue(findTexts(renderer.tree!).contains("Detail: general"))

    backend.tap(buttons[1].id)
    renderer.renderIfNeeded()
    XCTAssertEqual(nav.tab, .about)
    XCTAssertTrue(findTexts(renderer.tree!).contains("Detail: about"))
  }

  @MainActor
  func testSafeAreaInsetPreservesTextFieldIdentityAcrossCollapsedAndScrollSwap() async {
    struct PaletteShell: View {
      let model: PaletteModel
      var body: some View {
        @Bindable var m = model
        return Group {
          if model.isCollapsed {
            Color.clear
          } else {
            ScrollView {
              VStack(spacing: 4) {
                Text("Result for \(model.query)").frame(height: 36)
              }
            }
          }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
          TextField("Search", text: $m.query).frame(height: 56)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
          if !model.isCollapsed {
            Text("Footer").frame(height: 36)
          }
        }
      }
    }

    func findTextFieldID(_ el: Element) -> NodeID? {
      if el.kind == .textField { return el.id }
      for child in el.children {
        if let found = findTextFieldID(child) { return found }
      }
      return nil
    }

    let model = PaletteModel()
    let backend = FakeBackend()
    let renderer = Renderer(
      backend: backend,
      root: AnyView(PaletteShell(model: model)),
      size: Size(width: 758, height: 64)
    )
    renderer.mount()
    let initialFieldID = findTextFieldID(renderer.tree!)
    XCTAssertNotNil(initialFieldID)

    _ = renderer.input(id: initialFieldID, event: 7, text: "calc")
    renderer.resize(to: Size(width: 750, height: 475))
    renderer.renderIfNeeded()
    let expandedFieldID = findTextFieldID(renderer.tree!)
    XCTAssertEqual(expandedFieldID, initialFieldID, "TextField NodeID must survive collapsed->expanded swap")

    _ = renderer.input(id: initialFieldID, event: 7, text: "")
    renderer.resize(to: Size(width: 758, height: 64))
    renderer.renderIfNeeded()
    let collapsedAgainID = findTextFieldID(renderer.tree!)
    XCTAssertEqual(collapsedAgainID, initialFieldID, "TextField NodeID must survive expanded->collapsed swap")
  }

  @MainActor
  func testReentrantRenderIfNeededInsideOnChangeResizePublishesExpandedLayout() async {
    final class DirectPublishBackend: RenderBackend {
      var tapHandler: ((NodeID) -> Void)?
      var transactionHandler: ((() -> Void) -> Void)?
      var animationTickHandler: (() -> Bool)?
      var environment = EnvironmentValues()
      var needsRenderCommands: Bool { false }
      var publishedSizes: [Size] = []
      func perform(_ commands: [RenderCommand]) {}
      func didRender(_ root: Element) {
        publishedSizes.append(root.frame.size)
      }
    }

    var rendererRef: Renderer?
    struct ResizingPalette: View {
      let state: ExpandState
      let onSyncWindow: (Bool) -> Void
      var body: some View {
        @Bindable var s = state
        return VStack(spacing: 0) {
          TextField("Search", text: $s.query).frame(height: 56)
          if !state.isCollapsed {
            ScrollView {
              Text("Calc = 42").frame(maxWidth: .infinity, minHeight: 200)
            }
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: state.isCollapsed) { _, collapsed in
          onSyncWindow(collapsed)
        }
      }
    }

    let state = ExpandState()
    let backend = DirectPublishBackend()
    let renderer = Renderer(
      backend: backend,
      root: AnyView(ResizingPalette(state: state) { collapsed in
        let target = collapsed ? Size(width: 758, height: 64) : Size(width: 750, height: 475)
        rendererRef?.resize(to: target)
        // Simulate NSWindow.setFrame(..., display: true) -> layoutSubtreeIfNeeded() -> renderIfNeeded()
        rendererRef?.renderIfNeeded()
      }),
      size: Size(width: 758, height: 64)
    )
    rendererRef = renderer
    renderer.mount()
    backend.publishedSizes.removeAll()

    state.query = "calc"
    renderer.renderIfNeeded()

    XCTAssertEqual(
      backend.publishedSizes,
      [Size(width: 750, height: 475)],
      "Intermediate pre-resize 758x64 pass must not overwrite expanded 750x475 publication"
    )
    XCTAssertEqual(renderer.tree?.frame.size, Size(width: 750, height: 475))
  }

  @MainActor
  func testNavigationStackPushAndBackAndTabViewSelection() async {
    struct NavDemo: View {
      var body: some View {
        NavigationStack {
          NavigationLink("Open Detail") {
            Text("Detail Body")
              .navigationTitle("Detail Page")
          }
          .navigationTitle("Root Page")
        }
      }
    }

    let backend = FakeBackend()
    let renderer = Renderer(
      backend: backend,
      root: AnyView(NavDemo()),
      size: Size(width: 390, height: 800)
    )
    renderer.mount()

    func findSemantic(_ kind: String, in el: Element?) -> Element? {
      guard let el else { return nil }
      if el.props.semanticControl?.kind == kind { return el }
      for c in el.children { if let f = findSemantic(kind, in: c) { return f } }
      return nil
    }
    func findTapNode(in el: Element?) -> Element? {
      guard let el else { return nil }
      if el.kind == .styledButton || el.kind == .button { return el }
      for c in el.children { if let f = findTapNode(in: c) { return f } }
      return nil
    }

    let initialBar = findSemantic("navBar", in: renderer.tree)
    XCTAssertEqual(initialBar?.props.semanticControl?.title, "Root Page")
    XCTAssertEqual(initialBar?.props.semanticControl?.canGoBack, false)

    if let linkBtn = findTapNode(in: renderer.tree) {
      renderer.performTap(linkBtn.id)
    }
    let pushedBar = findSemantic("navBar", in: renderer.tree)
    XCTAssertEqual(pushedBar?.props.semanticControl?.canGoBack, true)
    XCTAssertEqual(pushedBar?.props.semanticControl?.title, "Detail Page")

    if let barID = pushedBar?.id {
      renderer.performBackInput(barID)
    }
    let poppedBar = findSemantic("navBar", in: renderer.tree)
    XCTAssertEqual(poppedBar?.props.semanticControl?.canGoBack, false)

    struct TabDemo: View {
      @State var tab = 0
      var body: some View {
        TabView(selection: $tab) {
          Text("Home Content").tabItem { Label("Home", systemImage: "house") }.tag(0)
          Text("Search Content").tabItem { Label("Search", systemImage: "magnifyingglass") }.tag(1)
        }
      }
    }

    let tabRenderer = Renderer(
      backend: FakeBackend(),
      root: AnyView(TabDemo()),
      size: Size(width: 390, height: 800)
    )
    tabRenderer.mount()
    let tabBar = findSemantic("tabBar", in: tabRenderer.tree)
    XCTAssertEqual(tabBar?.props.semanticControl?.items, ["Home", "Search"])
    XCTAssertEqual(tabBar?.props.semanticControl?.intValue, 0)

    if let tabBarID = tabBar?.id {
      tabRenderer.performIntInput(tabBarID, value: 1)
    }
    let updatedTabBar = findSemantic("tabBar", in: tabRenderer.tree)
    XCTAssertEqual(updatedTabBar?.props.semanticControl?.intValue, 1)
  }

  @MainActor
  func testLazyVStackInsideFormRealizesBottomRowsWhenScrolled() throws {
    struct AppRowView: View {
      let index: Int
      var body: some View {
        HStack {
          Text("App \(index)")
          Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 44)
      }
    }

    struct AppsSectionView: View {
      let items: [Int]
      var body: some View {
        Section {
          LazyVStack(spacing: 0) {
            ForEach(items, id: \.self) { index in
              VStack(spacing: 0) {
                if index > 0 { Divider() }
                AppRowView(index: index)
              }
            }
          }
        } header: {
          Text("Applications")
        }
      }
    }

    struct AppsFormPage: View {
      let items = Array(0..<150)
      var body: some View {
        Form {
          Section {
            Text("Enable Applications")
              .frame(height: 60)
          }
          Section {
            Text("Search Scopes")
              .frame(height: 640)
          }
          AppsSectionView(items: items)
        }
      }
    }

    let renderer = Renderer(
      backend: FakeBackend(),
      root: AnyView(AppsFormPage()),
      size: Size(width: 720, height: 600)
    )
    renderer.mount()

    func collectTexts(_ el: Element?, into out: inout Set<String>) {
      guard let el else { return }
      if el.kind == .text, !el.props.text.isEmpty {
        out.insert(el.props.text)
      }
      for child in el.children {
        collectTexts(child, into: &out)
      }
    }

    func findScrollID(_ el: Element?) -> NodeID? {
      guard let el else { return nil }
      if el.kind == .scroll { return el.id }
      for child in el.children {
        if let id = findScrollID(child) { return id }
      }
      return nil
    }

    let scrollID = try XCTUnwrap(findScrollID(renderer.tree))
    var initialTexts = Set<String>()
    collectTexts(renderer.tree, into: &initialTexts)
    XCTAssertTrue(initialTexts.contains("App 0"))
    XCTAssertFalse(initialTexts.contains("App 149"))

    // Scroll all the way to the bottom of the Form; bottom rows must materialize instead of staying blank placeholders.
    renderer.scroll(id: scrollID, to: Point(x: 0, y: 9000))
    renderer.renderIfNeeded()

    var bottomTexts = Set<String>()
    collectTexts(renderer.tree, into: &bottomTexts)
    XCTAssertTrue(bottomTexts.contains("App 148"))
    XCTAssertTrue(bottomTexts.contains("App 149"))
  }

  @MainActor
  func testUnstyledIconButtonsWithAccessibilityLabelRenderStyledSymbolsInsteadOfTextButtons() throws {
    var moves: [Int] = []
    struct FallbackButtonsProbe: View {
      let onMove: (Int) -> Void
      var body: some View {
        VStack(spacing: 8) {
          HStack(spacing: 8) {
            Button { onMove(-1) } label: { Image(systemName: "chevron.up") }
              .disabled(true)
              .accessibilityLabel("Move Search Files up")
            Button { onMove(1) } label: { Image(systemName: "chevron.down") }
              .disabled(false)
              .accessibilityLabel("Move Search Files down")
          }
          HStack(spacing: 8) {
            Button { onMove(-2) } label: { Image(systemName: "chevron.up") }
              .disabled(false)
              .accessibilityLabel("Move Search Web up")
            Button { onMove(2) } label: { Image(systemName: "chevron.down") }
              .disabled(true)
              .accessibilityLabel("Move Search Web down")
          }
        }
      }
    }

    let renderer = Renderer(
      backend: FakeBackend(),
      root: AnyView(FallbackButtonsProbe(onMove: { moves.append($0) })),
      size: Size(width: 400, height: 120)
    )
    renderer.mount()

    func collectKind(_ kind: ElementKind, in el: Element?, into out: inout [Element]) {
      guard let el else { return }
      if el.kind == kind { out.append(el) }
      for child in el.children { collectKind(kind, in: child, into: &out) }
    }

    var rawButtons: [Element] = []
    var styledButtons: [Element] = []
    var images: [Element] = []
    collectKind(.button, in: renderer.tree, into: &rawButtons)
    collectKind(.styledButton, in: renderer.tree, into: &styledButtons)
    collectKind(.image, in: renderer.tree, into: &images)

    XCTAssertEqual(rawButtons.count, 0, "Icon-only unstyled Buttons must not degrade into text push buttons")
    XCTAssertEqual(styledButtons.count, 4)
    XCTAssertEqual(images.map(\.props.imagePath), [
      "sf://chevron.up", "sf://chevron.down", "sf://chevron.up", "sf://chevron.down",
    ])
    XCTAssertFalse(styledButtons[0].props.enabled)
    XCTAssertTrue(styledButtons[1].props.enabled)
    XCTAssertTrue(styledButtons[2].props.enabled)
    XCTAssertFalse(styledButtons[3].props.enabled)

    renderer.performTap(styledButtons[1].id)
    XCTAssertEqual(moves, [1])
  }

  @MainActor
  func testAppPickerPopoverScrollViewHasExactHeightAndRealizesBottomItems() throws {
    final class PickerModel: ObservableObject {
      @Published var picking = true
    }

    struct AppPickerPopoverProbe: View {
      let apps = Array(0..<150)
      var body: some View {
        VStack(spacing: 0) {
          Text("Search Header")
            .frame(height: 40)
          Divider()
          ScrollView {
            LazyVStack(spacing: 1) {
              ForEach(apps, id: \.self) { index in
                Button(action: {}) {
                  HStack(spacing: 8) {
                    Text("Icon").frame(width: 20, height: 20)
                    Text("Candidate \(index)").lineLimit(1)
                    Spacer(minLength: 0)
                  }
                  .padding(.horizontal, 8)
                  .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
              }
            }
            .padding(4)
          }
        }
        .frame(width: 220, height: 240)
      }
    }

    struct HostPage: View {
      @ObservedObject var model: PickerModel
      var body: some View {
        Form {
          Section {
            Button("Add Application…") { model.picking = true }
              .popover(isPresented: $model.picking, arrowEdge: .bottom) {
                AppPickerPopoverProbe()
              }
          }
        }
      }
    }

    let model = PickerModel()
    let renderer = Renderer(
      backend: FakeBackend(),
      root: AnyView(HostPage(model: model)),
      size: Size(width: 720, height: 600)
    )
    renderer.mount()

    func collectScrolls(_ el: Element?, into out: inout [Element]) {
      guard let el else { return }
      if el.kind == .scroll { out.append(el) }
      for child in el.children { collectScrolls(child, into: &out) }
    }
    func collectTexts(_ el: Element?, into out: inout Set<String>) {
      guard let el else { return }
      if el.kind == .text, !el.props.text.isEmpty { out.insert(el.props.text) }
      for child in el.children { collectTexts(child, into: &out) }
    }

    var scrolls: [Element] = []
    collectScrolls(renderer.tree, into: &scrolls)
    // Last scroll node belongs to the presented AppPickerPopover (width = 220).
    let popoverScroll = try XCTUnwrap(scrolls.last { abs($0.frame.width - 220) < 1 })
    let contentHeight = try XCTUnwrap(popoverScroll.children.first?.frame.height)
    // 150 rows * 28pt (20pt icon + 2*4pt vPad) + 149 * 1pt spacing + 2*4pt outer padding = 4357pt
    XCTAssertEqual(contentHeight, 4357.0, accuracy: 2.0, "Popover LazyVStack must use exact 28pt row height on frame 1 without 44pt placeholder inflation")

    // Scroll to the very bottom of the popover list; Candidate 149 must be realized with zero trailing blank gap.
    renderer.scroll(id: popoverScroll.id, to: Point(x: 0, y: 5000))
    renderer.renderIfNeeded()

    var bottomScrolls: [Element] = []
    collectScrolls(renderer.tree, into: &bottomScrolls)
    let updatedPopoverScroll = try XCTUnwrap(bottomScrolls.last { abs($0.frame.width - 220) < 1 })
    var bottomTexts = Set<String>()
    collectTexts(updatedPopoverScroll, into: &bottomTexts)
    XCTAssertTrue(bottomTexts.contains("Candidate 148"))
    XCTAssertTrue(bottomTexts.contains("Candidate 149"))
  }

  @MainActor
  func testPickerAndMenuDropdownSelectionHighlightSpansFullMenuWidth() throws {
    struct NarrowPickerHost: View {
      @State var choice = "dark"
      var body: some View {
        Picker("Appearance", selection: $choice) {
          Text(verbatim: "System").tag("system")
          Text(verbatim: "Light").tag("light")
          Text(verbatim: "Dark").tag("dark")
        }
        .pickerStyle(.menu)
      }
    }

    let narrowRenderer = Renderer(
      backend: FakeBackend(),
      root: AnyView(NarrowPickerHost()),
      size: Size(width: 500, height: 400)
    )
    narrowRenderer.mount()

    let trigger = try XCTUnwrap(findNode(in: narrowRenderer.tree!, text: "Dark"))
    narrowRenderer.performTap(trigger.id)

    // Presented menu panel is the last child of the root active presentation ZStack.
    let narrowPanel = try XCTUnwrap(narrowRenderer.tree?.children.last)
    XCTAssertGreaterThanOrEqual(narrowPanel.frame.width, 140)
    let narrowRows = allNodes(narrowPanel).filter { $0.kind == .styledButton }
    XCTAssertEqual(narrowRows.count, 3)
    for row in narrowRows {
      XCTAssertEqual(row.frame.minX, narrowPanel.frame.minX + 6, accuracy: 0.5)
      XCTAssertEqual(row.frame.maxX, narrowPanel.frame.maxX - 6, accuracy: 0.5)
    }
    let selectedBg = try XCTUnwrap(
      allNodes(narrowRows[2]).first { $0.kind == .shape && ($0.props.background?.opacity ?? 0) > 0.1 }
    )
    XCTAssertEqual(selectedBg.frame.minX, narrowPanel.frame.minX + 6, accuracy: 0.5)
    XCTAssertEqual(selectedBg.frame.maxX, narrowPanel.frame.maxX - 6, accuracy: 0.5)

    // Mixed short + wide options where the short option is selected:
    struct MixedPickerHost: View {
      @State var choice = "short"
      var body: some View {
        Picker("Retention", selection: $choice) {
          Text(verbatim: "Off").tag("short")
          Text(verbatim: "Follow System Appearance Automatically").tag("wide")
        }
        .pickerStyle(.menu)
      }
    }

    let mixedRenderer = Renderer(
      backend: FakeBackend(),
      root: AnyView(MixedPickerHost()),
      size: Size(width: 500, height: 400)
    )
    mixedRenderer.mount()
    let mixedTrigger = try XCTUnwrap(findNode(in: mixedRenderer.tree!, text: "Off"))
    mixedRenderer.performTap(mixedTrigger.id)

    let mixedPanel = try XCTUnwrap(mixedRenderer.tree?.children.last)
    XCTAssertGreaterThan(mixedPanel.frame.width, 170)
    let mixedRows = allNodes(mixedPanel).filter { $0.kind == .styledButton }
    XCTAssertEqual(mixedRows.count, 2)
    let shortSelectedBg = try XCTUnwrap(
      allNodes(mixedRows[0]).first { $0.kind == .shape && ($0.props.background?.opacity ?? 0) > 0.1 }
    )
    XCTAssertEqual(shortSelectedBg.frame.minX, mixedPanel.frame.minX + 6, accuracy: 0.5)
    XCTAssertEqual(shortSelectedBg.frame.maxX, mixedPanel.frame.maxX - 6, accuracy: 0.5)

    // Action Menu: items fill inner menu width, highlight on hover, and dismiss on tap.
    final class MenuTracker { var copies = 0 }
    let tracker = MenuTracker()
    let menuView = Menu("Actions") {
      Button("Copy") { tracker.copies += 1 }
      Button("Rename Selected Item") {}
    }
    let menuRenderer = Renderer(
      backend: FakeBackend(),
      root: AnyView(menuView),
      size: Size(width: 500, height: 400)
    )
    menuRenderer.mount()
    let menuTrigger = try XCTUnwrap(findNode(in: menuRenderer.tree!, text: "Actions"))
    menuRenderer.performTap(menuTrigger.id)

    let menuPanel = try XCTUnwrap(menuRenderer.tree?.children.last)
    let menuButtons = allNodes(menuPanel).filter { $0.kind == .styledButton }
    XCTAssertEqual(menuButtons.count, 2)
    XCTAssertEqual(menuButtons[0].frame.minX, menuPanel.frame.minX + 6, accuracy: 0.5)
    XCTAssertEqual(menuButtons[0].frame.maxX, menuPanel.frame.maxX - 6, accuracy: 0.5)

    menuRenderer.interact(menuButtons[0].id, .hover(true))
    let updatedMenuPanel = try XCTUnwrap(menuRenderer.tree?.children.last)
    let hoveredBtn = allNodes(updatedMenuPanel).filter { $0.kind == .styledButton }[0]
    let hoverBg = try XCTUnwrap(
      allNodes(hoveredBtn).first { $0.kind == .shape && ($0.props.background?.opacity ?? 0) > 0.05 }
    )
    XCTAssertEqual(hoverBg.frame.maxX, updatedMenuPanel.frame.maxX - 6, accuracy: 0.5)

    menuRenderer.performTap(hoveredBtn.id)
    XCTAssertEqual(tracker.copies, 1)
    XCTAssertNil(findNode(in: menuRenderer.tree!, text: "Rename Selected Item"))
  }
}
