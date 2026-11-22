import Foundation
import XCTest
@testable import SwiftUIRuntime

private struct TestAppStorageView: View {
  let suite: UserDefaults
  @AppStorage private var counter: Int

  init(suite: UserDefaults, key: String) {
    self.suite = suite
    self._counter = AppStorage(wrappedValue: 5, key, store: suite)
  }

  var body: some View {
    VStack {
      Text(verbatim: "stored=\(counter)")
      Button("Bump") {
        counter += 1
      }
    }
  }
}

private struct TestSceneStorageView: View {
  @SceneStorage("tab") private var tab: String = "home"

  var body: some View {
    VStack {
      Text(verbatim: "scene=\(tab)")
      Button("Switch") {
        tab = "settings"
      }
    }
  }
}

private struct TestNavPathView: View {
  @State private var path = NavigationPath()

  var body: some View {
    NavigationStack(path: $path) {
      VStack {
        Text("RootPage")
        NavigationLink("Open Detail", value: 42)
      }
      .navigationDestination(for: Int.self) { number in
        VStack {
          Text(verbatim: "Detail-\(number)")
        }
      }
    }
  }
}

private struct TestDisclosureAndGaugeView: View {
  @State private var expanded = false

  var body: some View {
    VStack {
      DisclosureGroup("More Info", isExpanded: $expanded) {
        Text("HiddenDetail")
      }
      Gauge(value: 0.75, in: 0...1) {
        Text("CPU")
      } currentValueLabel: {
        Text("75%")
      }
    }
  }
}

private struct TestTableRow: Identifiable {
  let id: Int
  let name: String
  let role: String
}

private struct TestTableView: View {
  let rows: [TestTableRow]
  @State private var selected: Int? = nil

  var body: some View {
    VStack {
      Text(verbatim: "sel=\(selected ?? -1)")
      Table(rows, selection: $selected) {
        TableColumn("Name", value: \.name)
        TableColumn("Role", value: \.role)
      }
    }
  }
}

private struct TestDateAndColorView: View {
  @State private var date = Date(timeIntervalSince1970: 1_767_225_600)
  @State private var tint = Color.blue

  var body: some View {
    VStack {
      DatePicker("Due", selection: $date, displayedComponents: [.date])
      ColorPicker("Accent", selection: $tint)
    }
  }
}

private struct TestRedactedView: View {
  var body: some View {
    VStack {
      Text("SecretTitle").redacted(reason: .placeholder)
      Text("VisibleTitle")
    }
  }
}

private struct TestFocusedKey: FocusedValueKey {
  typealias Value = String
}

extension FocusedValues {
  fileprivate var testNote: String? {
    get { self[TestFocusedKey.self] }
    set { self[TestFocusedKey.self] = newValue }
  }
}

private struct TestFocusedProducerView: View {
  var body: some View {
    Text("Editor").focusedValue(\.testNote, "ActiveDocument")
  }
}

private struct TestMultiSceneApp: App {
  var body: some Scene {
    WindowGroup("Main") {
      Text("Primary")
    }
    .commands {
      CommandMenu("Tools") {
        Button("Run Tool") {}
      }
      CommandGroup(after: .newItem) {
        Button("New Note") {}
      }
    }
    Window("Inspector", id: "inspector") {
      Text("InspectorBody")
    }
    Settings {
      Text("SettingsBody")
    }
    MenuBarExtra("Status") {
      Text("PopoverBody")
    } label: {
      Text("Tray")
    }
    .menuBarExtraStyle(.window)
  }
}

@MainActor
final class ExtendedControlsTests: XCTestCase {
  override func setUp() async throws {
    StateRegistry.shared.reset()
  }

  func testAppStoragePersistsAndReactsAcrossRenders() async throws {
    let suiteName = "dev.crossswift.tests.appstorage.\(UUID().uuidString)"
    let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defer { suite.removePersistentDomain(forName: suiteName) }

    let backend = FakeBackend()
    let renderer = Renderer(
      backend: backend,
      root: AnyView(TestAppStorageView(suite: suite, key: "hits")),
      size: Size(width: 300, height: 200)
    )
    renderer.mount()
    XCTAssertTrue(texts(in: renderer.tree!).contains("stored=5"))

    let bumpID = try XCTUnwrap(buttonID(titled: "Bump", in: renderer.tree!))
    renderer.performTap(bumpID)
    XCTAssertEqual(suite.integer(forKey: "hits"), 6)
    XCTAssertTrue(texts(in: renderer.tree!).contains("stored=6"))
  }

  func testSceneStorageIsolatesPerRendererRoot() async throws {
    let r1 = Renderer(
      backend: FakeBackend(),
      root: AnyView(TestSceneStorageView()),
      size: Size(width: 300, height: 200)
    )
    let r2 = Renderer(
      backend: FakeBackend(),
      root: AnyView(TestSceneStorageView()),
      size: Size(width: 300, height: 200)
    )
    r1.mount()
    r2.mount()
    let btn1 = try XCTUnwrap(buttonID(titled: "Switch", in: r1.tree!))
    r1.performTap(btn1)

    XCTAssertTrue(texts(in: r1.tree!).contains("scene=settings"))
    XCTAssertTrue(texts(in: r2.tree!).contains("scene=home"))
  }

