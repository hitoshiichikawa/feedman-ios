import XCTest
@testable import Feedman

@MainActor
final class ItemStateCoordinatorTests: XCTestCase {
    func testEffectiveStateUsesRepositoryValuesWithoutOverlay() {
        let coordinator = ItemStateCoordinator()

        let snapshot = coordinator.effectiveState(
            itemID: "item-1",
            baseRead: false,
            baseStarred: true
        )

        XCTAssertFalse(snapshot.isRead)
        XCTAssertTrue(snapshot.isStarred)
        XCTAssertFalse(snapshot.isReadPending)
        XCTAssertFalse(snapshot.isStarredPending)
    }

    func testPendingOptimisticValueOverridesRepositoryValues() throws {
        let coordinator = ItemStateCoordinator()

        let token = try XCTUnwrap(coordinator.beginMutation(
            itemID: "item-1",
            baseRead: false,
            baseStarred: false,
            isRead: true,
            isStarred: true
        ))

        let snapshot = coordinator.effectiveState(
            itemID: "item-1",
            baseRead: false,
            baseStarred: false
        )
        XCTAssertTrue(snapshot.isRead)
        XCTAssertTrue(snapshot.isStarred)
        XCTAssertTrue(snapshot.isReadPending)
        XCTAssertTrue(snapshot.isStarredPending)
        XCTAssertTrue(coordinator.isPending(itemID: "item-1", field: .read))
        XCTAssertTrue(coordinator.isPending(itemID: "item-1", field: .starred))

        coordinator.commitMutation(token)
    }

    func testCommitKeepsConfirmedLocalValueForLaterStaleRefresh() throws {
        let coordinator = ItemStateCoordinator()
        let token = try XCTUnwrap(coordinator.beginMutation(
            itemID: "item-1",
            baseRead: false,
            baseStarred: false,
            isStarred: true
        ))

        coordinator.commitMutation(token)

        let snapshot = coordinator.effectiveState(
            itemID: "item-1",
            baseRead: false,
            baseStarred: false
        )
        XCTAssertFalse(snapshot.isRead)
        XCTAssertTrue(snapshot.isStarred)
        XCTAssertFalse(snapshot.isStarredPending)
    }

    func testRollbackRestoresOnlyMatchingFieldPreviousValue() throws {
        let coordinator = ItemStateCoordinator()
        let readToken = try XCTUnwrap(coordinator.beginMutation(
            itemID: "item-1",
            baseRead: false,
            baseStarred: false,
            isRead: true
        ))
        let starToken = try XCTUnwrap(coordinator.beginMutation(
            itemID: "item-1",
            baseRead: false,
            baseStarred: false,
            isStarred: true
        ))

        coordinator.commitMutation(starToken)
        coordinator.rollbackMutation(readToken)

        let snapshot = coordinator.effectiveState(
            itemID: "item-1",
            baseRead: false,
            baseStarred: false
        )
        XCTAssertFalse(snapshot.isRead)
        XCTAssertTrue(snapshot.isStarred)
        XCTAssertFalse(snapshot.isReadPending)
        XCTAssertFalse(snapshot.isStarredPending)
    }

    func testStaleRefreshDoesNotErasePendingOptimisticValue() throws {
        let coordinator = ItemStateCoordinator()
        _ = try XCTUnwrap(coordinator.beginMutation(
            itemID: "item-1",
            baseRead: false,
            baseStarred: false,
            isRead: true
        ))

        let staleSnapshot = coordinator.effectiveState(
            itemID: "item-1",
            baseRead: false,
            baseStarred: false
        )

        XCTAssertTrue(staleSnapshot.isRead)
        XCTAssertTrue(staleSnapshot.isReadPending)
    }

    func testSameFieldPendingRejectsSecondMutation() throws {
        let coordinator = ItemStateCoordinator()
        _ = try XCTUnwrap(coordinator.beginMutation(
            itemID: "item-1",
            baseRead: false,
            baseStarred: false,
            isStarred: true
        ))

        let secondToken = coordinator.beginMutation(
            itemID: "item-1",
            baseRead: false,
            baseStarred: false,
            isStarred: false
        )

        XCTAssertNil(secondToken)
    }
}
