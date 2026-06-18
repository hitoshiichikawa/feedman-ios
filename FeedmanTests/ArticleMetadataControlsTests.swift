import XCTest
import SwiftUI
@testable import Feedman

final class ArticleMetadataControlsTests: XCTestCase {
    func testAccessibilityLayoutStacksControlsOnlyForAccessibilityDynamicType() {
        XCTAssertFalse(FeedmanAccessibilityLayout.usesStackedControls(for: .large))
        XCTAssertFalse(FeedmanAccessibilityLayout.usesStackedControls(for: .xxxLarge))
        XCTAssertTrue(FeedmanAccessibilityLayout.usesStackedControls(for: .accessibility1))
        XCTAssertTrue(FeedmanAccessibilityLayout.usesStackedControls(for: .accessibility5))
    }

    func testAccessibilityLayoutAllowsPrimaryActionsToGrowAtAccessibilitySizes() {
        XCTAssertEqual(FeedmanAccessibilityLayout.primaryActionLineLimit(for: .large), 2)
        XCTAssertNil(FeedmanAccessibilityLayout.primaryActionLineLimit(for: .accessibility3))
    }

    func testStarDescriptorUsesFilledStarAndSelectedAccessibilityWhenStarred() {
        let descriptor = ArticleStarControlDescriptor(isStarred: true)

        XCTAssertEqual(descriptor.systemImageName, "star.fill")
        XCTAssertEqual(descriptor.colorRole, .star)
        XCTAssertEqual(descriptor.accessibilityLabel, "スターを解除")
        XCTAssertEqual(descriptor.accessibilityValue, "オン")
        XCTAssertTrue(descriptor.isSelected)
    }

    func testStarDescriptorUsesUnfilledStarAndInactiveAccessibilityWhenUnstarred() {
        let descriptor = ArticleStarControlDescriptor(isStarred: false)

        XCTAssertEqual(descriptor.systemImageName, "star")
        XCTAssertEqual(descriptor.colorRole, .mutedForeground)
        XCTAssertEqual(descriptor.accessibilityLabel, "スターを付ける")
        XCTAssertEqual(descriptor.accessibilityValue, "オフ")
        XCTAssertFalse(descriptor.isSelected)
    }

    func testEnabledStarActivationCallsCallerProvidedActionOnce() {
        let descriptor = ArticleStarControlDescriptor(isStarred: false)
        var starActionCount = 0

        descriptor.activate {
            starActionCount += 1
        }

        XCTAssertEqual(starActionCount, 1)
    }

    func testDisabledStarDoesNotCallActionAndCommunicatesDisabledState() {
        let descriptor = ArticleStarControlDescriptor(
            isStarred: true,
            isEnabled: false
        )
        var actionCount = 0

        descriptor.activate {
            actionCount += 1
        }

        XCTAssertEqual(actionCount, 0)
        XCTAssertEqual(descriptor.accessibilityHint, "操作できません")
    }

    func testStarTouchTargetIsStableAcrossSizes() {
        XCTAssertEqual(ArticleMetadataControlSize.compact.touchTarget, 44)
        XCTAssertEqual(ArticleMetadataControlSize.standard.touchTarget, 44)
        XCTAssertEqual(ArticleMetadataControlSize.timeline.touchTarget, 44)
    }

    func testHatebuUnavailableStateUsesPlaceholderWithoutImplyingZero() {
        let descriptor = ArticleHatebuCountDescriptor(
            count: nil,
            isFetched: false
        )

        XCTAssertEqual(descriptor.state, .unavailable)
        XCTAssertEqual(descriptor.displayText, "-")
        XCTAssertEqual(descriptor.colorRole, .mutedForeground)
        XCTAssertEqual(descriptor.accessibilityLabel, "はてなブックマーク未取得")
        XCTAssertFalse(descriptor.isHot)
    }

    func testHatebuZeroCountStaysDistinctFromUnavailableState() {
        let descriptor = ArticleHatebuCountDescriptor(
            count: 0,
            isFetched: true
        )

        XCTAssertEqual(descriptor.state, .available(0))
        XCTAssertEqual(descriptor.displayText, "0")
        XCTAssertEqual(descriptor.accessibilityLabel, "はてなブックマーク 0 件")
        XCTAssertFalse(descriptor.isHot)
    }

    func testHatebuHotStateStartsAtOneHundred() {
        let muted = ArticleHatebuCountDescriptor(count: 99, isFetched: true)
        let hot = ArticleHatebuCountDescriptor(count: 100, isFetched: true)

        XCTAssertEqual(muted.colorRole, .mutedForeground)
        XCTAssertFalse(muted.isHot)
        XCTAssertEqual(hot.colorRole, .accent)
        XCTAssertTrue(hot.isHot)
    }

    func testSourceMetadataPreservesOptionalFaviconAndRelativeDateInputs() {
        let metadata = ArticleSourceMetadata(
            feedTitle: "Very Long Feed Title",
            faviconURL: "data:image/png;base64,abc",
            relativeDate: "3分前"
        )

        XCTAssertEqual(metadata.feedTitle, "Very Long Feed Title")
        XCTAssertEqual(metadata.faviconURL, "data:image/png;base64,abc")
        XCTAssertEqual(metadata.relativeDate, "3分前")
        XCTAssertEqual(ArticleMetadataControlSize.standard.faviconSize, 24)
    }

    func testEnabledOpenLinkActivationPassesValueToCallerProvidedAction() {
        let descriptor = ArticleOpenLinkControlDescriptor(isOpenable: true)
        var openedLink: String?

        descriptor.activate(value: "https://example.com/article") { link in
            openedLink = link
        }

        XCTAssertEqual(openedLink, "https://example.com/article")
    }

    func testEnabledOpenLinkDescriptorExposesOriginalArticleSemantics() {
        let descriptor = ArticleOpenLinkControlDescriptor(isOpenable: true)

        XCTAssertEqual(descriptor.systemImageName, "arrow.up.forward.square")
        XCTAssertEqual(descriptor.accessibilityLabel, "元記事をブラウザで開く")
        XCTAssertNil(descriptor.accessibilityHint)
        XCTAssertTrue(descriptor.isEnabled)
        XCTAssertFalse(descriptor.isHidden)
    }

    func testDisabledOpenLinkDoesNotCallAction() {
        let descriptor = ArticleOpenLinkControlDescriptor(isOpenable: false)
        var actionCount = 0

        descriptor.activate(value: Optional<String>.none) { _ in
            actionCount += 1
        }

        XCTAssertFalse(descriptor.isEnabled)
        XCTAssertFalse(descriptor.isHidden)
        XCTAssertEqual(descriptor.accessibilityHint, "リンクを開けません")
        XCTAssertEqual(actionCount, 0)
    }

    func testHiddenOpenLinkUnavailableStateCanBeChosenByCaller() {
        let descriptor = ArticleOpenLinkControlDescriptor(
            isOpenable: false,
            unavailableBehavior: .hidden
        )
        var actionCount = 0

        descriptor.activate(value: "https://example.com/article") { _ in
            actionCount += 1
        }

        XCTAssertTrue(descriptor.isHidden)
        XCTAssertEqual(actionCount, 0)
    }
}
