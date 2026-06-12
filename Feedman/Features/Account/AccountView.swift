import SwiftUI

struct AccountRouteView: View {
    let repository: any AccountRepository
    let accessToken: String?
    let onDismiss: () -> Void

    @StateObject private var viewModel: AccountViewModel

    init(
        repository: any AccountRepository,
        accessToken: String?,
        onDismiss: @escaping () -> Void
    ) {
        self.repository = repository
        self.accessToken = accessToken
        self.onDismiss = onDismiss
        _viewModel = StateObject(
            wrappedValue: AccountViewModel(
                repository: repository,
                accessToken: accessToken
            )
        )
    }

    var body: some View {
        AccountView(viewModel: viewModel, onDismiss: onDismiss)
            .task {
                await viewModel.loadCurrentUser()
            }
    }
}

struct AccountView: View {
    @ObservedObject var viewModel: AccountViewModel
    let onDismiss: () -> Void

    var body: some View {
        FeedmanSheetShell(
            title: "アカウント",
            subtitle: "現在のログイン状態",
            dismissAccessibilityLabel: "アカウントシートを閉じる",
            onDismiss: onDismiss
        ) {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
        }
        .presentationDetents([.medium, .large])
        .alert(item: $viewModel.actionNotice) { notice in
            Alert(
                title: Text(notice.title),
                message: Text(notice.message),
                dismissButton: .default(Text("閉じる"))
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            FeedmanLoadingView(
                "ユーザー情報を読み込んでいます",
                accessibilityLabel: "ユーザー情報を読み込み中"
            )
        case let .loaded(user):
            loadedContent(user)
        case let .failed(errorState):
            FeedmanRecoverableErrorView(
                title: errorState.title,
                message: errorState.message,
                usesDangerEmphasis: false
            ) {
                Button {
                    Task {
                        await viewModel.retryCurrentUserLoading()
                    }
                } label: {
                    Text("再試行")
                }
                .disabled(viewModel.state.isLoading)
            }
        }
    }

    private func loadedContent(_ user: AccountDisplayUser) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            userCard(user)
            actionButtons
            Text("ログアウトと退会の実行処理は後続 Issue で接続します。")
                .font(.caption)
                .foregroundStyle(FeedmanTheme.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func userCard(_ user: AccountDisplayUser) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(FeedmanTheme.mutedForeground)
                .frame(width: 48, height: 48)
                .background(FeedmanTheme.muted)
                .clipShape(Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(user.displayName)
                    .font(.headline)
                    .foregroundStyle(FeedmanTheme.foreground)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("名前 \(user.displayName)")

                if let email = user.email {
                    Text(email)
                        .font(.subheadline)
                        .foregroundStyle(FeedmanTheme.mutedForeground)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("メールアドレス \(email)")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FeedmanTheme.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(FeedmanTheme.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                viewModel.requestLogoutPlaceholder()
            } label: {
                Label("ログアウト", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(AccountActionButtonStyle())
            .accessibilityLabel("ログアウト")

            Button(role: .destructive) {
                viewModel.requestDeleteAccountPlaceholder()
            } label: {
                Label("退会（アカウント削除）", systemImage: "trash")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(AccountActionButtonStyle(foregroundColor: FeedmanTheme.danger))
            .accessibilityLabel("退会、アカウント削除")
        }
    }
}

private struct AccountActionButtonStyle: ButtonStyle {
    var foregroundColor: Color = FeedmanTheme.foreground

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 14)
            .background(FeedmanTheme.surface)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(FeedmanTheme.border, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
