import CrossSwiftUI
import NativeAPI
import SwiftUIRuntime
import WinSDK
import XCTest

final class ScrollPositionTests: XCTestCase {
  @MainActor
  func testDPIRefreshKeepsTranslatedControlAtItsScrolledPosition() async throws {
    WindowsDrawingBackend.prepareApplication()
    let window = try XCTUnwrap(NativeAPI.Window.create())
    defer { _ = window.close() }
    window.setContentSize(.init(width: 640, height: 480))
    let backend = try XCTUnwrap(WindowsDrawingBackend(window: window))
    let content = SwiftUIRuntime.ScrollView {
      VStack(spacing: 0) {
        ForEach(0..<40, id: \.self) { i in
          SwiftUIRuntime.Button("Row \(i)") {}.frame(height: 32)
        }
      }
    }
    let renderer = Renderer(backend: backend, root: AnyView(content), size: .init(width: 640, height: 480))
    renderer.mount()
    defer { renderer.unmount() }

    func findControl(_ node: Element) -> UnsafeMutableRawPointer? {
      if (100...220).contains(node.frame.minY), let handle = backend.nativeButton(node.id)?.nativeObject {
        return handle
      }
      for child in node.children {
        if let handle = findControl(child) { return handle }
      }
      return nil
    }
    let control = try XCTUnwrap(findControl(XCTUnwrap(renderer.tree))).assumingMemoryBound(to: HWND__.self)
    let host = try XCTUnwrap(window.contentView?.nativeObject).assumingMemoryBound(to: HWND__.self)
    func top() -> LONG {
      var bounds = RECT()
      XCTAssertTrue(GetWindowRect(control, &bounds))
      return bounds.top
    }

    let initial = top()
    let publications = backend.fullPublicationCount
    XCTAssertTrue(renderer.input(event: 5, point: CGPoint(x: 30, y: 155), value: -30))
    let scrolled = top()
    XCTAssertLessThan(scrolled, initial)
    XCTAssertEqual(backend.fullPublicationCount, publications)
    SendMessageW(host, UINT(WM_DPICHANGED_AFTERPARENT), 0, 0)
    XCTAssertEqual(backend.fullPublicationCount, publications + 1)
    XCTAssertEqual(top(), scrolled)
  }
}
