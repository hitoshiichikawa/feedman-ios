import XCTest
@testable import Feedman

@MainActor
final class KeywordSettingsViewModelTests: XCTestCase {
    func testLoadKeywordsSuccessPreservesRepositoryOrder() async {
        let repository = StubKeywordSettingsRepository()
        repository.listResult = .success([Self.swiftUIKeyword, Self.rssKeyword])
        let viewModel = makeViewModel(repository: repository)

        await viewModel.loadKeywords()

        XCTAssertEqual(viewModel.contentState, .loaded([Self.swiftUIKeyword, Self.rssKeyword]))
        XCTAssertEqual(repository.operations, [.list(accessToken: "access-1")])
    }

    func testLoadKeywordsEmptyShowsEmptyState() async {
        let repository = StubKeywordSettingsRepository()
        repository.listResult = .success([])
        let viewModel = makeViewModel(repository: repository)

        await viewModel.loadKeywords()

        XCTAssertEqual(viewModel.contentState, .empty)
    }

    func testInitialLoadFailureShowsRecoverableErrorAndRetryCanLoad() async {
        let repository = StubKeywordSettingsRepository()
        repository.listResult = .failure(FeedmanAPIError.transportFailed(underlyingError: URLError(.notConnectedToInternet)))
        let viewModel = makeViewModel(repository: repository)

        await viewModel.loadKeywords()

        XCTAssertEqual(
            viewModel.contentState,
            .failed(
                KeywordSettingsErrorPresentation(
                    kind: .network,
                    title: "通信できませんでした",
                    message: "ネットワーク接続を確認してからもう一度お試しください。"
                )
            )
        )

        repository.listResult = .success([Self.swiftUIKeyword])
        await viewModel.retryInitialLoad()

        XCTAssertEqual(viewModel.contentState, .loaded([Self.swiftUIKeyword]))
        XCTAssertEqual(repository.operations.count, 2)
    }

    func testVisibleListRefreshFailurePreservesContentAndShowsMessage() async {
        let repository = StubKeywordSettingsRepository()
        repository.listResult = .success([Self.swiftUIKeyword])
        let viewModel = makeViewModel(repository: repository)
        await viewModel.loadKeywords()

        repository.listResult = .failure(FeedmanAPIError.transportFailed(underlyingError: URLError(.notConnectedToInternet)))
        await viewModel.loadKeywords()

        XCTAssertEqual(viewModel.contentState, .loaded([Self.swiftUIKeyword]))
        XCTAssertEqual(
            viewModel.message,
            .failure(
                KeywordSettingsErrorPresentation(
                    kind: .network,
                    title: "通信できませんでした",
                    message: "ネットワーク接続を確認してからもう一度お試しください。"
                )
            )
        )
    }

    func testCreateWithWhitespaceOnlyTermDoesNotCallRepository() async {
        let repository = StubKeywordSettingsRepository()
        let viewModel = makeViewModel(repository: repository)

        let didCreate = await viewModel.createKeyword(term: "   \n")

        XCTAssertFalse(didCreate)
        XCTAssertTrue(repository.operations.isEmpty)
        XCTAssertEqual(viewModel.message, .failure(.emptyTerm))
    }

    func testCreateTrimsTermAndAppendsServerConfirmedKeyword() async {
        let repository = StubKeywordSettingsRepository()
        repository.createResult = .success(Self.combineKeyword)
        let viewModel = makeViewModel(repository: repository)
        viewModel.draftTerm = "  Combine  "

        let didCreate = await viewModel.createKeyword()

        XCTAssertTrue(didCreate)
        XCTAssertEqual(
            repository.operations,
            [.create(KeywordCreateRequest(term: "Combine", enabled: true), accessToken: "access-1")]
        )
        XCTAssertEqual(viewModel.contentState, .loaded([Self.combineKeyword]))
        XCTAssertEqual(viewModel.draftTerm, "")
    }

