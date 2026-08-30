import XCTest
@testable import Nile

final class TranscriptImagePayloadCacheTests: XCTestCase {
    func testEntryAndCharacterLimitsEvictOldestImages() {
        var cache = TranscriptImagePayloadCache(
            maximumEntryCount: 2,
            maximumBase64CharacterCount: 5
        )

        cache.remember(path: "a", base64: "aa")
        cache.remember(path: "b", base64: "bb")
        cache.remember(path: "c", base64: "cc")
        XCTAssertEqual(cache.images, ["b": "bb", "c": "cc"])

        cache.remember(path: "huge", base64: "123456")
        XCTAssertEqual(cache.images, ["b": "bb", "c": "cc"])
        cache.removeAll()
        XCTAssertTrue(cache.images.isEmpty)
    }

    func testReplacementRefreshesRecencyAndOversizedReplacementRemovesOldValue() {
        var cache = TranscriptImagePayloadCache(
            maximumEntryCount: 2,
            maximumBase64CharacterCount: 5
        )
        cache.remember(path: "a", base64: "aa")
        cache.remember(path: "b", base64: "bb")

        cache.remember(path: "a", base64: "x")
        cache.remember(path: "c", base64: "cc")
        XCTAssertEqual(cache.images, ["a": "x", "c": "cc"])

        cache.remember(path: "a", base64: "123456")
        XCTAssertEqual(cache.images, ["c": "cc"])
    }

    func testCharacterPressureAndDisabledLimitsFailClosed() {
        var cache = TranscriptImagePayloadCache(
            maximumEntryCount: 3,
            maximumBase64CharacterCount: 4
        )
        cache.remember(path: "a", base64: "aa")
        cache.remember(path: "b", base64: "bb")
        cache.remember(path: "c", base64: "x")
        XCTAssertEqual(cache.images, ["b": "bb", "c": "x"])

        var disabled = TranscriptImagePayloadCache(
            maximumEntryCount: -1,
            maximumBase64CharacterCount: -1
        )
        disabled.remember(path: "empty", base64: "")
        disabled.remember(path: "value", base64: "a")
        XCTAssertTrue(disabled.images.isEmpty)
    }
}
