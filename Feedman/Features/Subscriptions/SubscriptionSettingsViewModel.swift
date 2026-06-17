import Foundation

enum SubscriptionSettingsOperation: Equatable {
    case savingInterval
    case resuming
    case unsubscribing
}

enum SubscriptionSettingsMessage: Equatable {
    case success(String)
    case failure(SubscriptionSettingsErrorPresentation)
}

struct SubscriptionSettingsErrorPresentation: Equatable {
    enum Kind: Equatable {
        case missingSubscriptionID
        case authRequired
        case network
        case api(code: String, category: String)
        case generic
    }

    let kind: Kind
    let title: String
    let message: String
}

struct SubscriptionUnsubscribeEvent: Equatable, Identifiable {
    let id: UUID
    let subscriptionID: String

    init(id: UUID = UUID(), subscriptionID: String) {
        self.id = id
        self.subscriptionID = subscriptionID
    }
}

@MainActor
final class SubscriptionSettingsViewModel: ObservableObject {
    static let supportedIntervals = [15, 30, 60, 180, 360]

    let feedID: String
    let subscriptionID: String?
    let title: String
    let faviconURL: String?
    let originalIntervalMinutes: Int?

    @Published private(set) var persistedIntervalMinutes: Int?
    @Published var selectedIntervalMinutes: Int? {
        didSet {
            guard oldValue != selectedIntervalMinutes else {
                return
            }

            clearFailure()
        }
    }
    @Published private(set) var status: FeedStatus
    @Published private(set) var operation: SubscriptionSettingsOperation?
    @Published private(set) var message: SubscriptionSettingsMessage?
    @Published var isUnsubscribeConfirmationPresented = false
    @Published private(set) var unsubscribeEvent: SubscriptionUnsubscribeEvent?

    private let repository: FeedRepository

    init(
        feed: Feed,
        repository: FeedRepository
    ) {
        self.feedID = feed.id
        self.subscriptionID = feed.subscriptionID
        self.title = feed.title
        self.faviconURL = feed.faviconURL
        self.originalIntervalMinutes = feed.fetchIntervalMinutes
        self.persistedIntervalMinutes = feed.fetchIntervalMinutes
        self.selectedIntervalMinutes = Self.supportedIntervals.contains(feed.fetchIntervalMinutes ?? -1)
            ? feed.fetchIntervalMinutes
            : nil
        self.status = feed.status
        self.repository = repository
    }

    var isBusy: Bool {
        operation != nil
    }

    var canSaveInterval: Bool {
        guard operation != .savingInterval,
              let selectedIntervalMinutes,
              Self.supportedIntervals.contains(selectedIntervalMinutes) else {
            return false
        }

        return selectedIntervalMinutes != persistedIntervalMinutes
    }

    var canResume: Bool {
        guard operation != .resuming else {
            return false
        }

        switch status {
        case .active:
            return false
        case .stopped, .error:
            return subscriptionID != nil
        }
    }

    var canUnsubscribe: Bool {
        subscriptionID != nil && operation != .unsubscribing && unsubscribeEvent == nil
    }

    var statusMessage: String? {
        switch status {
        case .active:
            return nil
        case let .stopped(message):
            return "停止中です。再開すると次回取得対象に戻ります。\(safeSuffix(message))"
        case let .error(message):
            return "前回の取得でエラーが発生しました。再開できます。\(safeSuffix(message))"
        }
    }

    func selectInterval(_ minutes: Int) {
        guard Self.supportedIntervals.contains(minutes) else {
            return
        }

        selectedIntervalMinutes = minutes
    }

