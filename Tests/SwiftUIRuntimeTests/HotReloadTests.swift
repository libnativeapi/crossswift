import Foundation
#if (os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)) && canImport(CoreGraphics)
  import CoreGraphics
#endif
import Observation
@testable import SwiftUIRuntime
import XCTest

// MARK: - Test Fixtures

private struct HotReloadTodo: Codable, Equatable, Hashable {
  var id: Int
  var title: String
  var done: Bool
}

private enum HotReloadTab: String, Equatable {
  case home
  case search
  case settings
}

private struct HotReloadRoute: Hashable, Codable {
  let id: Int
  let title: String
}

private final class CodableCounterObject: SwiftUIRuntime.ObservableObject, Codable {
  var value: Int
  init(value: Int = 0) { self.value = value }
}

private final class NonCodableObject: SwiftUIRuntime.ObservableObject {
  var token: String
  init(token: String = "fresh") { self.token = token }
}

private struct PrimitivesView: View {
  @State var flag = false
  @State var count = 0
  @State var big: Int64 = 0
  @State var ratio: Double = 0.0
  @State var single: Float = 0.0
  @State var text = "initial"
  @State var width: CGFloat = 10
  @State var link = URL(string: "https://example.com/start")!
  @State var timestamp = Date(timeIntervalSinceReferenceDate: 100)
  @State var bytes = Data([1, 2])
  @State var identifier = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
  @State var optionalSome: Int? = nil
  @State var optionalNone: String? = "present"
  @State var tags: [String] = []
  @State var scores: [String: Int] = [:]

  static let updatedURL = URL(string: "https://crossswift.dev/hot-reload")!
  static let updatedDate = Date(timeIntervalSinceReferenceDate: 12345.5)
  static let updatedData = Data([9, 8, 7, 6])
  static let updatedUUID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

  var body: some View {
    VStack(spacing: 4) {
      Text(
        "flag=\(flag)|count=\(count)|big=\(big)|ratio=\(ratio)|single=\(single)|text=\(text)|width=\(Double(width))|url=\(link.absoluteString)|date=\(timestamp.timeIntervalSinceReferenceDate)|data=\(bytes.count)|uuid=\(identifier.uuidString)|optSome=\(optionalSome.map(String.init) ?? "nil")|optNone=\(optionalNone ?? "nil")|tags=\(tags.joined(separator: ","))|scores=\(scores["a"] ?? -1)"
      )
      Button("Mutate") {
        flag = true
        count = 42
        big = 9_000_000_000
        ratio = 3.25
        single = 1.5
        text = "reloaded"
        width = 240.5
        link = Self.updatedURL
        timestamp = Self.updatedDate
        bytes = Self.updatedData
        identifier = Self.updatedUUID
        optionalSome = 99
        optionalNone = nil
        tags = ["swift", "wasm"]
        scores = ["a": 7, "b": 8]
      }
    }
  }
}

private struct CodableAndEnumView: View {
  @State var todo = HotReloadTodo(id: 1, title: "Init", done: false)
  @State var todos: [HotReloadTodo] = []
  @State var tab: HotReloadTab = .home
  @State var optionalTab: HotReloadTab? = nil

  var body: some View {
    VStack(spacing: 4) {
      Text(
        "todo=\(todo.id):\(todo.title):\(todo.done)|count=\(todos.count)|tab=\(tab.rawValue)|optTab=\(optionalTab?.rawValue ?? "nil")"
      )
      Button("Update") {
        todo = HotReloadTodo(id: 2, title: "Shipped", done: true)
        todos = [HotReloadTodo(id: 10, title: "One", done: true)]
        tab = .settings
        optionalTab = .search
      }
    }
  }
}

private struct SiblingCounter: View {
  let label: String
  @State var count = 0

  var body: some View {
    HStack(spacing: 4) {
      Text("\(label)=\(count)")
      Button("Inc \(label)") { count += 1 }
    }
  }
}

private struct SiblingParentView: View {
  let keyedIDs = ["a/b", "c\\d"]

  var body: some View {
    VStack(spacing: 4) {
      SiblingCounter(label: "first")
      SiblingCounter(label: "second")
      ForEach(keyedIDs, id: \.self) { itemID in
        SiblingCounter(label: itemID)
      }
    }
  }
}

