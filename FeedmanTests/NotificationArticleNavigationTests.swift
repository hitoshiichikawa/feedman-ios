import XCTest
@testable import Feedman

final class NotificationArticleNavigationTests: XCTestCase {
    func testValidDeepLinkExtractsArticleTarget() {
        let result = NotificationArticleTargetParser().resolve(
            userInfo: [
                "data": [
                    "deep_link": "feedman://items/item-47"
                ]
            ]
        )

        XCTAssertEqual(result, .target(NotificationArticleTarget(itemID: "item-47")))
    }

    func testItemIDFallbackCreatesArticleTargetWhenDeepLinkIsAbsent() {
        let result = NotificationArticleTargetParser().resolve(
            userInfo: [
                "data": [
                    "item_id": " item-48 "
                ]
            ]
        )

        XCTAssertEqual(result, .target(NotificationArticleTarget(itemID: "item-48")))
    }

    func testUnsupportedSchemeRejectsNavigation() {
        let result = NotificationArticleTargetParser().resolve(
            userInfo: [
                "data": [
                    "deep_link": "https://example.com/items/item-47"
                ]
            ]
        )

        XCTAssertEqual(result, .rejected(.unsupportedDeepLink))
    }

    func testUnsupportedPathRejectsNavigation() {
        let result = NotificationArticleTargetParser().resolve(
            userInfo: [
                "data": [
                    "deep_link": "feedman://feeds/item-47"
                ]
            ]
        )

        XCTAssertEqual(result, .rejected(.unsupportedDeepLink))
    }

    func testEmptyDeepLinkItemIDRejectsNavigation() {
        let result = NotificationArticleTargetParser().resolve(
            userInfo: [
                "data": [
                    "deep_link": "feedman://items/%20%20%20"
                ]
            ]
        )

        XCTAssertEqual(result, .rejected(.emptyItemID))
    }

    func testEmptyFallbackItemIDRejectsNavigation() {
        let result = NotificationArticleTargetParser().resolve(
            userInfo: [
                "data": [
                    "item_id": "   "
                ]
            ]
        )

        XCTAssertEqual(result, .rejected(.emptyItemID))
    }

    func testConflictingDeepLinkAndItemIDRejectsNavigation() {
        let result = NotificationArticleTargetParser().resolve(
            userInfo: [
                "data": [
                    "deep_link": "feedman://items/item-47",
                    "item_id": "item-48"
                ]
            ]
        )

        XCTAssertEqual(
            result,
            .rejected(.conflictingItemID(deepLinkItemID: "item-47", itemID: "item-48"))
        )
    }

    func testMatchingDeepLinkAndItemIDUsesDeepLinkTarget() {
        let result = NotificationArticleTargetParser().resolve(
            userInfo: [
                "data": [
                    "deep_link": "feedman://items/item-47",
                    "item_id": " item-47 "
                ]
            ]
        )

        XCTAssertEqual(result, .target(NotificationArticleTarget(itemID: "item-47")))
    }

    func testMissingMalformedAndDuplicatedPayloadFieldsDoNotCrash() {
        let result = NotificationArticleTargetParser().resolve(
            userInfo: [
                "data": [
                    "deep_link": ["feedman://items/item-47"],
                    "item_id": 47
                ]
            ]
        )

        XCTAssertEqual(result, .ignored)
    }

    @MainActor
    func testBridgeQueuesColdLaunchPayloadUntilEnvironmentConfigured() {
        NotificationArticleNavigationBridge.shared.reset()
        defer {
            NotificationArticleNavigationBridge.shared.reset()
        }
        var receivedUserInfos: [[AnyHashable: Any]] = []

        NotificationArticleNavigationBridge.shared.handle(
            userInfo: [
                "data": [
                    "deep_link": "feedman://items/item-47"
                ]
            ]
        )
        NotificationArticleNavigationBridge.shared.configure { userInfo in
            receivedUserInfos.append(userInfo)
        }

        XCTAssertEqual(receivedUserInfos.count, 1)
        XCTAssertEqual(
            NotificationArticleTargetParser().resolve(userInfo: receivedUserInfos[0]),
            .target(NotificationArticleTarget(itemID: "item-47"))
        )
    }

