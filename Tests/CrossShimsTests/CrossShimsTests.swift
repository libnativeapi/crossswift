#if !os(macOS)
  import Combine
  import CrossSwiftUI
  import Foundation
  import Security
  import SwiftUIRuntime
  import XCTest

  private enum ShimTestError: Error, Equatable {
    case boom
  }

  private final class PublishedCounterModel: ObservableObject {
    @Published var count: Int = 0
  }

  final class CrossShimsTests: XCTestCase {
    func testCombineCorePublishersAndOperators() {
      var mapped: [Int] = []
      let c1 = [1, 1, 2, 3, 4, 5].publisher
        .removeDuplicates()
        .filter { $0 % 2 == 1 }
        .map { $0 * 10 }
        .sink { mapped.append($0) }
      XCTAssertEqual(mapped, [10, 30, 50])
      c1.cancel()

      var scanned: [Int] = []
      let c2 = [1, 2, 3].publisher
        .scan(0, +)
        .sink { scanned.append($0) }
      XCTAssertEqual(scanned, [1, 3, 6])
      c2.cancel()

      var replaced: [String] = []
      let c3 = Fail<String, ShimTestError>(error: .boom)
        .replaceError(with: "fallback")
        .sink { replaced.append($0) }
      XCTAssertEqual(replaced, ["fallback"])
      c3.cancel()
    }

    func testCombineSubjectsCombineLatestMergeAndZip() {
      let left = PassthroughSubject<Int, Never>()
      let right = CurrentValueSubject<String, Never>("a")
      var pairs: [String] = []
      let c1 = left.combineLatest(right)
        .map { "\($0)-\($1)" }
        .sink { pairs.append($0) }

      left.send(1)
      right.send("b")
      left.send(2)
      XCTAssertEqual(pairs, ["1-a", "1-b", "2-b"])
      c1.cancel()

      let p1 = PassthroughSubject<Int, Never>()
      let p2 = PassthroughSubject<Int, Never>()
      var zipped: [Int] = []
      let c2 = p1.zip(p2).map(+).sink { zipped.append($0) }
      p1.send(10)
      p1.send(20)
      p2.send(1)
      p2.send(2)
      XCTAssertEqual(zipped, [11, 22])
      c2.cancel()

      var merged: [Int] = []
      let c3 = Just(7).merge(with: Just(9)).sink { merged.append($0) }
      XCTAssertEqual(merged, [7, 9])
      c3.cancel()
    }

    func testPublishedProjectedValueConformsToCombinePublisher() {
      let model = PublishedCounterModel()
      var observed: [Int] = []
      let cancellable = model.$count.map { $0 + 1 }.sink { observed.append($0) }
      model.count = 4
      model.count = 9
      XCTAssertEqual(observed, [1, 5, 10])
      cancellable.cancel()
      model.count = 15
      XCTAssertEqual(observed, [1, 5, 10])
    }

    func testSecurityKeychainCRUDAndRandomBytes() {
      let service = "dev.crossswift.test.\(UUID().uuidString)"
      let account = "unit-test-account"
      let initialSecret = Data("secret-v1".utf8)
      let updatedSecret = Data("secret-v2".utf8)

      let addQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecValueData as String: initialSecret,
      ]
      XCTAssertEqual(SecItemAdd(addQuery as CFDictionary, nil), errSecSuccess)
      XCTAssertEqual(SecItemAdd(addQuery as CFDictionary, nil), errSecDuplicateItem)

      let copyQuery: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecReturnData as String: true,
      ]
      var copyResult: AnyObject?
      XCTAssertEqual(SecItemCopyMatching(copyQuery as CFDictionary, &copyResult), errSecSuccess)
      XCTAssertEqual(copyResult as? Data, initialSecret)

      let updateMatch: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
      ]
      let updateAttrs: [String: Any] = [
        kSecValueData as String: updatedSecret
      ]
      XCTAssertEqual(
        SecItemUpdate(updateMatch as CFDictionary, updateAttrs as CFDictionary),
        errSecSuccess
      )

      var updatedResult: AnyObject?
      XCTAssertEqual(SecItemCopyMatching(copyQuery as CFDictionary, &updatedResult), errSecSuccess)
      XCTAssertEqual(updatedResult as? Data, updatedSecret)

      XCTAssertEqual(SecItemDelete(updateMatch as CFDictionary), errSecSuccess)
      XCTAssertEqual(SecItemDelete(updateMatch as CFDictionary), errSecItemNotFound)

      var bytes = [UInt8](repeating: 0, count: 32)
      let randStatus = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
      XCTAssertEqual(randStatus, errSecSuccess)
      XCTAssertTrue(bytes.contains { $0 != 0 })
    }
  }
#endif