  func testNavigationPathPushesTypedDestinationAndPopsBack() async throws {
    let renderer = Renderer(
      backend: FakeBackend(),
      root: AnyView(TestNavPathView()),
      size: Size(width: 400, height: 500)
    )
    renderer.mount()
    XCTAssertTrue(texts(in: renderer.tree!).contains("RootPage"))
    XCTAssertFalse(texts(in: renderer.tree!).contains("Detail-42"))

    let linkID = try XCTUnwrap(styledButtonContaining("Open Detail", in: renderer.tree!))
    renderer.performTap(linkID)
    XCTAssertTrue(texts(in: renderer.tree!).contains("Detail-42"))

    let backID = try XCTUnwrap(styledButtonContaining("Back", in: renderer.tree!))
    renderer.performTap(backID)
    XCTAssertTrue(texts(in: renderer.tree!).contains("RootPage"))
  }

  func testDisclosureGroupExpandsAndGaugeRenders() async throws {
    let renderer = Renderer(
      backend: FakeBackend(),
      root: AnyView(TestDisclosureAndGaugeView()),
      size: Size(width: 320, height: 240)
    )
    renderer.mount()
    XCTAssertFalse(texts(in: renderer.tree!).contains("HiddenDetail"))
    XCTAssertTrue(texts(in: renderer.tree!).contains("75%"))

    let toggleID = try XCTUnwrap(styledButtonContaining("More Info", in: renderer.tree!))
    renderer.performTap(toggleID)
    XCTAssertTrue(texts(in: renderer.tree!).contains("HiddenDetail"))
  }

  func testTableRendersColumnsAndUpdatesSelection() async throws {
    let rows = [
      TestTableRow(id: 1, name: "Alice", role: "Engineer"),
      TestTableRow(id: 2, name: "Bob", role: "Designer"),
    ]
    let renderer = Renderer(
      backend: FakeBackend(),
      root: AnyView(TestTableView(rows: rows)),
      size: Size(width: 400, height: 300)
    )
    renderer.mount()
    XCTAssertTrue(texts(in: renderer.tree!).contains("Alice"))
    XCTAssertTrue(texts(in: renderer.tree!).contains("Designer"))

    let bobRowID = try XCTUnwrap(styledButtonContaining("Bob", in: renderer.tree!))
    renderer.performTap(bobRowID)
    XCTAssertTrue(texts(in: renderer.tree!).contains("sel=2"))
  }

  func testDatePickerColorPickerRedactedAndFocusedValues() async throws {
    let r1 = Renderer(
      backend: FakeBackend(),
      root: AnyView(TestDateAndColorView()),
      size: Size(width: 320, height: 240)
    )
    r1.mount()
    XCTAssertTrue(texts(in: r1.tree!).contains("Due"))
    XCTAssertTrue(texts(in: r1.tree!).contains("Accent"))

    let r2 = Renderer(
      backend: FakeBackend(),
      root: AnyView(TestRedactedView()),
      size: Size(width: 320, height: 120)
    )
    r2.mount()
    let secretNode = findElement(in: r2.tree!) { $0.kind == .text && $0.props.text == "SecretTitle" }
    XCTAssertEqual(secretNode?.props.foreground, .clear)
    XCTAssertNotNil(secretNode?.props.background)

    let r3 = Renderer(
      backend: FakeBackend(),
      root: AnyView(TestFocusedProducerView()),
      size: Size(width: 200, height: 80)
    )
    r3.mount()
    XCTAssertEqual(FocusedValues.active.testNote, "ActiveDocument")
  }

  func testDeclarativeMultiWindowSettingsCommandsAndMenuBarWindowStyle() async throws {
    let app = TestMultiSceneApp()
    let rootScene = app.body

    var leaves: [any Scene] = []
    var commandSections: [_ResolvedCommandSection] = []
    func walk(_ scene: any Scene) {
      if let provider = scene as? any _CommandsProvidingScene {
        commandSections.append(contentsOf: provider._makeCommandSections())
      }
      if let composite = scene as? any _CompositeScene {
        composite._childScenes.forEach(walk)
        return
      }
      leaves.append(scene)
    }
    walk(rootScene)

    let windowScenes = leaves.compactMap { $0 as? any _WindowScene }
    XCTAssertEqual(windowScenes.count, 3)
    XCTAssertTrue(windowScenes.contains(where: { $0._windowID == "inspector" && $0._isSingleInstanceWindow && !$0._opensAtLaunch }))
    XCTAssertTrue(windowScenes.contains(where: { $0._windowID == Settings<EmptyView>.windowID && !$0._opensAtLaunch }))
    XCTAssertEqual(commandSections.map(\.title), ["Tools", "File"])

    let menuExtra = leaves.compactMap { $0 as? any _MenuBarExtraScene }.first
    XCTAssertEqual(menuExtra?._style, .window)
  }

  // MARK: - Helpers

  private func texts(in node: Element) -> [String] {
    var out: [String] = []
    if node.kind == .text && !node.props.text.isEmpty { out.append(node.props.text) }
    for child in node.children { out.append(contentsOf: texts(in: child)) }
    return out
  }

  private func buttonID(titled title: String, in node: Element) -> NodeID? {
    if node.kind == .button && node.props.text == title { return node.id }
    for child in node.children {
      if let found = buttonID(titled: title, in: child) { return found }
    }
    return nil
  }

  private func styledButtonContaining(_ text: String, in node: Element) -> NodeID? {
    if (node.kind == .styledButton || node.kind == .button) && texts(in: node).contains(text) {
      return node.id
    }
    for child in node.children {
      if let found = styledButtonContaining(text, in: child) { return found }
    }
    return nil
  }

  private func findElement(in node: Element, matching predicate: (Element) -> Bool) -> Element? {
    if predicate(node) { return node }
    for child in node.children {
      if let found = findElement(in: child, matching: predicate) { return found }
    }
    return nil
  }
}
