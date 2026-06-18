import SwiftUI

struct AccountRouteView: View {
    let repository: any AccountRepository
    let accessToken: String?
    let onDismiss: () -> Void
    let onAccountDeleted: AccountViewModel.AccountDeletionCompletion

    @StateObject private var viewModel: AccountViewModel

    init(
        repository: any AccountRepository,
        accessToken: String?,
        onDismiss: @escaping () -> Void,
        onAccountDeleted: @escaping AccountViewModel.AccountDeletionCompletion
    ) {
        self.repository = repository
        self.accessToken = accessToken
        self.onDismiss = onDismiss
        self.onAccountDeleted = onAccountDeleted
        _viewModel = StateObject(
            wrappedValue: AccountViewModel(
                repository: repository,
                accessToken: accessToken,
                onAccountDeleted: onAccountDeleted
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
        .alert(
            "退会しますか？",
            isPresented: deletionConfirmationBinding,
            actions: {
                Button("キャンセル", role: .cancel) {
                    viewModel.cancelDeleteAccountConfirmation()
                }
                Button("退会する", role: .destructive) {
                    Task {
                        await viewModel.confirmDeleteAccount()
                    }
                }
            },
            message: {
                Text("アカウントと保存された購読情報を削除します。この操作は取り消せません。")
            }
        )
    }

    private var deletionConfirmationBinding: Binding<Bool> {
        Binding(
            get: { viewModel.deletionState.isConfirming },
            set: { _ in }
        )
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
                usesDangerEmphasis: false,
                retryDescriptor: FeedmanRetryDescriptor(accessibilityLabel: "ユーザー情報の読み込みを再試行")
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
            deletionStatus
            Text("ログアウト処理は後続 Issue で接続します。")
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
                viewModel.requestDeleteAccountConfirmation()
            } label: {
                Label("退会（アカウント削除）", systemImage: "trash")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(AccountActionButtonStyle(foregroundColor: FeedmanTheme.danger))
            .disabled(viewModel.deletionState.isDeleting)
            .accessibilityLabel("退会、アカウント削除")
        }
    }

    @ViewBuilder
    private var deletionStatus: some View {
        switch viewModel.deletionState {
        case .idle, .confirming, .succeeded:
            EmptyView()
        case .deleting:
            FeedmanCompactLoadingRow(
                "退会処理を実行しています",
                accessibilityLabel: "退会処理を実行中"
            )
        case let .failed(errorState):
            FeedmanRecoverableErrorView(
                title: errorState.title,
                message: errorState.message,
                usesDangerEmphasis: true,
                retryDescriptor: FeedmanRetryDescriptor(
                    label: "もう一度退会する",
                    accessibilityLabel: "退会処理をもう一度実行"
                )
            ) {
                Button {
                    viewModel.requestDeleteAccountConfirmation()
                } label: {
                    Text("もう一度退会する")
                }
            }
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
