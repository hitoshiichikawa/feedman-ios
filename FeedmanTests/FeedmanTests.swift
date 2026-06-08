import XCTest
@testable import Feedman

final class FeedmanTests: XCTestCase {
    func testMockRepositoryReturnsTimelineItems() async throws {
        let repository = MockFeedRepository()

        let items = try await repository.crossFeedItems()

        XCTAssertFalse(items.isEmpty)
        XCTAssertEqual(items.first?.feedTitle, "Publickey")
    }
}

