import SwiftUI

struct SubscriptionSettingsSheet: View {
    @StateObject private var viewModel: SubscriptionSettingsViewModel

    private let onDismiss: () -> Void
    private let onIntervalSaved: (String, Int) -> Void
    private let onResumed: (String) -> Void
    private let onUnsubscribed: (String) -> Void

    init(
        feed: Feed,
        repository: FeedRepository,
        onDismiss: @escaping () -> Void,
        onIntervalSaved: @escaping (String, Int) -> Void,
        onResumed: @escaping (String) -> Void,
        onUnsubscribed: @escaping (String) -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: SubscriptionSettingsViewModel(
                feed: feed,
                repository: repository
            )
        )
        self.onDismiss = onDismiss
        self.onIntervalSaved = onIntervalSaved
        self.onResumed = onResumed
        self.onUnsubscribed = onUnsubscribed
    }

    var body: some View {
        FeedmanSheetShell(
            title: "購読設定",
            subtitle: viewModel.title,
            onDismiss: onDismiss,
            primaryAction: {
                saveButton
            }
        ) {
            VStack(alignment: .leading, spacing: 16) {
                statusSection
                intervalSection
                messageSection
                resumeSection
                unsubscribeSection
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(viewModel.operation == .unsubscribing)
        .alert("購読を解除しますか？", isPresented: $viewModel.isUnsubscribeConfirmationPresented) {
            Button("キャンセル", role: .cancel) {
                viewModel.cancelUnsubscribe()
            }
            Button("購読を解除", role: .destructive) {
                Task {
                    let didUnsubscribe = await viewModel.confirmUnsubscribe()
                    guard didUnsubscribe, let subscriptionID = viewModel.subscriptionID else {
                        return
                    }
                    onUnsubscribed(subscriptionID)
                }
            }
        } message: {
            Text("\(viewModel.title) の購読を解除します。フィード一覧から削除されます。")
        }
    }

    private var saveButton: some View {
        Button {
            Task {
                let didSave = await viewModel.saveInterval()
                guard didSave,
                      let subscriptionID = viewModel.subscriptionID,
                      let interval = viewModel.persistedIntervalMinutes else {
                    return
                }
                onIntervalSaved(subscriptionID, interval)
            }
        } label: {
            HStack(spacing: 8) {
                if viewModel.operation == .savingInterval {
                    ProgressView()
                        .controlSize(.small)
                        .tint(FeedmanTheme.accentOn)
                        .frame(width: 18, height: 18)
                        .accessibilityHidden(true)
                }

                Text(viewModel.operation == .savingInterval ? "保存中" : "取得間隔を保存")
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minWidth: 112)
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(!viewModel.canSaveInterval)
        .opacity(viewModel.canSaveInterval ? 1 : 0.58)
        .accessibilityLabel(viewModel.operation == .savingInterval ? "取得間隔を保存中" : "取得間隔を保存")
    }

    private var statusSection: some View {
        HStack(alignment: .top, spacing: 12) {
            FeedmanFaviconView(
                faviconURL: viewModel.faviconURL,
                displayName: viewModel.title,
                size: 36,
                cornerRadius: 8
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.title)
                    .font(.headline)
                    .foregroundStyle(FeedmanTheme.foreground)
                    .fixedSize(horizontal: false, vertical: true)

                Text(statusLabel)
                    .font(.subheadline)
                    .foregroundStyle(FeedmanTheme.mutedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FeedmanTheme.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(FeedmanTheme.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(viewModel.title)、\(statusLabel)")
    }

    private var intervalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("取得間隔")
                .font(.caption.weight(.semibold))
                .foregroundStyle(FeedmanTheme.mutedForeground)

            Picker("取得間隔", selection: $viewModel.selectedIntervalMinutes) {
                ForEach(SubscriptionSettingsViewModel.supportedIntervals, id: \.self) { interval in
                    Text("\(interval)分").tag(Optional(interval))
                }
            }
            .pickerStyle(.segmented)
            .disabled(viewModel.operation == .savingInterval)
            .accessibilityLabel("取得間隔")

            if viewModel.selectedIntervalMinutes == nil {
                FeedmanBannerView(
                    message: unsupportedIntervalMessage,
                    style: .warning
                )
            }
        }
    }

    @ViewBuilder
    private var messageSection: some View {
        if let message = viewModel.message {
            switch message {
            case let .success(text):
                FeedmanBannerView(message: text, style: .success)
            case let .failure(error):
                FeedmanBannerView(message: "\(error.title)。\(error.message)", style: .error)
            }
        }
    }

    @ViewBuilder
    private var resumeSection: some View {
        if let statusMessage = viewModel.statusMessage {
            VStack(alignment: .leading, spacing: 10) {
                FeedmanBannerView(message: statusMessage, style: .warning)

                Button {
                    Task {
                        let didResume = await viewModel.resume()
                        guard didResume, let subscriptionID = viewModel.subscriptionID else {
                            return
                        }
                        onResumed(subscriptionID)
                    }
                } label: {
                    HStack(spacing: 8) {
                        if viewModel.operation == .resuming {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 18, height: 18)
                                .accessibilityHidden(true)
                        }

                        Label(viewModel.operation == .resuming ? "再開中" : "購読を再開", systemImage: "play.circle")
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canResume)
                .accessibilityLabel(viewModel.operation == .resuming ? "購読を再開中" : "購読を再開")
            }
        }
    }

    private var unsubscribeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .overlay(FeedmanTheme.border)

            Button(role: .destructive) {
                viewModel.requestUnsubscribeConfirmation()
            } label: {
                Label(
                    viewModel.operation == .unsubscribing ? "解除中" : "購読を解除",
                    systemImage: "trash"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!viewModel.canUnsubscribe)
            .accessibilityLabel(viewModel.operation == .unsubscribing ? "購読を解除中" : "購読を解除")
        }
    }

    private var statusLabel: String {
        switch viewModel.status {
        case .active:
            return "有効"
        case .stopped:
            return "停止中"
        case .error:
            return "取得エラー"
        }
    }

    private var unsupportedIntervalMessage: String {
        guard let originalIntervalMinutes = viewModel.originalIntervalMinutes else {
            return "取得間隔が未設定です。保存するには間隔を選択してください。"
        }

        return "現在の取得間隔 \(originalIntervalMinutes) 分はこの画面では保存対象外です。変更する場合のみ間隔を選択してください。"
    }
}

#Preview("Subscription Settings") {
    SubscriptionSettingsSheet(
        feed: Feed(
            id: "swift-blog",
            subscriptionID: "sub-swift-blog",
            title: "Swift Blog",
            unreadCount: 0,
            status: .error(message: "前回の取得に失敗しました"),
            fetchIntervalMinutes: 60
        ),
        repository: MockFeedRepository(),
        onDismiss: {},
        onIntervalSaved: { _, _ in },
        onResumed: { _ in },
        onUnsubscribed: { _ in }
    )
}