private struct SceneStorageWriterView: View {
  @SceneStorage("selectedTab") var selectedTab = "overview"
  @SceneStorage("draftNote") var draftNote: String?

  var body: some View {
    VStack(spacing: 4) {
      Text("writer:\(selectedTab)|\(draftNote ?? "empty")")
      Button("SaveScene") {
        selectedTab = "inspector"
        draftNote = "hello scene"
      }
    }
  }
}

private struct SceneStorageReaderView: View {
  @SceneStorage("selectedTab") var selectedTab = "overview"

  var body: some View {
    Text("reader:\(selectedTab)")
  }
}

private struct SceneStorageHostView: View {
  var body: some View {
    VStack(spacing: 4) {
      SceneStorageWriterView()
      SceneStorageReaderView()
    }
  }
}

private struct AppStorageHostView: View {
  @AppStorage var enabled: Bool
  @AppStorage var count: Int
  @AppStorage var name: String
  @AppStorage var tab: HotReloadTab
  @AppStorage var note: String?

  init(store: UserDefaults) {
    _enabled = AppStorage(wrappedValue: false, "hr.enabled", store: store)
    _count = AppStorage(wrappedValue: 0, "hr.count", store: store)
    _name = AppStorage(wrappedValue: "default", "hr.name", store: store)
    _tab = AppStorage(wrappedValue: .home, "hr.tab", store: store)
    _note = AppStorage("hr.note", store: store)
  }

  var body: some View {
    VStack(spacing: 4) {
      Text("app:\(enabled)|\(count)|\(name)|\(tab.rawValue)|\(note ?? "nil")")
      Button("WriteApp") {
        enabled = true
        count = 17
        name = "persisted"
        tab = .settings
        note = "saved"
      }
    }
  }
}

private struct NavDetailView: View {
  let title: String
  @State var detailClicks = 0

  var body: some View {
    VStack(spacing: 4) {
      Text("Detail:\(title):\(detailClicks)")
      Button("ClickDetail") { detailClicks += 1 }
    }
  }
}

private struct DynamicNavStackView: View {
  @State var path = NavigationPath()

  var body: some View {
    NavigationStack(path: $path) {
      VStack(spacing: 4) {
        Text("RootDepth:\(path.count)")
        Button("PushString") { path.append("summary") }
        Button("PushRoute") { path.append(HotReloadRoute(id: 7, title: "Profile")) }
      }
      .navigationDestination(for: String.self) { slug in
        NavDetailView(title: "str-\(slug)")
      }
      .navigationDestination(for: HotReloadRoute.self) { route in
        NavDetailView(title: "route-\(route.id)-\(route.title)")
      }
    }
  }
}

private struct TypedNavStackView: View {
  @State var routes: [HotReloadRoute] = []

  var body: some View {
    NavigationStack(path: $routes) {
      VStack(spacing: 4) {
        Text("TypedRoot:\(routes.count)")
        Button("PushTyped") { routes.append(HotReloadRoute(id: 9, title: "Billing")) }
      }
      .navigationDestination(for: HotReloadRoute.self) { route in
        NavDetailView(title: "typed-\(route.id)-\(route.title)")
      }
    }
  }
}

private struct StateObjectHostView: View {
  @StateObject var codableObj = CodableCounterObject(value: 1)
  @StateObject var nonCodableObj = NonCodableObject(token: "initial")

  var body: some View {
    VStack(spacing: 4) {
      Text("obj:\(codableObj.value)|\(nonCodableObj.token)")
      Button("BumpObj") {
        codableObj.value = 55
        nonCodableObj.token = "mutated"
        StateRegistry.shared.notifyChange()
      }
    }
  }
}

private struct ShiftedPropertiesView: View {
  @State var addedAbove = "new-default"
  @State var count = 0
  @State var changedType = "now-string"

  var body: some View {
    Text("shifted:\(addedAbove)|\(count)|\(changedType)")
  }
}

private struct ConditionalChildView: View {
  @State var showChild = false

