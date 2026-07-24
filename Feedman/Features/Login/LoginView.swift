import SwiftUI

enum LoginAuthenticationActionStyle: Equatable {
    case primary
    case secondary
    case text
}

enum LoginSignupInputField: Equatable {
    case username
}

enum LoginStatusMessageTone: Equatable {
    case neutral
    case error
    case resultUnknown
}

struct LoginActionPresentation: Equatable {
    let title: String
    let accessibilityLabel: String
    let style: LoginAuthenticationActionStyle
    let isLoading: Bool
    let isDisabled: Bool
}

struct LoginSignupPresentation: Equatable {
    let title: String
    let usernamePlaceholder: String
    let usernameAccessibilityLabel: String
    let submitTitle: String
    let submitAccessibilityLabel: String
    let inputFields: [LoginSignupInputField]
    let inputIsEnabled: Bool
    let submitButtonIsLoading: Bool
    let submitButtonIsDisabled: Bool
}

struct LoginStatusMessagePresentation: Equatable {
    let text: String
    let accessibilityLabel: String
    let tone: LoginStatusMessageTone
}

struct LoginPasskeyPresentation: Equatable {
    let googleButton: LoginActionPresentation
    let passkeyLoginButton: LoginActionPresentation
    let signup: LoginSignupPresentation
    let statusMessage: LoginStatusMessagePresentation?

    init(status: LoginAttemptStatus) {
        let isAnyLoading = status.isLoading
        let isGoogleLoading = status.isLoading(.google)
        let isPasskeyLoginLoading = status.isLoading(.passkeyLogin)
        let isPasskeyRegistrationLoading = status.isLoading(.passkeyRegistration)

        googleButton = LoginActionPresentation(
            title: isGoogleLoading ? "ログイン中" : "Google でログイン",
            accessibilityLabel: isGoogleLoading ? "Google ログイン中" : "Google でログイン",
            style: .primary,
            isLoading: isGoogleLoading,
            isDisabled: isAnyLoading
        )
        passkeyLoginButton = LoginActionPresentation(
            title: isPasskeyLoginLoading ? "パスキーログイン中" : "パスキーでログイン",
            accessibilityLabel: isPasskeyLoginLoading ? "パスキーログイン中" : "パスキーでログイン",
            style: .secondary,
            isLoading: isPasskeyLoginLoading,
            isDisabled: isAnyLoading
        )
        signup = LoginSignupPresentation(
            title: "アカウントを新規作成",
            usernamePlaceholder: "ユーザー名",
            usernameAccessibilityLabel: "ユーザー名",
            submitTitle: isPasskeyRegistrationLoading ? "アカウント作成中" : "ユーザー名とパスキーで新規作成",
            submitAccessibilityLabel: isPasskeyRegistrationLoading ? "アカウント作成中" : "ユーザー名とパスキーで新規作成",
            inputFields: [.username],
            inputIsEnabled: !isAnyLoading,
            submitButtonIsLoading: isPasskeyRegistrationLoading,
            submitButtonIsDisabled: isAnyLoading
        )

        switch status {
        case let .canceled(kind):
            statusMessage = LoginStatusMessagePresentation(
                text: Self.canceledMessage(for: kind),
                accessibilityLabel: Self.canceledMessage(for: kind),
                tone: .neutral
            )
        case let .failed(_, message):
            statusMessage = LoginStatusMessagePresentation(
                text: message,
                accessibilityLabel: message,
                tone: .error
            )
        case let .resultUnknown(_, message):
            statusMessage = LoginStatusMessagePresentation(
                text: message,
                accessibilityLabel: message,
                tone: .resultUnknown
            )
        case .idle, .loading, .authenticated:
            statusMessage = nil
        }
    }

    private static func canceledMessage(for kind: LoginAttemptKind) -> String {
        switch kind {
        case .google:
            return "ログインをキャンセルしました。もう一度お試しください。"
        case .passkeyLogin:
            return "パスキーログインをキャンセルしました。もう一度お試しください。"
        case .passkeyRegistration:
            return "アカウント作成をキャンセルしました。もう一度お試しください。"
        }
    }
}

struct LoginRouteView: View {
    @StateObject private var viewModel: LoginViewModel

