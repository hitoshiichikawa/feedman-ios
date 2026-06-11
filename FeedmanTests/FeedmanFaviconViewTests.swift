import XCTest
@testable import Feedman

final class FeedmanFaviconViewTests: XCTestCase {
    func testValidImageDataURLDecodesPayload() throws {
        let payload = try XCTUnwrap(FaviconDataURLDecoder.payload(from: validPNGDataURL))

        XCTAssertEqual(payload.mimeType, "image/png")
        XCTAssertFalse(payload.data.isEmpty)
    }

    func testValidImageDataURLCreatesImage() {
        XCTAssertNotNil(FaviconDataURLDecoder.image(from: validPNGDataURL))
    }

    func testNilSourceFallsBackByReturningNoPayload() {
        XCTAssertNil(FaviconDataURLDecoder.payload(from: nil))
    }

    func testEmptySourceFallsBackByReturningNoPayload() {
        XCTAssertNil(FaviconDataURLDecoder.payload(from: ""))
    }

    func testNonDataURLFallsBackByReturningNoPayload() {
        XCTAssertNil(FaviconDataURLDecoder.payload(from: "https://example.com/favicon.png"))
    }

    func testDataURLWithoutBase64PayloadFallsBackByReturningNoPayload() {
        XCTAssertNil(FaviconDataURLDecoder.payload(from: "data:image/png,abc"))
    }

    func testInvalidBase64FallsBackByReturningNoPayload() {
        XCTAssertNil(FaviconDataURLDecoder.payload(from: "data:image/png;base64,not base64"))
    }

    func testNonImageMimeTypeFallsBackByReturningNoPayload() {
        XCTAssertNil(FaviconDataURLDecoder.payload(from: "data:text/plain;base64,SGVsbG8="))
    }

    func testDecodedNonImageDataFallsBackByReturningNoImage() {
        XCTAssertNil(FaviconDataURLDecoder.image(from: "data:image/png;base64,SGVsbG8="))
    }

    func testLetterUsesFirstCharacterFromTrimmedDisplayName() {
        XCTAssertEqual(LetterAvatarDescriptor.letter(from: " Feedman Blog "), "F")
    }

    func testLetterUsesQuestionMarkForBlankDisplayName() {
        XCTAssertEqual(LetterAvatarDescriptor.letter(from: "   "), "?")
        XCTAssertEqual(LetterAvatarDescriptor.letter(from: nil), "?")
    }

    func testLetterUsesFirstUserVisibleCharacter() {
        XCTAssertEqual(LetterAvatarDescriptor.letter(from: "📰 News"), "📰")
    }

    func testBackgroundColorIsDeterministicForSameDisplayName() {
        let first = LetterAvatarDescriptor.backgroundColor(for: "Feedman Blog")
        let second = LetterAvatarDescriptor.backgroundColor(for: "Feedman Blog")

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.hexString, "#059669")
    }

    func testBackgroundColorDistributesDifferentDisplayNames() {
        let colors = [
            LetterAvatarDescriptor.backgroundColor(for: "Feedman Blog"),
            LetterAvatarDescriptor.backgroundColor(for: "Publickey"),
            LetterAvatarDescriptor.backgroundColor(for: "Swift News"),
            LetterAvatarDescriptor.backgroundColor(for: "Backend Weekly")
        ]

        XCTAssertGreaterThan(Set(colors.map(\.hexString)).count, 1)
    }

    private let validPNGDataURL =
        "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/p9sAAAAASUVORK5CYII="
}