  var body: some View {
    VStack(spacing: 4) {
      Button("ToggleChild") { showChild.toggle() }
      if showChild {
        SiblingCounter(label: "cond")
      }
    }
  }
}

@Observable
private final class UnmountModel {
  var label = "start"
}

private struct UnmountTestView: View {
  let model: UnmountModel
  @State var taps = 0

  var body: some View {
    VStack(spacing: 4) {
      Text("unmount:\(model.label):\(taps)")
      Button("Tap") { taps += 1 }
    }
  }
}

private struct LocalizedReloadView: View {
  var body: some View {
    Text(LocalizedStringKey("hr.greeting"))
  }
}

// MARK: - Tests

@MainActor
final class HotReloadTests: XCTestCase {
  override func setUp() {
    super.setUp()
    StateRegistry.shared.reset()
  }

  override func tearDown() {
    StateRegistry.shared.reset()
    XCStringsCatalog.shared.reset()
    super.tearDown()
  }

  private func findButton(named title: String, in element: Element) -> Element? {
    if element.kind == .button, element.props.text == title { return element }
    for child in element.children {
      if let found = findButton(named: title, in: child) { return found }
    }
    return nil
  }

  private func tapButton(named title: String, in renderer: Renderer, backend: FakeBackend) {
    guard let tree = renderer.tree,
          let button = findButton(named: title, in: tree)
    else {
      XCTFail("Expected button titled '\(title)'")
      return
    }
    backend.tap(button.id)
  }

  func testPrimitiveAndCollectionStatePreservedAcrossReload() async {
    let backend1 = FakeBackend()
    let renderer1 = Renderer(
      backend: backend1,
      root: AnyView(PrimitivesView()),
      size: Size(width: 400, height: 300)
    )
    renderer1.mount()
    tapButton(named: "Mutate", in: renderer1, backend: backend1)

    let expectedText = findNode(in: renderer1.tree!, kind: .text)?.props.text
    XCTAssertNotNil(expectedText)
    XCTAssertTrue(expectedText?.contains("count=42") == true)
    XCTAssertTrue(expectedText?.contains("optNone=nil") == true)

    let snapshot = StateRegistry.shared.exportHotReloadSnapshotJSON()
    renderer1.unmount()
    StateRegistry.shared.reset()

    XCTAssertTrue(StateRegistry.shared.importHotReloadSnapshot(snapshot))
    let backend2 = FakeBackend()
    let renderer2 = Renderer(
      backend: backend2,
      root: AnyView(PrimitivesView()),
      size: Size(width: 400, height: 300)
    )
    renderer2.mount()

    let restoredText = findNode(in: renderer2.tree!, kind: .text)?.props.text
    XCTAssertEqual(restoredText, expectedText)
    renderer2.unmount()
  }

  func testCodableStructAndRawRepresentableStatePreserved() async {
    let backend1 = FakeBackend()
    let renderer1 = Renderer(
      backend: backend1,
      root: AnyView(CodableAndEnumView()),
      size: Size(width: 300, height: 200)
    )
    renderer1.mount()
    tapButton(named: "Update", in: renderer1, backend: backend1)
    XCTAssertEqual(
      findNode(in: renderer1.tree!, kind: .text)?.props.text,
      "todo=2:Shipped:true|count=1|tab=settings|optTab=search"
    )

    let snapshot = StateRegistry.shared.exportHotReloadSnapshot()
    renderer1.unmount()
    StateRegistry.shared.reset()

    XCTAssertTrue(StateRegistry.shared.importHotReloadSnapshot(snapshot))
    let backend2 = FakeBackend()
    let renderer2 = Renderer(
      backend: backend2,
      root: AnyView(CodableAndEnumView()),
      size: Size(width: 300, height: 200)
    )
    renderer2.mount()

    XCTAssertEqual(
      findNode(in: renderer2.tree!, kind: .text)?.props.text,
      "todo=2:Shipped:true|count=1|tab=settings|optTab=search"
    )
    renderer2.unmount()
  }