    func testUpdateTrimsTermAndReplacesServerConfirmedKeyword() async {
        let repository = StubKeywordSettingsRepository()
        repository.listResult = .success([Self.swiftUIKeyword])
        repository.updateResult = .success(Self.swiftKeyword)
        let viewModel = makeViewModel(repository: repository)
        await viewModel.loadKeywords()

        let didUpdate = await viewModel.updateKeyword(id: "keyword-1", term: "  Swift  ")

        XCTAssertTrue(didUpdate)
        XCTAssertEqual(
            repository.operations.suffix(1),
            [.update(id: "keyword-1", request: KeywordUpdateRequest(term: "Swift", enabled: nil), accessToken: "access-1")]
        )
        XCTAssertEqual(viewModel.contentState, .loaded([Self.swiftKeyword]))
    }

    func testToggleFailurePreservesVisibleServerState() async {
        let repository = StubKeywordSettingsRepository()
        repository.listResult = .success([Self.swiftUIKeyword])
        repository.updateResult = .failure(FeedmanAPIError.transportFailed(underlyingError: URLError(.notConnectedToInternet)))
        let viewModel = makeViewModel(repository: repository)
        await viewModel.loadKeywords()

        let didToggle = await viewModel.setKeywordEnabled(id: "keyword-1", enabled: false)

        XCTAssertFalse(didToggle)
        XCTAssertEqual(viewModel.contentState, .loaded([Self.swiftUIKeyword]))
        XCTAssertEqual(viewModel.keywords.first?.enabled, true)
        XCTAssertNotNil(viewModel.message)
    }

    func testDeleteRequiresConfirmationBeforeRepositoryCall() async {
        let repository = StubKeywordSettingsRepository()
        repository.listResult = .success([Self.swiftUIKeyword])
        let viewModel = makeViewModel(repository: repository)
        await viewModel.loadKeywords()

        let didDeleteWithoutConfirmation = await viewModel.confirmDeleteKeyword()
        XCTAssertFalse(didDeleteWithoutConfirmation)
        XCTAssertEqual(repository.operations, [.list(accessToken: "access-1")])

        viewModel.requestDeleteConfirmation(id: "keyword-1")
        XCTAssertEqual(viewModel.deleteConfirmation, KeywordDeleteConfirmation(id: "keyword-1", term: "SwiftUI"))
        let didDelete = await viewModel.confirmDeleteKeyword()

        XCTAssertTrue(didDelete)
        XCTAssertEqual(viewModel.contentState, .empty)
        XCTAssertNil(viewModel.deleteConfirmation)
        XCTAssertEqual(repository.operations.suffix(1), [.delete(id: "keyword-1", accessToken: "access-1")])
    }

    func testDeleteFailureKeepsVisibleListAndConfirmation() async {
        let repository = StubKeywordSettingsRepository()
        repository.listResult = .success([Self.swiftUIKeyword])
        repository.deleteResult = .failure(FeedmanAPIError.transportFailed(underlyingError: URLError(.notConnectedToInternet)))
        let viewModel = makeViewModel(repository: repository)
        await viewModel.loadKeywords()

        viewModel.requestDeleteConfirmation(id: "keyword-1")
        let didDelete = await viewModel.confirmDeleteKeyword()

        XCTAssertFalse(didDelete)
        XCTAssertEqual(viewModel.contentState, .loaded([Self.swiftUIKeyword]))
        XCTAssertEqual(viewModel.deleteConfirmation, KeywordDeleteConfirmation(id: "keyword-1", term: "SwiftUI"))
        XCTAssertNotNil(viewModel.message)
    }

    func testConcurrentLoadPreventsDuplicateRepositoryCalls() async throws {
        let repository = ControlledKeywordSettingsRepository()
        let viewModel = makeViewModel(repository: repository)

        let loadTask = Task { @MainActor in
            await viewModel.loadKeywords()
        }
        let didStart = try await waitUntil {
            repository.operations.count == 1
        }
        XCTAssertTrue(didStart)

        await viewModel.loadKeywords()

        XCTAssertEqual(repository.operations.count, 1)
        repository.succeedList(with: [Self.swiftUIKeyword])
        await loadTask.value
        XCTAssertEqual(viewModel.contentState, .loaded([Self.swiftUIKeyword]))
    }

