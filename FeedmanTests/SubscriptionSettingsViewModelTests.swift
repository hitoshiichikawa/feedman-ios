import XCTest
@testable import Feedman

@MainActor
final class SubscriptionSettingsViewModelTests: XCTestCase {
    func testUnsupportedInitialIntervalDoesNotSaveUntilUserSelectsSupportedInterval() async {
        let repository = StubSubscriptionSettingsRepository()
        let viewModel = SubscriptionSettingsViewModel(
            feed: makeFeed(fetchIntervalMinutes: 45),
            repository: repository
        )

        XCTAssertNil(viewModel.selectedIntervalMinutes)
        XCTAssertFalse(viewModel.canSaveInterval)

        let didNoOpSave = await viewModel.saveInterval()
        XCTAssertFalse(didNoOpSave)
        XCTAssertTrue(repository.settingsRequests.isEmpty)

        viewModel.selectInterval(30)
        XCTAssertEqual(viewModel.selectedIntervalMinutes, 30)
        XCTAssertTrue(viewModel.canSaveInterval)
    }

    func testSaveIntervalSuccessRecordsRequestAndUpdatesPersistedState() async {
        let repository = StubSubscriptionSettingsRepository()
        let viewModel = SubscriptionSettingsViewModel(
            feed: makeFeed(fetchIntervalMinutes: 60),
            repository: repository
        )

        viewModel.selectInterval(180)
        let didSave = await viewModel.saveInterval()

        XCTAssertTrue(didSave)
        XCTAssertEqual(
            repository.settingsRequests,
            [SettingsRequest(subscriptionID: "sub-feed", request: SubscriptionSettingsRequest(fetchIntervalMinutes: 180))]
        )
        XCTAssertEqual(viewModel.persistedIntervalMinutes, 180)
        XCTAssertEqual(viewModel.message, .success("取得間隔を保存しました"))
    }

    func testSaveIntervalFailureKeepsSelectionEditable() async {
        let repository = StubSubscriptionSettingsRepository()
        repository.settingsResult = .failure(FeedmanAPIError.transportFailed(underlyingError: URLError(.notConnectedToInternet)))
        let viewModel = SubscriptionSettingsViewModel(
            feed: makeFeed(fetchIntervalMinutes: 60),
            repository: repository
        )

        viewModel.selectInterval(30)
        let didSave = await viewModel.saveInterval()

        XCTAssertFalse(didSave)
        XCTAssertEqual(viewModel.selectedIntervalMinutes, 30)
        XCTAssertEqual(viewModel.persistedIntervalMinutes, 60)
        XCTAssertEqual(repository.settingsRequests.count, 1)
        XCTAssertEqual(
            viewModel.message,
            .failure(
                SubscriptionSettingsErrorPresentation(
                    kind: .network,
                    title: "通信できませんでした",
                    message: "ネットワーク接続を確認してからもう一度お試しください。"
                )
            )
        )
    }

    func testConcurrentSavePreventsDuplicateRequest() async throws {
        let repository = ControlledSubscriptionSettingsRepository()
        let viewModel = SubscriptionSettingsViewModel(
            feed: makeFeed(fetchIntervalMinutes: 60),
            repository: repository
        )

        viewModel.selectInterval(30)
        let saveTask = Task {
            await viewModel.saveInterval()
        }

        let didStart = try await waitUntil {
            repository.settingsRequests.count == 1
        }
        XCTAssertTrue(didStart)
        let didSaveDuplicate = await viewModel.saveInterval()
        XCTAssertFalse(didSaveDuplicate)
        XCTAssertEqual(repository.settingsRequests.count, 1)

        repository.succeedSettings()
        let didSave = await saveTask.value
        XCTAssertTrue(didSave)
        XCTAssertEqual(viewModel.persistedIntervalMinutes, 30)
    }

    func testResumeActiveFeedIsGuarded() async {
        let repository = StubSubscriptionSettingsRepository()
        let viewModel = SubscriptionSettingsViewModel(
            feed: makeFeed(status: .active),
            repository: repository
        )

        XCTAssertFalse(viewModel.canResume)
        let didResume = await viewModel.resume()
        XCTAssertFalse(didResume)
        XCTAssertTrue(repository.resumeRequests.isEmpty)
    }