  func testSiblingViewPathDisambiguationAndEscapedIDs() async {
    let backend1 = FakeBackend()
    let renderer1 = Renderer(
      backend: backend1,
      root: AnyView(SiblingParentView()),
      size: Size(width: 300, height: 300)
    )
    renderer1.mount()

    for _ in 0..<2 { tapButton(named: "Inc first", in: renderer1, backend: backend1) }
    for _ in 0..<5 { tapButton(named: "Inc second", in: renderer1, backend: backend1) }
    for _ in 0..<3 { tapButton(named: "Inc a/b", in: renderer1, backend: backend1) }
    for _ in 0..<4 { tapButton(named: "Inc c\\d", in: renderer1, backend: backend1) }

    let snapshot = StateRegistry.shared.exportHotReloadSnapshotJSON()
    renderer1.unmount()
    StateRegistry.shared.reset()

    XCTAssertTrue(StateRegistry.shared.importHotReloadSnapshot(snapshot))
    let backend2 = FakeBackend()
    let renderer2 = Renderer(
      backend: backend2,
      root: AnyView(SiblingParentView()),
      size: Size(width: 300, height: 300)
    )
    renderer2.mount()

    XCTAssertNotNil(findNode(in: renderer2.tree!, text: "first=2"))
    XCTAssertNotNil(findNode(in: renderer2.tree!, text: "second=5"))
    XCTAssertNotNil(findNode(in: renderer2.tree!, text: "a/b=3"))
    XCTAssertNotNil(findNode(in: renderer2.tree!, text: "c\\d=4"))
    renderer2.unmount()
  }

  func testSceneStoragePreservedAcrossReload() async {
    let backend1 = FakeBackend()
    let renderer1 = Renderer(
      backend: backend1,
      root: AnyView(SceneStorageHostView()),
      size: Size(width: 300, height: 200)
    )
    renderer1.mount()
    tapButton(named: "SaveScene", in: renderer1, backend: backend1)
    XCTAssertNotNil(findNode(in: renderer1.tree!, text: "writer:inspector|hello scene"))
    XCTAssertNotNil(findNode(in: renderer1.tree!, text: "reader:inspector"))

    let snapshot = StateRegistry.shared.exportHotReloadSnapshotJSON()
    renderer1.unmount()
    StateRegistry.shared.reset()

    XCTAssertTrue(StateRegistry.shared.importHotReloadSnapshot(snapshot))
    let backend2 = FakeBackend()
    let renderer2 = Renderer(
      backend: backend2,
      root: AnyView(SceneStorageHostView()),
      size: Size(width: 300, height: 200)
    )
    renderer2.mount()

    XCTAssertNotNil(findNode(in: renderer2.tree!, text: "writer:inspector|hello scene"))
    XCTAssertNotNil(findNode(in: renderer2.tree!, text: "reader:inspector"))
    renderer2.unmount()
  }

  func testAppStoragePreservedWhenUserDefaultsStartsEmpty() async {
    let suiteName = "HotReloadTests.\(UUID().uuidString)"
    let defaults1 = UserDefaults(suiteName: suiteName)!
    defaults1.removePersistentDomain(forName: suiteName)
    defer { defaults1.removePersistentDomain(forName: suiteName) }

    let backend1 = FakeBackend()
    let renderer1 = Renderer(
      backend: backend1,
      root: AnyView(AppStorageHostView(store: defaults1)),
      size: Size(width: 300, height: 200)
    )
    renderer1.mount()
    tapButton(named: "WriteApp", in: renderer1, backend: backend1)
    XCTAssertNotNil(findNode(in: renderer1.tree!, text: "app:true|17|persisted|settings|saved"))

    let snapshot = StateRegistry.shared.exportHotReloadSnapshotJSON()
    renderer1.unmount()
    StateRegistry.shared.reset()

    // Simulate a fresh Wasm instance whose UserDefaults starts empty.
    defaults1.removePersistentDomain(forName: suiteName)
    let defaults2 = UserDefaults(suiteName: suiteName)!

    XCTAssertTrue(StateRegistry.shared.importHotReloadSnapshot(snapshot))
    let backend2 = FakeBackend()
    let renderer2 = Renderer(
      backend: backend2,
      root: AnyView(AppStorageHostView(store: defaults2)),
      size: Size(width: 300, height: 200)
    )
    renderer2.mount()

    XCTAssertNotNil(findNode(in: renderer2.tree!, text: "app:true|17|persisted|settings|saved"))
    XCTAssertEqual(defaults2.integer(forKey: "hr.count"), 17)
    XCTAssertEqual(defaults2.string(forKey: "hr.name"), "persisted")
    renderer2.unmount()
  }

