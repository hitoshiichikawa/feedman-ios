import SwiftUI

struct AccountRouteView: View {
    let repository: any AccountRepository
    let accessToken: String?
    let onDismiss: () -> Void
    let onLogout: AccountViewModel.LogoutCompletion
    let onAccountDeleted: AccountViewModel.AccountDeletionCompletion
    let passkeyRepository: any PasskeyRepository
    let passkeyCoordinator: any PasskeyPlatformAuthorizationCoordinating

    @StateObject private var viewModel: AccountViewModel

    init(
        repository: any AccountRepository,
        accessToken: String?,
        onDismiss: @escaping () -> Void,
        onLogout: @escaping AccountViewModel.LogoutCompletion,
        onAccountDeleted: @escaping AccountViewModel.AccountDeletionCompletion,
        passkeyRepository: any PasskeyRepository = UnavailablePasskeyRepository(),
        passkeyCoordinator: any PasskeyPlatformAuthorizationCoordinating = UnavailablePasskeyPlatformAuthorizationCoordinator()
    ) {
        self.repository = repository
        self.accessToken = accessToken
        self.onDismiss = onDismiss
        self.onLogout = onLogout
        self.onAccountDeleted = onAccountDeleted
        self.passkeyRepository = passkeyRepository
        self.passkeyCoordinator = passkeyCoordinator
        _viewModel = StateObject(
            wrappedValue: AccountViewModel(
                repository: repository,
                accessToken: accessToken,
                passkeyRepository: passkeyRepository,
                passkeyCoordinator: passkeyCoordinator,
                onLogout: onLogout,
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
    @State private var passkeyEnrollmentTask: Task<Void, Never>?

    var body: some View {
        FeedmanSheetShell(
            title: "アカウント",
            subtitle: "現在のログイン状態",
            dismissAccessibilityLabel: "アカウントシートを閉じる",
            onDismiss: dismiss
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
        .onDisappear {
            cancelPasskeyEnrollment()
        }
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
            passkeyEnrollmentStatus
            logoutStatus
            deletionStatus
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

    @ViewBuilder
    private var actionButtons: some View {
        let passkeyPresentation = AccountPasskeyEnrollmentPresentation(
            passkeyState: viewModel.passkeyEnrollmentState,
            logoutState: viewModel.logoutState,
            deletionState: viewModel.deletionState
        )

        VStack(spacing: 10) {
            Button {
                startPasskeyEnrollment()
            } label: {
                Label(passkeyPresentation.addButtonTitle, systemImage: "person.badge.key")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(AccountActionButtonStyle())
            .disabled(passkeyPresentation.isAddDisabled)
            .accessibilityLabel(passkeyPresentation.addButtonAccessibilityLabel)

            Button {
                Task {
                    await viewModel.logout()
                }
            } label: {
                Label("ログアウト", systemImage: "rectangle.portrait.and.arrow.right")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(AccountActionButtonStyle())
            .disabled(passkeyPresentation.isLogoutDisabled)
            .accessibilityLabel("ログアウト")

            Button(role: .destructive) {
                viewModel.requestDeleteAccountConfirmation()
            } label: {
                Label("退会（アカウント削除）", systemImage: "trash")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(AccountActionButtonStyle(foregroundColor: FeedmanTheme.danger))
            .disabled(passkeyPresentation.isDeleteDisabled)
            .accessibilityLabel("退会、アカウント削除")
        }
    }

    @ViewBuilder
    private var passkeyEnrollmentStatus: some View {
        switch viewModel.passkeyEnrollmentState {
        case .idle, .succeeded:
            EmptyView()
        case .adding:
            FeedmanCompactLoadingRow(
                "パスキーを追加しています",
                accessibilityLabel: "パスキー追加処理中"
            )
        case let .canceled(errorState):
            FeedmanRecoverableErrorView(
                title: errorState.title,
                message: errorState.message,
                usesDangerEmphasis: false,
                retryDescriptor: FeedmanRetryDescriptor(
                    label: "もう一度パスキーを追加",
                    accessibilityLabel: "パスキー追加をもう一度実行"
                )
            ) {
                Button {
                    startPasskeyEnrollment()
                } label: {
                    Text("もう一度パスキーを追加")
                }
            }
        case let .failed(errorState):
            FeedmanRecoverableErrorView(
                title: errorState.title,
                message: errorState.message,
                usesDangerEmphasis: false,
                retryDescriptor: FeedmanRetryDescriptor(
                    label: "もう一度パスキーを追加",
                    accessibilityLabel: "パスキー追加をもう一度実行"
                )
            ) {
                Button {
                    startPasskeyEnrollment()
                } label: {
                    Text("もう一度パスキーを追加")
                }
            }
        case let .resultUnknown(errorState):
            FeedmanRecoverableErrorView(
                title: errorState.title,
                message: errorState.message,
                usesDangerEmphasis: false,
                retryDescriptor: FeedmanRetryDescriptor(
                    label: "再試行",
                    accessibilityLabel: "パスキー追加を再試行"
                )
            ) {
                Button {
                    startPasskeyEnrollment()
                } label: {
                    Text("再試行")
                }
            }
        }
    }

    @ViewBuilder
    private var logoutStatus: some View {
        switch viewModel.logoutState {
        case .idle:
            EmptyView()
        case .loggingOut:
            FeedmanCompactLoadingRow(
                "ログアウトしています",
                accessibilityLabel: "ログアウト処理中"
            )
        case let .failed(errorState):
            FeedmanRecoverableErrorView(
                title: errorState.title,
                message: errorState.message,
                usesDangerEmphasis: false,
                retryDescriptor: FeedmanRetryDescriptor(
                    label: "もう一度ログアウト",
                    accessibilityLabel: "ログアウト処理をもう一度実行"
                )
            ) {
                Button {
                    Task {
                        await viewModel.logout()
                    }
                } label: {
                    Text("もう一度ログアウト")
                }
            }
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

    private func startPasskeyEnrollment() {
        guard passkeyEnrollmentTask == nil else {
            return
        }

        let task = Task {
            await viewModel.startPasskeyEnrollment()
            passkeyEnrollmentTask = nil
        }
        passkeyEnrollmentTask = task
    }

    private func cancelPasskeyEnrollment() {
        passkeyEnrollmentTask?.cancel()
        passkeyEnrollmentTask = nil
        viewModel.cancelActivePasskeyEnrollment()
    }

    private func dismiss() {
        cancelPasskeyEnrollment()
        onDismiss()
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
