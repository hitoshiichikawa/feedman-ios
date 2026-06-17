import XCTest
@testable import Feedman

@MainActor
final class RegisterFeedViewModelTests: XCTestCase {
    func testSubmitWithWhitespaceOnlyURLDoesNotCallRepository() async {
        let repository = StubRegisterFeedRepository(result: .success(Self.registeredFeed))
        let viewModel = RegisterFeedViewModel(repository: repository, initialURL: "   \n  ")

        await viewModel.submit()

        XCTAssertEqual(repository.registeredURLs, [])
        XCTAssertEqual(
            viewModel.submissionState,
            .failure(.emptyInput)
        )
    }

    func testSubmitTrimsURLAndPublishesSuccessEvent() async throws {
        let repository = ControlledRegisterFeedRepository()
        let viewModel = RegisterFeedViewModel(
            repository: repository,
            initialURL: "  https://example.com/feed.xml  "
        )

        let submitTask = Task {
            await viewModel.submit()
        }

        let didStart = try await waitUntil {
            repository.registeredURLs.count == 1
        }
        XCTAssertTrue(didStart)
        XCTAssertEqual(repository.registeredURLs, ["https://example.com/feed.xml"])
        XCTAssertEqual(viewModel.urlText, "https://example.com/feed.xml")
        XCTAssertEqual(viewModel.submissionState, .loading)

        repository.succeed(with: Self.registeredFeed)
        await submitTask.value

        XCTAssertEqual(viewModel.submissionState, .success(Self.registeredFeed))
        XCTAssertEqual(viewModel.successEvent?.registeredFeed, Self.registeredFeed)
    }

    func testSubmitFailureKeepsURLEditableAndMapsNetworkError() async {
        let repository = StubRegisterFeedRepository(
            result: .failure(FeedmanAPIError.transportFailed(underlyingError: URLError(.notConnectedToInternet)))
        )
        let viewModel = RegisterFeedViewModel(repository: repository, initialURL: "https://example.com")

        await viewModel.submit()

        XCTAssertEqual(viewModel.urlText, "https://example.com")
        XCTAssertNil(viewModel.successEvent)
        XCTAssertEqual(repository.subscriptionCallCount, 0)
        XCTAssertEqual(
            viewModel.submissionState,
            .failure(
                RegisterFeedErrorPresentation(
                    kind: .network,
                    title: "通信できませんでした",
                    message: "ネットワーク接続を確認してからもう一度お試しください。"
                )
            )
        )
    }

    func testConcurrentSubmitOnlyCallsRepositoryOnce() async throws {
        let repository = ControlledRegisterFeedRepository()
        let viewModel = RegisterFeedViewModel(repository: repository, initialURL: "https://example.com/feed.xml")

        let submitTask = Task {
            await viewModel.submit()
        }

        let didStart = try await waitUntil {
            repository.registeredURLs.count == 1
        }
        XCTAssertTrue(didStart)

        await viewModel.submit()

        XCTAssertEqual(repository.registeredURLs.count, 1)
        repository.succeed(with: Self.registeredFeed)
        await submitTask.value
        XCTAssertEqual(viewModel.submissionState, .success(Self.registeredFeed))
    }

    func testDuplicateErrorMapsToDuplicateGuidance() {
        let presentation = RegisterFeedViewModel.errorPresentation(
            for: feedmanError(statusCode: 409, code: "DUPLICATE_SUBSCRIPTION", category: "conflict")
        )

        XCTAssertEqual(presentation.kind, .duplicate)
        XCTAssertEqual(presentation.title, "すでに登録されています")
    }

    func testInvalidURLErrorMapsToURLGuidance() {
        let presentation = RegisterFeedViewModel.errorPresentation(
            for: feedmanError(statusCode: 400, code: "INVALID_FEED_URL", category: "validation")
        )

        XCTAssertEqual(presentation.kind, .invalidURL)
        XCTAssertEqual(presentation.title, "URL を確認してください")
    }

    func testRateLimitErrorIncludesRetrySeconds() {
        let presentation = RegisterFeedViewModel.errorPresentation(
            for: feedmanError(
                statusCode: 429,
                code: "FEED_COOLDOWN",
                category: "rate_limit",
                retryAfterSeconds: 120
            )
        )

        XCTAssertEqual(presentation.kind, .rateLimit(retryAfterSeconds: 120))
        XCTAssertTrue(presentation.message.contains("120 秒後"))
    }

    func testAuthRequiredMapsToAuthGuidance() {
        let presentation = RegisterFeedViewModel.errorPresentation(
            for: FeedmanAPIError.authRequired(
                AuthRequiredContext(
                    reason: .missingRefreshHook,
                    statusCode: 401,
                    underlyingError: nil
                )
            )
        )

        XCTAssertEqual(presentation.kind, .authRequired)
        XCTAssertEqual(presentation.title, "ログインが必要です")
    }

    private static let registeredFeed = RegisteredFeed(
        subscriptionID: "sub-registered",
        feedID: "feed-registered",
        title: "Registered Feed",
        feedURL: "https://example.com/feed.xml",
        siteURL: "https://example.com",
        faviconURL: nil,
        fetchIntervalMinutes: 60,
        status: .active,
        unreadCount: 0
    )

    private func feedmanError(
        statusCode: Int,
        code: String,
        category: String,
        retryAfterSeconds: Int? = nil
    ) -> FeedmanAPIError {
        FeedmanAPIError.feedmanError(
            FeedmanErrorContext(
                statusCode: statusCode,
                body: FeedmanErrorBody(
                    code: code,
                    message: "Registration failed.",
                    category: category,
                    action: "fix_request",
                    details: retryAfterSeconds.map {
                        ["retry_after_seconds": .int($0)]
                    }
                ),
                retryAfter: retryAfterSeconds.map(String.init)
            )
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

private final class StubRegisterFeedRepository: FeedRepository {
    private(set) var registeredURLs: [String] = []
    private(set) var subscriptionCallCount = 0
    var result: Result<RegisteredFeed, Error>

    init(result: Result<RegisteredFeed, Error>) {
        self.result = result
    }

    func subscriptions() async throws -> [Feed] {
        subscriptionCallCount += 1
        return []
    }

    func registerFeed(url: String) async throws -> RegisteredFeed {
        registeredURLs.append(url)
        return try result.get()
    }

    func crossFeedItems() async throws -> [FeedItem] {
        []
    }
}

private final class ControlledRegisterFeedRepository: FeedRepository {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<RegisteredFeed, Error>?
    private var storedRegisteredURLs: [String] = []

    var registeredURLs: [String] {
        lock.withCriticalSection {
            storedRegisteredURLs
        }
    }

    func subscriptions() async throws -> [Feed] {
        []
    }

    func registerFeed(url: String) async throws -> RegisteredFeed {
        lock.withCriticalSection {
            storedRegisteredURLs.append(url)
        }

        return try await withCheckedThrowingContinuation { continuation in
            lock.withCriticalSection {
                self.continuation = continuation
            }
        }
    }

    func crossFeedItems() async throws -> [FeedItem] {
        []
    }

    func succeed(with registeredFeed: RegisteredFeed) {
        resume(with: .success(registeredFeed))
    }

    private func resume(with result: Result<RegisteredFeed, Error>) {
        let continuation = lock.withCriticalSection {
            let current = self.continuation
            self.continuation = nil
            return current
        }

        continuation?.resume(with: result)
    }
}

private extension NSLock {
    func withCriticalSection<T>(_ body: () -> T) -> T {
        lock()
        defer {
            unlock()
        }
        return body()
    }
}