  func testNavigationPathPreservesPrimitiveAndCodableDestinationsAndChildState() async {
    // 1) Custom Codable & Hashable route inside NavigationPath + child @State
    let backend1 = FakeBackend()
    let renderer1 = Renderer(
      backend: backend1,
      root: AnyView(DynamicNavStackView()),
      size: Size(width: 400, height: 300)
    )
    renderer1.mount()
    tapButton(named: "PushRoute", in: renderer1, backend: backend1)
    XCTAssertNotNil(findNode(in: renderer1.tree!, text: "Detail:route-7-Profile:0"))
    tapButton(named: "ClickDetail", in: renderer1, backend: backend1)
    tapButton(named: "ClickDetail", in: renderer1, backend: backend1)
    XCTAssertNotNil(findNode(in: renderer1.tree!, text: "Detail:route-7-Profile:2"))

    let snapshot1 = StateRegistry.shared.exportHotReloadSnapshotJSON()
    renderer1.unmount()
    StateRegistry.shared.reset()

    XCTAssertTrue(StateRegistry.shared.importHotReloadSnapshot(snapshot1))
    let backend2 = FakeBackend()
    let renderer2 = Renderer(
      backend: backend2,
      root: AnyView(DynamicNavStackView()),
      size: Size(width: 400, height: 300)
    )
    renderer2.mount()
    XCTAssertNotNil(findNode(in: renderer2.tree!, text: "Detail:route-7-Profile:2"))
    renderer2.unmount()
    StateRegistry.shared.reset()

    // 2) Typed [HotReloadRoute] array path
    let backend3 = FakeBackend()
    let renderer3 = Renderer(
      backend: backend3,
      root: AnyView(TypedNavStackView()),
      size: Size(width: 400, height: 300)
    )
    renderer3.mount()
    tapButton(named: "PushTyped", in: renderer3, backend: backend3)
    XCTAssertNotNil(findNode(in: renderer3.tree!, text: "Detail:typed-9-Billing:0"))

    let snapshot2 = StateRegistry.shared.exportHotReloadSnapshotJSON()
    renderer3.unmount()
    StateRegistry.shared.reset()

    XCTAssertTrue(StateRegistry.shared.importHotReloadSnapshot(snapshot2))
    let backend4 = FakeBackend()
    let renderer4 = Renderer(
      backend: backend4,
      root: AnyView(TypedNavStackView()),
      size: Size(width: 400, height: 300)
    )
    renderer4.mount()
    XCTAssertNotNil(findNode(in: renderer4.tree!, text: "Detail:typed-9-Billing:0"))
    renderer4.unmount()
  }

  func testCodableAndNonCodableStateObject() async {
    let backend1 = FakeBackend()
    let renderer1 = Renderer(
      backend: backend1,
      root: AnyView(StateObjectHostView()),
      size: Size(width: 300, height: 200)
    )
    renderer1.mount()
    tapButton(named: "BumpObj", in: renderer1, backend: backend1)
    XCTAssertNotNil(findNode(in: renderer1.tree!, text: "obj:55|mutated"))

    let snapshot = StateRegistry.shared.exportHotReloadSnapshotJSON()
    renderer1.unmount()
    StateRegistry.shared.reset()

    XCTAssertTrue(StateRegistry.shared.importHotReloadSnapshot(snapshot))
    let backend2 = FakeBackend()
    let renderer2 = Renderer(
      backend: backend2,
      root: AnyView(StateObjectHostView()),
      size: Size(width: 300, height: 200)
    )
    renderer2.mount()

    // Codable @StateObject restores 55; non-Codable gracefully falls back to initial.
    XCTAssertNotNil(findNode(in: renderer2.tree!, text: "obj:55|initial"))
    renderer2.unmount()
  }