    func testConcurrentCreatePreventsDuplicateRepositoryCalls() async throws {
        let repository = ControlledKeywordSettingsRepository()
        let viewModel = makeViewModel(repository: repository)

        let createTask = Task { @MainActor in
            await viewModel.createKeyword(term: "Swift")
        }
        let didStart = try await waitUntil {
            repository.operations.count == 1
        }
        XCTAssertTrue(didStart)

        let duplicateResult = await viewModel.createKeyword(term: "Swift")

        XCTAssertFalse(duplicateResult)
        XCTAssertEqual(repository.operations.count, 1)
        repository.succeedCreate(with: Self.swiftKeyword)
        let didCreate = await createTask.value
        XCTAssertTrue(didCreate)
    }

    func testNewViewModelStartsWithoutStaleMessageOrConfirmation() {
        let repository = StubKeywordSettingsRepository()
        let firstViewModel = makeViewModel(repository: repository)
        firstViewModel.requestDeleteConfirmation(id: "missing")

        let secondViewModel = makeViewModel(repository: repository)

        XCTAssertEqual(secondViewModel.contentState, .idle)
        XCTAssertNil(secondViewModel.message)
        XCTAssertNil(secondViewModel.deleteConfirmation)
    }

    func testDuplicateRateLimitAuthAndNetworkErrorsMapToGuidance() {
        let duplicate = KeywordSettingsViewModel.errorPresentation(
            for: feedmanError(statusCode: 409, code: "DUPLICATE_KEYWORD", category: "conflict")
        )
        let rateLimit = KeywordSettingsViewModel.errorPresentation(
            for: feedmanError(statusCode: 429, code: "KEYWORD_RATE_LIMIT", category: "rate_limit", retryAfterSeconds: 90)
        )
        let auth = KeywordSettingsViewModel.errorPresentation(
            for: FeedmanAPIError.authRequired(AuthRequiredContext(reason: .missingRefreshHook, statusCode: 401, underlyingError: nil))
        )
        let network = KeywordSettingsViewModel.errorPresentation(
            for: FeedmanAPIError.transportFailed(underlyingError: URLError(.notConnectedToInternet))
        )

        XCTAssertEqual(duplicate.kind, .duplicate)
        XCTAssertTrue(duplicate.message.contains("登録済み"))
        XCTAssertEqual(rateLimit.kind, .rateLimit(retryAfterSeconds: 90))
        XCTAssertTrue(rateLimit.message.contains("90 秒後"))
        XCTAssertEqual(auth.kind, .authRequired)
        XCTAssertEqual(network.kind, .network)
    }

    func testAuthRequiredCallsHandler() async {
        let repository = StubKeywordSettingsRepository()
        repository.listResult = .failure(
            FeedmanAPIError.authRequired(AuthRequiredContext(reason: .missingRefreshHook, statusCode: 401, underlyingError: nil))
        )
        var authRequiredCallCount = 0
        let viewModel = KeywordSettingsViewModel(
            repository: repository,
            accessToken: "access-1",
            authRequiredHandler: {
                authRequiredCallCount += 1
            }
        )

        await viewModel.loadKeywords()

        XCTAssertEqual(authRequiredCallCount, 1)
    }

    private static let swiftUIKeyword = KeywordResponse(
        id: "keyword-1",
        term: "SwiftUI",
        scope: "title",
        enabled: true,
        hits: 3
    )
    private static let rssKeyword = KeywordResponse(
        id: "keyword-2",
        term: "RSS",
        scope: "title",
        enabled: false,
        hits: 0
    )
    private static let combineKeyword = KeywordResponse(
        id: "keyword-3",
        term: "Combine",
        scope: "title",
        enabled: true,
        hits: 0
    )
    private static let swiftKeyword = KeywordResponse(
        id: "keyword-1",
        term: "Swift",
        scope: "title",
        enabled: true,
        hits: 3
    )

