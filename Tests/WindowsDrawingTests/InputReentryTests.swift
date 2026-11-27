import CSwiftUIWindowsTestSupport
import XCTest

final class InputReentryTests: XCTestCase {
  func testNativeInputDoesNotReachReplacementPeer() {
    XCTAssertEqual(input_reentry_probe(), 0)
  }
}