  func testGracefulTypeChangeShiftedPropertiesDeletedViewsAndCorruptJSON() async {
    // 1) Corrupt / wrong-version snapshots return false without crashing.
    XCTAssertFalse(StateRegistry.shared.importHotReloadSnapshot("not json"))
    XCTAssertFalse(StateRegistry.shared.importHotReloadSnapshot("{\"version\":999,\"states\":[],\"sceneStorage\":{},\"appStorage\":{}}"))

    // 2) Craft a snapshot simulating:
    //    - `_count` previously at property index 0 (now shifted to index 1 by `addedAbove`)
    //    - `_changedType` previously `Swift.Int` (now `Swift.String`)
    //    - a deleted view entry that no longer exists
    let ownerName = HotReloadCodec.normalizeTypeName(String(reflecting: ShiftedPropertiesView.self))
    let craftedJSON = """
    {
      "version": 1,
      "states": [
        {
          "path": "",
          "owner": "\(ownerName)",
          "property": 0,
          "label": "_count",
          "value": {
            "kind": "codable",
            "typeName": "Swift.Int",
            "payload": "{\\"v\\":77}"
          }
        },
        {
          "path": "",
          "owner": "\(ownerName)",
          "property": 1,
          "label": "_changedType",
          "value": {
            "kind": "codable",
            "typeName": "Swift.Int",
            "payload": "{\\"v\\":123}"
          }
        },
        {
          "path": "i:99",
          "owner": "DeletedModule.DeletedView",
          "property": 0,
          "label": "_gone",
          "value": {
            "kind": "codable",
            "typeName": "Swift.String",
            "payload": "{\\"v\\":\\"stale\\"}"
          }
        }
      ],
      "sceneStorage": {},
      "appStorage": {}
    }
    """

    XCTAssertTrue(StateRegistry.shared.importHotReloadSnapshot(craftedJSON))
    let backend = FakeBackend()
    let renderer = Renderer(
      backend: backend,
      root: AnyView(ShiftedPropertiesView()),
      size: Size(width: 300, height: 200)
    )
    renderer.mount()

    // `addedAbove` keeps its default, `count` restores 77 despite index shift,
    // `changedType` ignores Int->String mismatch and keeps "now-string".
    XCTAssertNotNil(findNode(in: renderer.tree!, text: "shifted:new-default|77|now-string"))
    // Pending buffer was automatically cleared at the end of mount().
    XCTAssertNil(StateRegistry.shared.pendingHotReload)
    renderer.unmount()
  }

  func testUnconsumedPendingEntriesClearedAfterInitialMount() async {
    let backend1 = FakeBackend()
    let renderer1 = Renderer(
      backend: backend1,
      root: AnyView(ConditionalChildView()),
      size: Size(width: 300, height: 200)
    )
    renderer1.mount()
    tapButton(named: "ToggleChild", in: renderer1, backend: backend1)
    tapButton(named: "Inc cond", in: renderer1, backend: backend1)
    tapButton(named: "Inc cond", in: renderer1, backend: backend1)
    XCTAssertNotNil(findNode(in: renderer1.tree!, text: "cond=2"))

    // Snapshot while child is mounted, then strip `showChild` so child does NOT mount initially.
    let rawData = StateRegistry.shared.exportHotReloadSnapshot()
    let jsonObj = try! JSONSerialization.jsonObject(with: rawData) as! [String: Any]
    let states = (jsonObj["states"] as! [[String: Any]]).filter { ($0["label"] as? String) != "_showChild" }
    var modified = jsonObj
    modified["states"] = states
    let modifiedData = try! JSONSerialization.data(withJSONObject: modified)

    renderer1.unmount()
    StateRegistry.shared.reset()

    XCTAssertTrue(StateRegistry.shared.importHotReloadSnapshot(modifiedData))
    let backend2 = FakeBackend()
    let renderer2 = Renderer(
      backend: backend2,
      root: AnyView(ConditionalChildView()),
      size: Size(width: 300, height: 200)
    )
    renderer2.mount()
    // Child was not mounted during initial pass; pending entries should now be cleared.
    tapButton(named: "ToggleChild", in: renderer2, backend: backend2)
    XCTAssertNotNil(findNode(in: renderer2.tree!, text: "cond=0"))
    renderer2.unmount()
  }