    @discardableResult
    func saveInterval() async -> Bool {
        guard operation != .savingInterval else {
            return false
        }

        guard let subscriptionID else {
            message = .failure(Self.errorPresentation(for: SubscriptionSettingsLocalError.missingSubscriptionID))
            return false
        }

        guard canSaveInterval, let selectedIntervalMinutes else {
            return false
        }

        operation = .savingInterval
        do {
            try await repository.updateSubscriptionSettings(
                subscriptionID: subscriptionID,
                request: SubscriptionSettingsRequest(fetchIntervalMinutes: selectedIntervalMinutes)
            )
            persistedIntervalMinutes = selectedIntervalMinutes
            operation = nil
            message = .success("取得間隔を保存しました")
            return true
        } catch {
            operation = nil
            message = .failure(Self.errorPresentation(for: error))
            return false
        }
    }

    @discardableResult
    func resume() async -> Bool {
        guard operation != .resuming else {
            return false
        }

        guard canResume, let subscriptionID else {
            return false
        }

        operation = .resuming
        do {
            try await repository.resumeSubscription(subscriptionID: subscriptionID)
            status = .active
            operation = nil
            message = .success("購読を再開しました")
            return true
        } catch {
            operation = nil
            isUnsubscribeConfirmationPresented = false
            message = .failure(Self.errorPresentation(for: error))
            return false
        }
    }

    func requestUnsubscribeConfirmation() {
        guard canUnsubscribe else {
            return
        }

        isUnsubscribeConfirmationPresented = true
    }

    func cancelUnsubscribe() {
        isUnsubscribeConfirmationPresented = false
    }

    @discardableResult
    func confirmUnsubscribe() async -> Bool {
        guard operation != .unsubscribing else {
            return false
        }

        guard isUnsubscribeConfirmationPresented, let subscriptionID else {
            return false
        }

        operation = .unsubscribing
        do {
            try await repository.unsubscribe(subscriptionID: subscriptionID)
            operation = nil
            isUnsubscribeConfirmationPresented = false
            message = .success("購読を解除しました")
            unsubscribeEvent = SubscriptionUnsubscribeEvent(subscriptionID: subscriptionID)
            return true
        } catch {
            operation = nil
            message = .failure(Self.errorPresentation(for: error))
            return false
        }
    }

    static func errorPresentation(for error: Error) -> SubscriptionSettingsErrorPresentation {
        if error is SubscriptionSettingsLocalError {
            return SubscriptionSettingsErrorPresentation(
                kind: .missingSubscriptionID,
                title: "設定を変更できません",
                message: "購読 ID を確認できないため、このフィードの設定は変更できません。"
            )
        }

        if case FeedmanAPIError.authRequired = error {
            return SubscriptionSettingsErrorPresentation(
                kind: .authRequired,
                title: "ログインが必要です",
                message: "認証の有効期限が切れています。再ログイン後にもう一度お試しください。"
            )
        }

        if case FeedmanAPIError.transportFailed = error {
            return SubscriptionSettingsErrorPresentation(
                kind: .network,
                title: "通信できませんでした",
                message: "ネットワーク接続を確認してからもう一度お試しください。"
            )
        }

        if case let FeedmanAPIError.feedmanError(context) = error {
            return SubscriptionSettingsErrorPresentation(
                kind: .api(code: context.code, category: context.category),
                title: "設定を更新できませんでした",
                message: apiMessage(for: context)
            )
        }

        return SubscriptionSettingsErrorPresentation(
            kind: .generic,
            title: "設定を更新できませんでした",
            message: "時間をおいてもう一度お試しください。"
        )
    }

    private func clearFailure() {
        guard case .failure = message else {
            return
        }

        message = nil
    }

    private func safeSuffix(_ message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        return " \(trimmed)"
    }

    private static func apiMessage(for context: FeedmanErrorContext) -> String {
        if context.statusCode == 404 {
            return "購読が見つかりませんでした。フィード一覧を更新してください。"
        }

        if context.statusCode == 429 || context.category.lowercased() == "rate_limit" {
            return "操作が多すぎます。時間をおいてもう一度お試しください。"
        }

        if context.statusCode == 400 || context.category.lowercased() == "validation" {
            return "選択内容を確認してからもう一度お試しください。"
        }

        return "時間をおいてもう一度お試しください。"
    }
}

private enum SubscriptionSettingsLocalError: Error {
    case missingSubscriptionID
}