    func testAuthenticatedRoutingPresentsExistingArticleDetailSurfaceAndClosesDrawer() {
        var state = AppShellState(isDrawerOpen: true)

        let didPresent = state.presentNotificationArticleTarget(NotificationArticleTarget(itemID: "item-47"))

        XCTAssertTrue(didPresent)
        XCTAssertEqual(state.activePresentation, .articleDetail(ArticleDetailSheetInput(id: "item-47")))
        XCTAssertTrue(state.isPresentingNotificationArticleDetail)
        XCTAssertFalse(state.isDrawerOpen)
    }

    func testDismissingNotificationLaunchedDetailClearsPresentationMarker() {
        var state = AppShellState(
            activePresentation: .articleDetail(ArticleDetailSheetInput(id: "item-47"))
        )
        _ = state.presentNotificationArticleTarget(NotificationArticleTarget(itemID: "item-47"))

        state.dismissPresentation()

        XCTAssertNil(state.activePresentation)
        XCTAssertFalse(state.isPresentingNotificationArticleDetail)
    }

    @MainActor
    func testColdLaunchRetainsPendingArticleTargetDuringSessionRestoreAndConsumesAfterPresentation() {
        let environment = makeEnvironment(state: .restoring)

        environment.handleNotificationPayload(
            [
                "data": [
                    "deep_link": "feedman://items/item-47"
                ]
            ]
        )

        XCTAssertEqual(environment.pendingNotificationArticleTarget, NotificationArticleTarget(itemID: "item-47"))
        XCTAssertEqual(environment.authenticationState, .restoring)

        environment.clearPendingNotificationArticleTarget()

        XCTAssertNil(environment.pendingNotificationArticleTarget)
    }

    @MainActor
    func testUnauthenticatedNotificationTargetIsDeferredUntilLoginCompletes() {
        let environment = makeEnvironment(state: .unauthenticated)

        environment.handleNotificationPayload(
            [
                "data": [
                    "item_id": "item-47"
                ]
            ]
        )

        XCTAssertEqual(environment.pendingNotificationArticleTarget, NotificationArticleTarget(itemID: "item-47"))
        XCTAssertNil(environment.currentAccessToken)

        environment.completeLogin(
            with: TokenCredentials(
                accessToken: "login-access",
                refreshToken: "login-refresh",
                tokenType: "Bearer",
                expiresIn: 900
            )
        )

        XCTAssertEqual(environment.authenticationState, .authenticated(accessToken: "login-access"))
        XCTAssertEqual(environment.pendingNotificationArticleTarget, NotificationArticleTarget(itemID: "item-47"))
    }

    @MainActor
    func testConflictingNotificationPayloadPublishesNonFatalErrorWithoutPendingTarget() {
        let environment = makeEnvironment(state: .authenticated(accessToken: "access-1"))

        environment.handleNotificationPayload(
            [
                "data": [
                    "deep_link": "feedman://items/item-47",
                    "item_id": "item-48"
                ]
            ]
        )

        XCTAssertNil(environment.pendingNotificationArticleTarget)
        XCTAssertEqual(
            environment.notificationNavigationError,
            .conflictingItemID(deepLinkItemID: "item-47", itemID: "item-48")
        )
    }

    @MainActor
    private func makeEnvironment(state: AppAuthenticationState) -> AppEnvironment {
        AppEnvironment(
            feedRepository: MockFeedRepository(),
            authRepository: UnavailableAuthRepository(),
            accountRepository: UnavailableAccountRepository(),
            deviceRegistrationService: APNsDeviceRegistrationService(
                repository: UnavailableDeviceRegistrationRepository(),
                stateStore: InMemoryDeviceRegistrationStateStore(),
                accessTokenProvider: {
                    throw AppEnvironmentError.missingAccessToken
                }
            ),
            authBaseURL: URL(string: "https://api.example.com")!,
            authenticationState: state
        )
    }
}