  func testPrivateTypeNameNormalization() async {
    XCTAssertEqual(
      HotReloadCodec.normalizeTypeName("MyApp.(unknown context at $104a3b2c0).CounterView"),
      "MyApp.(private).CounterView"
    )
    XCTAssertEqual(
      HotReloadCodec.normalizeTypeName(
        "Swift.Array<MyApp.(unknown context at $100ab).Row<MyApp.(unknown context at 0xdeadbeef).Item>>"
      ),
      "Swift.Array<MyApp.(private).Row<MyApp.(private).Item>>"
    )
    XCTAssertEqual(
      HotReloadCodec.normalizeTypeName("MyApp.PublicView"),
      "MyApp.PublicView"
    )
  }

  func testRendererUnmountDetachesHandlersAndSupportsCleanRemount() async {
    let model = UnmountModel()
    let backend = FakeBackend()
    let renderer = Renderer(
      backend: backend,
      root: AnyView(UnmountTestView(model: model)),
      size: Size(width: 300, height: 200)
    )
    renderer.mount()
    XCTAssertNotNil(renderer.tree)
    XCTAssertNotNil(backend.tapHandler)

    tapButton(named: "Tap", in: renderer, backend: backend)
    XCTAssertNotNil(findNode(in: renderer.tree!, text: "unmount:start:1"))

    backend.reset()
    renderer.unmount()

    XCTAssertNil(renderer.tree)
    XCTAssertNil(backend.tapHandler)
    XCTAssertEqual(backend.removedIDs.count, 1)

    // Idempotent unmount and safe no-ops while unmounted.
    renderer.unmount()
    model.label = "changed"
    renderer.setNeedsRender()
    renderer.renderIfNeeded()
    XCTAssertNil(renderer.tree)

    // Clean remount on the same renderer re-attaches handlers and renders updated model.
    renderer.mount()
    XCTAssertNotNil(renderer.tree)
    XCTAssertNotNil(backend.tapHandler)
    XCTAssertNotNil(findNode(in: renderer.tree!, text: "unmount:changed:1"))
    tapButton(named: "Tap", in: renderer, backend: backend)
    XCTAssertNotNil(findNode(in: renderer.tree!, text: "unmount:changed:2"))
    renderer.unmount()

    // Mounting a fresh renderer after teardown starts with fresh view state.
    let backend2 = FakeBackend()
    let renderer2 = Renderer(
      backend: backend2,
      root: AnyView(UnmountTestView(model: model)),
      size: Size(width: 300, height: 200)
    )
    renderer2.mount()
    XCTAssertNotNil(findNode(in: renderer2.tree!, text: "unmount:changed:0"))
    renderer2.unmount()
  }

  func testRendererReloadResourcesUpdatesXCStrings() async {
    XCStringsCatalog.shared.preferredLanguage = "en"
    let v1 = """
    {
      "sourceLanguage": "en",
      "strings": {
        "hr.greeting": {
          "localizations": {
            "en": { "stringUnit": { "state": "translated", "value": "Hello v1" } }
          }
        }
      }
    }
    """
    XCTAssertTrue(XCStringsCatalog.shared.load(data: Data(v1.utf8), merge: false))

    let backend = FakeBackend()
    let renderer = Renderer(
      backend: backend,
      root: AnyView(LocalizedReloadView()),
      size: Size(width: 300, height: 100)
    )
    renderer.mount()
    XCTAssertNotNil(findNode(in: renderer.tree!, text: "Hello v1"))

    let v2 = """
    {
      "sourceLanguage": "en",
      "strings": {
        "hr.greeting": {
          "localizations": {
            "en": { "stringUnit": { "state": "translated", "value": "Hello v2 Updated" } }
          }
        }
      }
    }
    """
    XCStringsCatalog.shared.reset()
    XCTAssertTrue(XCStringsCatalog.shared.load(data: Data(v2.utf8), merge: true))
    renderer.reloadResources()

    XCTAssertNotNil(findNode(in: renderer.tree!, text: "Hello v2 Updated"))
    renderer.unmount()
  }
}
