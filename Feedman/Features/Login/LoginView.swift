import SwiftUI

struct LoginRouteView: View {
    @StateObject private var viewModel: LoginViewModel

    init(
        authBaseURL: URL,
        authRepository: any AuthRepository,
        sessionStarter: any WebAuthenticationSessionStarting = ASWebAuthenticationSessionCoordinator(),
        onAuthenticated: @escaping (TokenCredentials) -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: LoginViewModel(
                authBaseURL: authBaseURL,
                authRepository: authRepository,
                sessionStarter: sessionStarter,
                onAuthenticated: onAuthenticated
            )
        )
    }

    var body: some View {
        LoginView(viewModel: viewModel)
    }
}

struct LoginView: View {
    @ObservedObject var viewModel: LoginViewModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 32)

            VStack(spacing: 14) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(FeedmanTheme.accent)
                    .frame(width: 56, height: 56)
                    .background(FeedmanTheme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Feedman")
                        .font(.title.weight(.semibold))
                        .foregroundStyle(FeedmanTheme.foreground)

                    Text("Google アカウントでログインしてください。")
                        .font(.subheadline)
                        .foregroundStyle(FeedmanTheme.mutedForeground)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 12) {
                Button {
                    Task {
                        await viewModel.startGoogleLogin()
                    }
                } label: {
                    HStack(spacing: 10) {
                        if viewModel.state.isLoading(.google) {
                            ProgressView()
                                .tint(FeedmanTheme.accentOn)
                                .frame(width: 18, height: 18)
                        } else {
                            Image(systemName: "person.crop.circle.badge.checkmark")
                                .font(.system(size: 17, weight: .semibold))
                        }

                        Text(viewModel.state.isLoading(.google) ? "ログイン中" : "Google でログイン")
                            .font(.headline.weight(.semibold))
                    }
                    .foregroundStyle(FeedmanTheme.accentOn)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .padding(.horizontal, 16)
                    .background(viewModel.state.isLoading(.google) ? FeedmanTheme.accent.opacity(0.72) : FeedmanTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(!viewModel.state.isRetryEnabled)
                .accessibilityLabel(viewModel.state.isLoading(.google) ? "Google ログイン中" : "Google でログイン")

                statusMessage
            }
            .frame(maxWidth: 360)

            Spacer(minLength: 32)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FeedmanTheme.background)
    }

    @ViewBuilder
    private var statusMessage: some View {
        switch viewModel.state {
        case .canceled:
            Text("ログインをキャンセルしました。もう一度お試しください。")
                .font(.footnote)
                .foregroundStyle(FeedmanTheme.mutedForeground)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        case let .failed(_, message), let .resultUnknown(_, message):
            Text(message)
                .font(.footnote)
                .foregroundStyle(FeedmanTheme.danger)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        case .idle, .loading, .authenticated:
            EmptyView()
        }
    }
}

#Preview("Login") {
    LoginRouteView(
        authBaseURL: URL(string: "https://example.com")!,
        authRepository: UnavailableAuthRepository()
    ) { _ in }
}