    private func makeViewModel(repository: any KeywordRepository) -> KeywordSettingsViewModel {
        KeywordSettingsViewModel(repository: repository, accessToken: "access-1")
    }

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
                    message: "Keyword operation failed.",
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

private enum KeywordSettingsRepositoryOperation: Equatable {
    case list(accessToken: String)
    case create(KeywordCreateRequest, accessToken: String)
    case update(id: String, request: KeywordUpdateRequest, accessToken: String)
    case delete(id: String, accessToken: String)
}

private final class StubKeywordSettingsRepository: KeywordRepository {
    private(set) var operations: [KeywordSettingsRepositoryOperation] = []

    var listResult: Result<[KeywordResponse], Error> = .success([])
    var createResult: Result<KeywordResponse, Error> = .success(
        KeywordResponse(id: "keyword-created", term: "Created", scope: "title", enabled: true, hits: 0)
    )
    var updateResult: Result<KeywordResponse, Error> = .success(
        KeywordResponse(id: "keyword-updated", term: "Updated", scope: "title", enabled: true, hits: 0)
    )
    var deleteResult: Result<Void, Error> = .success(())

    func keywords(accessToken: String) async throws -> [KeywordResponse] {
        operations.append(.list(accessToken: accessToken))
        return try listResult.get()
    }

    func createKeyword(_ request: KeywordCreateRequest, accessToken: String) async throws -> KeywordResponse {
        operations.append(.create(request, accessToken: accessToken))
        return try createResult.get()
    }

    func updateKeyword(
        id: String,
        request: KeywordUpdateRequest,
        accessToken: String
    ) async throws -> KeywordResponse {
        operations.append(.update(id: id, request: request, accessToken: accessToken))
        return try updateResult.get()
    }

    func deleteKeyword(id: String, accessToken: String) async throws {
        operations.append(.delete(id: id, accessToken: accessToken))
        try deleteResult.get()
    }
}

private final class ControlledKeywordSettingsRepository: KeywordRepository {
    private let lock = NSLock()
    private var listContinuation: CheckedContinuation<[KeywordResponse], Error>?
    private var createContinuation: CheckedContinuation<KeywordResponse, Error>?
    private var storedOperations: [KeywordSettingsRepositoryOperation] = []

    var operations: [KeywordSettingsRepositoryOperation] {
        locked {
            storedOperations
        }
    }

    func keywords(accessToken: String) async throws -> [KeywordResponse] {
        locked {
            storedOperations.append(.list(accessToken: accessToken))
        }
        return try await withCheckedThrowingContinuation { continuation in
            locked {
                self.listContinuation = continuation
            }
        }
    }

    func createKeyword(_ request: KeywordCreateRequest, accessToken: String) async throws -> KeywordResponse {
        locked {
            storedOperations.append(.create(request, accessToken: accessToken))
        }
        return try await withCheckedThrowingContinuation { continuation in
            locked {
                self.createContinuation = continuation
            }
        }
    }

    func updateKeyword(
        id: String,
        request: KeywordUpdateRequest,
        accessToken: String
    ) async throws -> KeywordResponse {
        KeywordResponse(id: id, term: request.term ?? "Updated", scope: "title", enabled: request.enabled ?? true, hits: 0)
    }

    func deleteKeyword(id: String, accessToken: String) async throws {}

    func succeedList(with keywords: [KeywordResponse]) {
        let continuation = locked {
            let current = listContinuation
            listContinuation = nil
            return current
        }
        continuation?.resume(returning: keywords)
    }

    func succeedCreate(with keyword: KeywordResponse) {
        let continuation = locked {
            let current = createContinuation
            createContinuation = nil
            return current
        }
        continuation?.resume(returning: keyword)
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer {
            lock.unlock()
        }
        return body()
    }
}