    init(
        authBaseURL: URL,
        authRepository: any AuthRepository,
        sessionStarter: any WebAuthenticationSessionStarting = ASWebAuthenticationSessionCoordinator(),
        passkeyRepository: any PasskeyRepository = UnavailablePasskeyRepository(),
        passkeyCoordinator: any PasskeyPlatformAuthorizationCoordinating = UnavailablePasskeyPlatformAuthorizationCoordinator(),
        onAuthenticated: @escaping (TokenCredentials) -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: LoginViewModel(
                authBaseURL: authBaseURL,
                authRepository: authRepository,
                sessionStarter: sessionStarter,
                passkeyRepository: passkeyRepository,
                passkeyCoordinator: passkeyCoordinator,
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var signupUsername = ""
    @State private var activeAttemptTask: Task<Void, Never>?

    private var presentation: LoginPasskeyPresentation {
        LoginPasskeyPresentation(status: viewModel.attemptStatus)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 24)

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

                        Text("Google またはパスキーでログインできます。")
                            .font(.subheadline)
                            .foregroundStyle(FeedmanTheme.mutedForeground)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(spacing: 14) {
                    authenticationButton(
                        presentation.googleButton,
                        systemImage: "person.crop.circle.badge.checkmark",
                        progressTint: FeedmanTheme.accentOn
                    ) {
                        startGoogleLogin()
                    }

                    authenticationButton(
                        presentation.passkeyLoginButton,
                        systemImage: "key.fill",
                        progressTint: FeedmanTheme.accent
                    ) {
                        startPasskeyLogin()
                    }

                    VStack(spacing: 10) {
                        Text(presentation.signup.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(FeedmanTheme.foreground)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)

                        TextField(presentation.signup.usernamePlaceholder, text: $signupUsername)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 46)
                            .background(FeedmanTheme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(FeedmanTheme.border, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .disabled(!presentation.signup.inputIsEnabled)
                            .accessibilityLabel(presentation.signup.usernameAccessibilityLabel)
                            .onSubmit {
                                startPasskeyRegistration()
                            }

                        Button {
                            startPasskeyRegistration()
                        } label: {
                            HStack(spacing: 10) {
                                if presentation.signup.submitButtonIsLoading {
                                    ProgressView()
                                        .tint(FeedmanTheme.accent)
                                        .frame(width: 18, height: 18)
                                } else {
                                    Image(systemName: "person.badge.key.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                }

                                Text(presentation.signup.submitTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(FeedmanAccessibilityLayout.primaryActionLineLimit(for: dynamicTypeSize))
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .foregroundStyle(FeedmanTheme.accent)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .padding(.horizontal, 14)
                            .background(FeedmanTheme.accentSoft)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .disabled(presentation.signup.submitButtonIsDisabled)
                        .accessibilityLabel(presentation.signup.submitAccessibilityLabel)
                    }
                    .accessibilityElement(children: .contain)

                    statusMessage
                }
                .frame(maxWidth: 360)

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FeedmanTheme.background)
        .scrollDismissesKeyboard(.interactively)
        .onDisappear {
            cancelActiveAttempt()
        }
    }

    private func authenticationButton(
        _ presentation: LoginActionPresentation,
        systemImage: String,
        progressTint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if presentation.isLoading {
                    ProgressView()
                        .tint(progressTint)
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .semibold))
                }

                Text(presentation.title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(FeedmanAccessibilityLayout.primaryActionLineLimit(for: dynamicTypeSize))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(foregroundColor(for: presentation.style))
            .frame(maxWidth: .infinity, minHeight: 50)
            .padding(.horizontal, 16)
            .background(backgroundColor(for: presentation))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor(for: presentation.style), lineWidth: presentation.style == .secondary ? 1 : 0)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .disabled(presentation.isDisabled)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private func foregroundColor(for style: LoginAuthenticationActionStyle) -> Color {
        switch style {
        case .primary:
            return FeedmanTheme.accentOn
        case .secondary, .text:
            return FeedmanTheme.accent
        }
    }

    private func backgroundColor(for presentation: LoginActionPresentation) -> Color {
        switch presentation.style {
        case .primary:
            return presentation.isLoading ? FeedmanTheme.accent.opacity(0.72) : FeedmanTheme.accent
        case .secondary:
            return FeedmanTheme.surface
        case .text:
            return .clear
        }
    }

    private func borderColor(for style: LoginAuthenticationActionStyle) -> Color {
        switch style {
        case .primary, .text:
            return .clear
        case .secondary:
            return FeedmanTheme.borderStrong
        }
    }

    private func startGoogleLogin() {
        startAttempt {
            await viewModel.startGoogleLogin()
        }
    }

    private func startPasskeyLogin() {
        startAttempt {
            await viewModel.startPasskeyLogin()
        }
    }

    private func startPasskeyRegistration() {
        let username = signupUsername
        startAttempt {
            await viewModel.startPasskeyRegistration(username: username)
        }
    }

    private func startAttempt(_ operation: @escaping @MainActor () async -> Void) {
        activeAttemptTask?.cancel()
        let task = Task { @MainActor in
            await operation()
            activeAttemptTask = nil
        }
        activeAttemptTask = task
    }

    private func cancelActiveAttempt() {
        activeAttemptTask?.cancel()
        activeAttemptTask = nil
        viewModel.cancelActiveAttempt()
    }

    @ViewBuilder
    private var statusMessage: some View {
        if let statusMessage = presentation.statusMessage {
            Text(statusMessage.text)
                .font(.footnote)
                .foregroundStyle(statusColor(for: statusMessage.tone))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(statusMessage.accessibilityLabel)
        } else {
            EmptyView()
        }
    }

    private func statusColor(for tone: LoginStatusMessageTone) -> Color {
        switch tone {
        case .neutral:
            return FeedmanTheme.mutedForeground
        case .error, .resultUnknown:
            return FeedmanTheme.danger
        }
    }
}

#Preview("Login") {
    LoginRouteView(
        authBaseURL: URL(string: "https://example.com")!,
        authRepository: UnavailableAuthRepository()
    ) { _ in }
}