    func testResumeStoppedFeedCallsRepositoryAndUpdatesStatus() async {
        let repository = StubSubscriptionSettingsRepository()
        let viewModel = SubscriptionSettingsViewModel(
            feed: makeFeed(status: .stopped(message: "手動で停止しました")),
            repository: repository
        )

        XCTAssertTrue(viewModel.canResume)
        let didResume = await viewModel.resume()
        XCTAssertTrue(didResume)
        XCTAssertEqual(repository.resumeRequests, ["sub-feed"])
        XCTAssertEqual(viewModel.status, .active)
        XCTAssertEqual(viewModel.message, .success("購読を再開しました"))
    }

    func testUnsubscribeCancelDoesNotCallRepositoryAndConfirmCallsOnce() async {
        let repository = StubSubscriptionSettingsRepository()
        let viewModel = SubscriptionSettingsViewModel(
            feed: makeFeed(),
            repository: repository
        )

        viewModel.requestUnsubscribeConfirmation()
        XCTAssertTrue(viewModel.isUnsubscribeConfirmationPresented)
        viewModel.cancelUnsubscribe()
        XCTAssertFalse(viewModel.isUnsubscribeConfirmationPresented)
        let didCancelConfirm = await viewModel.confirmUnsubscribe()
        XCTAssertFalse(didCancelConfirm)
        XCTAssertTrue(repository.unsubscribeRequests.isEmpty)

        viewModel.requestUnsubscribeConfirmation()
        let didConfirm = await viewModel.confirmUnsubscribe()
        XCTAssertTrue(didConfirm)
        XCTAssertEqual(repository.unsubscribeRequests, ["sub-feed"])
        XCTAssertEqual(viewModel.unsubscribeEvent?.subscriptionID, "sub-feed")

        viewModel.requestUnsubscribeConfirmation()
        let didSecondConfirm = await viewModel.confirmUnsubscribe()
        XCTAssertFalse(didSecondConfirm)
        XCTAssertEqual(repository.unsubscribeRequests, ["sub-feed"])
    }

    private func makeFeed(
        status: FeedStatus = .active,
        fetchIntervalMinutes: Int = 60
    ) -> Feed {
        Feed(
            id: "feed-id",
            subscriptionID: "sub-feed",
            title: "Example Feed",
            unreadCount: 0,
            status: status,
            fetchIntervalMinutes: fetchIntervalMinutes
        )
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        condition: @escaping () -> Bool
    ) async throws -> Bool {
        let start = DispatchTime.now().uptimeNanoseconds

        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            if condition() {
                return true
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        return false
    }
}

private struct SettingsRequest: Equatable {
    let subscriptionID: String
    let request: SubscriptionSettingsRequest
}

private final class StubSubscriptionSettingsRepository: FeedRepository {
    private(set) var settingsRequests: [SettingsRequest] = []
    private(set) var resumeRequests: [String] = []
    private(set) var unsubscribeRequests: [String] = []

    var settingsResult: Result<Void, Error> = .success(())
    var resumeResult: Result<Void, Error> = .success(())
    var unsubscribeResult: Result<Void, Error> = .success(())

    func subscriptions() async throws -> [Feed] {
        []
    }

    func updateSubscriptionSettings(
        subscriptionID: String,
        request: SubscriptionSettingsRequest
    ) async throws {
        settingsRequests.append(SettingsRequest(subscriptionID: subscriptionID, request: request))
        try settingsResult.get()
    }

    func resumeSubscription(subscriptionID: String) async throws {
        resumeRequests.append(subscriptionID)
        try resumeResult.get()
    }

    func unsubscribe(subscriptionID: String) async throws {
        unsubscribeRequests.append(subscriptionID)
        try unsubscribeResult.get()
    }

    func crossFeedItems() async throws -> [FeedItem] {
        []
    }
}

private final class ControlledSubscriptionSettingsRepository: FeedRepository {
    private var continuation: CheckedContinuation<Void, Error>?
    private(set) var settingsRequests: [SettingsRequest] = []

    func subscriptions() async throws -> [Feed] {
        []
    }

    func updateSubscriptionSettings(
        subscriptionID: String,
        request: SubscriptionSettingsRequest
    ) async throws {
        settingsRequests.append(SettingsRequest(subscriptionID: subscriptionID, request: request))
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func crossFeedItems() async throws -> [FeedItem] {
        []
    }

    func succeedSettings() {
        continuation?.resume(returning: ())
        continuation = nil
    }
}
