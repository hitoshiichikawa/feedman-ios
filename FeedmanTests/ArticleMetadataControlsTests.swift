import XCTest
#if canImport(UIKit)
import SwiftUI
import UIKit
#endif
@testable import Feedman

final class ArticleMetadataControlsTests: XCTestCase {
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

    #if canImport(UIKit)
    @MainActor
    func testStarActivationCallsOnlyCallerProvidedAction() throws {
        var starActionCount = 0
        var cardOpenActionCount = 0
        let harness = TappableArticleCardInteractionHarness(
            onOpenArticle: {
                cardOpenActionCount += 1
            },
            accessory: {
                ArticleStarControl(isStarred: false) {
                    starActionCount += 1
                }
            }
        )

        let didActivate = try activateAccessibilityElement(
            labeled: "スターを付ける",
            in: harness
        )

        XCTAssertTrue(didActivate)
        XCTAssertEqual(starActionCount, 1)
        XCTAssertEqual(cardOpenActionCount, 0)
    }
    #endif

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

    #if canImport(UIKit)
    @MainActor
    func testOpenLinkDescriptorCallsOnlyCallerProvidedActionWithValue() throws {
        var openedLink: String?
        var cardOpenActionCount = 0
        let harness = TappableArticleCardInteractionHarness(
            onOpenArticle: {
                cardOpenActionCount += 1
            },
            accessory: {
                ArticleOpenLinkControl(value: "https://example.com/article") { link in
                    openedLink = link
                }
            }
        )

        let didActivate = try activateAccessibilityElement(
            labeled: "元記事をブラウザで開く",
            in: harness
        )

        XCTAssertTrue(didActivate)
        XCTAssertEqual(openedLink, "https://example.com/article")
        XCTAssertEqual(cardOpenActionCount, 0)
    }
    #endif

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

#if canImport(UIKit)
private struct TappableArticleCardInteractionHarness<Accessory: View>: View {
    let onOpenArticle: () -> Void
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 12) {
            Text("Article title")
                .lineLimit(2)

            Spacer(minLength: 12)

            accessory()
        }
        .padding(12)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpenArticle)
        .accessibilityElement(children: .contain)
    }
}

@MainActor
private func activateAccessibilityElement<Content: View>(
    labeled label: String,
    in rootView: Content
) throws -> Bool {
    let hostingController = UIHostingController(rootView: rootView)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.rootViewController = hostingController
    window.makeKeyAndVisible()
    defer {
        window.isHidden = true
    }

    hostingController.view.setNeedsLayout()
    hostingController.view.layoutIfNeeded()

    guard let element = hostingController.view.firstAccessibilityElement(labeled: label) else {
        throw ArticleControlInteractionHarnessError.missingAccessibilityElement(label)
    }

    return element.accessibilityActivate()
}

private enum ArticleControlInteractionHarnessError: Error, CustomStringConvertible {
    case missingAccessibilityElement(String)

    var description: String {
        switch self {
        case .missingAccessibilityElement(let label):
            return "Missing accessibility element labeled \(label)"
        }
    }
}

private extension UIView {
    func firstAccessibilityElement(labeled label: String) -> NSObject? {
        var visitedElements = Set<ObjectIdentifier>()
        return firstAccessibilityElement(labeled: label, visitedElements: &visitedElements)
    }

    func firstAccessibilityElement(
        labeled label: String,
        visitedElements: inout Set<ObjectIdentifier>
    ) -> NSObject? {
        let identifier = ObjectIdentifier(self)
        guard visitedElements.insert(identifier).inserted else {
            return nil
        }

        if isAccessibilityElement, accessibilityLabel == label {
            return self
        }

        if let match = accessibilityElements?.compactMap({
            firstAccessibilityElement(
                labeled: label,
                in: $0,
                visitedElements: &visitedElements
            )
        }).first {
            return match
        }

        let elementCount = accessibilityElementCount()
        if elementCount > 0, elementCount != NSNotFound {
            for index in 0..<elementCount {
                guard let element = accessibilityElement(at: index) else {
                    continue
                }

                if let match = firstAccessibilityElement(
                    labeled: label,
                    in: element,
                    visitedElements: &visitedElements
                ) {
                    return match
                }
            }
        }

        for subview in subviews {
            if let match = subview.firstAccessibilityElement(
                labeled: label,
                visitedElements: &visitedElements
            ) {
                return match
            }
        }

        return nil
    }

    func firstAccessibilityElement(
        labeled label: String,
        in element: Any,
        visitedElements: inout Set<ObjectIdentifier>
    ) -> NSObject? {
        if let view = element as? UIView {
            return view.firstAccessibilityElement(
                labeled: label,
                visitedElements: &visitedElements
            )
        }

        guard let object = element as? NSObject else {
            return nil
        }

        let identifier = ObjectIdentifier(object)
        guard visitedElements.insert(identifier).inserted else {
            return nil
        }

        return object.accessibilityLabel == label ? object : nil
    }
}
#endif
