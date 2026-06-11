import SwiftUI
import XCTest
@testable import Feedman

final class FeedmanTests: XCTestCase {
    func testMockRepositoryReturnsTimelineItems() async throws {
        let repository = MockFeedRepository()

        let items = try await repository.crossFeedItems()

        XCTAssertFalse(items.isEmpty)
        XCTAssertEqual(items.first?.feedTitle, "Publickey")
    }

    func testFeedmanThemeLightTokensMatchIndigoPrototypeValues() {
        let tokens = FeedmanTheme.resolvedTokens(for: .light)

        XCTAssertEqual(tokens.background.hexString, "#FAFAFA")
        XCTAssertEqual(tokens.surface.hexString, "#FFFFFF")
        XCTAssertEqual(tokens.surfaceSecondary.hexString, "#F7F7F7")
        XCTAssertEqual(tokens.foreground.hexString, "#171717")
        XCTAssertEqual(tokens.muted.hexString, "#F5F5F5")
        XCTAssertEqual(tokens.mutedForeground.hexString, "#737373")
        XCTAssertEqual(tokens.border.hexString, "#E5E5E5")
        XCTAssertEqual(tokens.borderStrong.hexString, "#D4D4D4")
        XCTAssertEqual(tokens.accent.hexString, "#4F46E5")
        XCTAssertEqual(tokens.accentOn.hexString, "#FFFFFF")
        XCTAssertEqual(tokens.accentSoft.hexString, "#E6EAFF")
        XCTAssertEqual(tokens.star.hexString, "#E7AD01")
        XCTAssertEqual(tokens.danger.hexString, "#E7000F")
        XCTAssertEqual(tokens.scrim.hexString, "#000000")
        XCTAssertEqual(tokens.scrim.opacity, 0.32, accuracy: 0.001)
        XCTAssertFalse(tokens.usesDarkChrome)
    }

    func testFeedmanThemeDarkTokensMatchIndigoPrototypeValues() {
        let tokens = FeedmanTheme.resolvedTokens(for: .dark)

        XCTAssertEqual(tokens.background.hexString, "#0A0A0A")
        XCTAssertEqual(tokens.surface.hexString, "#171717")
        XCTAssertEqual(tokens.surfaceSecondary.hexString, "#1E1E1E")
        XCTAssertEqual(tokens.foreground.hexString, "#FAFAFA")
        XCTAssertEqual(tokens.muted.hexString, "#262626")
        XCTAssertEqual(tokens.mutedForeground.hexString, "#A1A1A1")
        XCTAssertEqual(tokens.border.hexString, "#FFFFFF")
        XCTAssertEqual(tokens.border.opacity, 0.12, accuracy: 0.001)
        XCTAssertEqual(tokens.borderStrong.hexString, "#FFFFFF")
        XCTAssertEqual(tokens.borderStrong.opacity, 0.20, accuracy: 0.001)
        XCTAssertEqual(tokens.accent.hexString, "#6895F4")
        XCTAssertEqual(tokens.accentOn.hexString, "#FFFFFF")
        XCTAssertEqual(tokens.accentSoft.hexString, "#6895F4")
        XCTAssertEqual(tokens.accentSoft.opacity, 0.18, accuracy: 0.001)
        XCTAssertEqual(tokens.star.hexString, "#F5BA26")
        XCTAssertEqual(tokens.danger.hexString, "#FF6468")
        XCTAssertEqual(tokens.scrim.hexString, "#000000")
        XCTAssertEqual(tokens.scrim.opacity, 0.60, accuracy: 0.001)
        XCTAssertTrue(tokens.usesDarkChrome)
    }

    func testFeedmanThemeLightAndDarkTokensDifferForSemanticRoles() {
        let light = FeedmanTheme.resolvedTokens(for: .light)
        let dark = FeedmanTheme.resolvedTokens(for: .dark)

        XCTAssertNotEqual(light.background, dark.background)
        XCTAssertNotEqual(light.surface, dark.surface)
        XCTAssertNotEqual(light.surfaceSecondary, dark.surfaceSecondary)
        XCTAssertNotEqual(light.foreground, dark.foreground)
        XCTAssertNotEqual(light.muted, dark.muted)
        XCTAssertNotEqual(light.mutedForeground, dark.mutedForeground)
        XCTAssertNotEqual(light.border, dark.border)
        XCTAssertNotEqual(light.borderStrong, dark.borderStrong)
        XCTAssertNotEqual(light.accent, dark.accent)
        XCTAssertNotEqual(light.accentSoft, dark.accentSoft)
        XCTAssertNotEqual(light.star, dark.star)
        XCTAssertNotEqual(light.danger, dark.danger)
        XCTAssertNotEqual(light.scrim, dark.scrim)
        XCTAssertNotEqual(light.usesDarkChrome, dark.usesDarkChrome)
    }
}
