import SwiftUI

struct RegisterFeedSheet: View {
    @StateObject private var viewModel: RegisterFeedViewModel

    private let onDismiss: () -> Void
    private let onRegistered: (RegisteredFeed) -> Void

    init(
        repository: FeedRepository,
        initialURL: String = "",
        onDismiss: @escaping () -> Void,
        onRegistered: @escaping (RegisteredFeed) -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: RegisterFeedViewModel(
                repository: repository,
                initialURL: initialURL
            )
        )
        self.onDismiss = onDismiss
        self.onRegistered = onRegistered
    }

    var body: some View {
        FeedmanSheetShell(
            title: "フィードを登録",
            subtitle: "サイトの URL か RSS/Atom の URL を入力してください",
            onDismiss: onDismiss,
            primaryAction: {
                primaryAction
            }
        ) {
            VStack(alignment: .leading, spacing: 16) {
                urlField
                submissionContent
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch viewModel.submissionState {
        case let .success(registeredFeed):
            Button {
                onRegistered(registeredFeed)
            } label: {
                Text("完了")
                    .frame(maxWidth: .infinity)
            }
            .accessibilityLabel("登録を完了")
        default:
            Button {
                Task {
                    await viewModel.submit()
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.submissionState.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(FeedmanTheme.accentOn)
                            .frame(width: 18, height: 18)
                            .accessibilityHidden(true)
                    }

                    Text(viewModel.submissionState.isLoading ? "登録中" : "フィードを登録")
                        .lineLimit(1)
                        .frame(minWidth: 92)
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(!viewModel.canSubmit)
            .opacity(viewModel.canSubmit ? 1 : 0.58)
            .accessibilityLabel(viewModel.submissionState.isLoading ? "フィードを登録中" : "フィードを登録")
        }
    }

    private var urlField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("URL")
                .font(.caption.weight(.semibold))
                .foregroundStyle(FeedmanTheme.mutedForeground)

            HStack(spacing: 10) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FeedmanTheme.mutedForeground)
                    .accessibilityHidden(true)

                TextField("https://example.com", text: $viewModel.urlText)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .disabled(viewModel.submissionState.isLoading)
                    .onSubmit {
                        guard viewModel.canSubmit else {
                            return
                        }

                        Task {
                            await viewModel.submit()
                        }
                    }
                    .accessibilityLabel("フィード URL")
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(FeedmanTheme.muted)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var submissionContent: some View {
        switch viewModel.submissionState {
        case .input:
            Text("URL からフィードを自動検出して購読に追加します。")
                .font(.footnote)
                .foregroundStyle(FeedmanTheme.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("URL からフィードを自動検出して購読に追加します")
        case .loading:
            FeedmanCompactLoadingRow(
                "フィードを検出して登録しています",
                accessibilityLabel: "フィードを検出して登録しています"
            )
        case let .success(registeredFeed):
            successCard(registeredFeed)
        case let .failure(error):
            FeedmanBannerView(message: "\(error.title)。\(error.message)", style: bannerStyle(for: error.kind))
        }
    }

    private func successCard(_ registeredFeed: RegisteredFeed) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "checkmark")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(FeedmanTheme.accentOn)
                .frame(width: 32, height: 32)
                .background(FeedmanTheme.accent)
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(registeredFeed.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FeedmanTheme.foreground)
                    .fixedSize(horizontal: false, vertical: true)

                Text("フィードを登録しました")
                    .font(.caption)
                    .foregroundStyle(FeedmanTheme.mutedForeground)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FeedmanTheme.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(registeredFeed.title) を登録しました")
    }

    private func bannerStyle(for kind: RegisterFeedErrorPresentation.Kind) -> FeedmanToast.Style {
        switch kind {
        case .duplicate, .rateLimit:
            return .warning
        case .emptyInput, .invalidURL, .authRequired, .network, .generic:
            return .error
        }
    }
}

#Preview("Register Feed") {
    RegisterFeedSheet(
        repository: MockFeedRepository(),
        onDismiss: {},
        onRegistered: { _ in }
    )
}
