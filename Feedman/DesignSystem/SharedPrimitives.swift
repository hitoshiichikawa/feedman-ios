import SwiftUI

struct FeedmanLoadingView: View {
    let message: String?
    let accessibilityLabel: String

    init(
        _ message: String? = nil,
        accessibilityLabel: String = "読み込み中"
    ) {
        self.message = message
        self.accessibilityLabel = accessibilityLabel
    }

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(FeedmanTheme.accent)
                .frame(width: 28, height: 28)

            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(FeedmanTheme.mutedForeground)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 160)
        .background(FeedmanTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(FeedmanTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct FeedmanCompactLoadingRow: View {
    let message: String?
    let accessibilityLabel: String

    init(
        _ message: String? = nil,
        accessibilityLabel: String = "追加読み込み中"
    ) {
        self.message = message
        self.accessibilityLabel = accessibilityLabel
    }

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(FeedmanTheme.accent)
                .frame(width: 18, height: 18)

            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(FeedmanTheme.mutedForeground)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct FeedmanEmptyStateView<PrimaryAction: View>: View {
    let systemImage: String
    let title: String
    let subtitle: String?
    private let primaryAction: PrimaryAction?

    init(
        systemImage: String,
        title: String,
        subtitle: String? = nil,
        @ViewBuilder primaryAction: () -> PrimaryAction
    ) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.primaryAction = primaryAction()
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(FeedmanTheme.accent)
                .frame(width: 52, height: 52)
                .background(FeedmanTheme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(FeedmanTheme.foreground)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(FeedmanTheme.mutedForeground)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let primaryAction {
                primaryAction
                    .buttonStyle(FeedmanPrimaryButtonStyle())
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(FeedmanTheme.muted)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }
}

extension FeedmanEmptyStateView where PrimaryAction == EmptyView {
    init(
        systemImage: String,
        title: String,
        subtitle: String? = nil
    ) {
        self.systemImage = systemImage
        self.title = title
        self.subtitle = subtitle
        self.primaryAction = nil
    }
}

struct FeedmanRecoverableErrorView<RetryAction: View>: View {
    let title: String
    let message: String?
    let usesDangerEmphasis: Bool
    private let retryAction: RetryAction?

    init(
        title: String,
        message: String? = nil,
        usesDangerEmphasis: Bool = true,
        @ViewBuilder retryAction: () -> RetryAction
    ) {
        self.title = title
        self.message = message
        self.usesDangerEmphasis = usesDangerEmphasis
        self.retryAction = retryAction()
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: usesDangerEmphasis ? "exclamationmark.triangle.fill" : "wifi.exclamationmark")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(usesDangerEmphasis ? FeedmanTheme.danger : FeedmanTheme.accent)
                .frame(width: 52, height: 52)
                .background(usesDangerEmphasis ? FeedmanTheme.danger.opacity(0.12) : FeedmanTheme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(FeedmanTheme.foreground)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let message {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(FeedmanTheme.mutedForeground)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let retryAction {
                retryAction
                    .buttonStyle(FeedmanPrimaryButtonStyle())
                    .accessibilityLabel("再試行")
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 220)
        .background(FeedmanTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(FeedmanTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(errorAccessibilityLabel)
    }

    private var errorAccessibilityLabel: String {
        if let message {
            return "\(title)。\(message)"
        }
        return title
    }
}

extension FeedmanRecoverableErrorView where RetryAction == EmptyView {
    init(
        title: String,
        message: String? = nil,
        usesDangerEmphasis: Bool = true
    ) {
        self.title = title
        self.message = message
        self.usesDangerEmphasis = usesDangerEmphasis
        self.retryAction = nil
    }
}

struct FeedmanToast: Equatable, Identifiable {
    enum Style: Equatable {
        case neutral
        case success
        case warning
        case error
    }

    let id: UUID
    let message: String
    let style: Style
    let duration: TimeInterval

    init(
        id: UUID = UUID(),
        message: String,
        style: Style = .neutral,
        duration: TimeInterval = 3
    ) {
        self.id = id
        self.message = message
        self.style = style
        self.duration = duration
    }

    var systemImage: String? {
        switch style {
        case .neutral:
            return nil
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }
}

@MainActor
final class FeedmanToastCenter: ObservableObject {
    @Published private(set) var currentToast: FeedmanToast?
    private var dismissalTask: Task<Void, Never>?

    func show(
        _ message: String,
        style: FeedmanToast.Style = .neutral,
        duration: TimeInterval = 3
    ) {
        show(FeedmanToast(message: message, style: style, duration: duration))
    }

    func show(_ toast: FeedmanToast) {
        dismissalTask?.cancel()
        dismissalTask = nil
        currentToast = toast

        guard toast.duration > 0 else {
            return
        }

        dismissalTask = Task { [weak self] in
            let nanoseconds = UInt64(toast.duration * 1_000_000_000)
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            await self?.dismissIfCurrent(id: toast.id)
        }
    }

    func dismiss() {
        dismissalTask?.cancel()
        dismissalTask = nil
        currentToast = nil
    }

    private func dismissIfCurrent(id: UUID) {
        guard currentToast?.id == id else {
            return
        }
        dismissalTask = nil
        currentToast = nil
    }
}

struct FeedmanToastView: View {
    let toast: FeedmanToast

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let systemImage = toast.systemImage {
                Image(systemName: systemImage)
                    .font(.headline)
                    .foregroundStyle(iconColor)
                    .accessibilityHidden(true)
            }

            Text(toast.message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(FeedmanTheme.foreground)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(FeedmanTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(FeedmanTheme.borderStrong, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: FeedmanTheme.scrim.opacity(0.18), radius: 16, x: 0, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(toast.message)
        .accessibilityAddTraits(.isStaticText)
    }

    private var iconColor: Color {
        switch toast.style {
        case .neutral:
            return FeedmanTheme.mutedForeground
        case .success:
            return FeedmanTheme.accent
        case .warning, .error:
            return FeedmanTheme.danger
        }
    }
}

struct FeedmanToastOverlayModifier: ViewModifier {
    @ObservedObject var toastCenter: FeedmanToastCenter
    let edge: Edge

    func body(content: Content) -> some View {
        ZStack(alignment: alignment) {
            content

            if let toast = toastCenter.currentToast {
                FeedmanToastView(toast: toast)
                    .padding(.horizontal, 16)
                    .padding(edge == .top ? .top : .bottom, 14)
                    .transition(.move(edge: edge).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.snappy, value: toastCenter.currentToast?.id)
    }

    private var alignment: Alignment {
        edge == .top ? .top : .bottom
    }
}

extension View {
    func feedmanToastOverlay(
        toastCenter: FeedmanToastCenter,
        edge: Edge = .bottom
    ) -> some View {
        modifier(FeedmanToastOverlayModifier(toastCenter: toastCenter, edge: edge))
    }
}

struct FeedmanBannerView<ActionContent: View>: View {
    let message: String
    let style: FeedmanToast.Style
    private let actionContent: ActionContent?

    init(
        message: String,
        style: FeedmanToast.Style = .neutral,
        @ViewBuilder action: () -> ActionContent
    ) {
        self.message = message
        self.style = style
        self.actionContent = action()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(iconColor)
                    .accessibilityHidden(true)
            }

            Text(message)
                .font(.footnote)
                .foregroundStyle(FeedmanTheme.foreground)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if let actionContent {
                actionContent
                    .buttonStyle(FeedmanSecondaryButtonStyle())
            }
        }
        .padding(12)
        .background(backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(FeedmanTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(message)
    }

    private var systemImage: String? {
        FeedmanToast(message: message, style: style).systemImage
    }

    private var iconColor: Color {
        switch style {
        case .neutral:
            return FeedmanTheme.mutedForeground
        case .success:
            return FeedmanTheme.accent
        case .warning, .error:
            return FeedmanTheme.danger
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .neutral:
            return FeedmanTheme.surfaceSecondary
        case .success:
            return FeedmanTheme.accentSoft
        case .warning, .error:
            return FeedmanTheme.danger.opacity(0.10)
        }
    }
}

extension FeedmanBannerView where ActionContent == EmptyView {
    init(message: String, style: FeedmanToast.Style = .neutral) {
        self.message = message
        self.style = style
        self.actionContent = nil
    }
}

struct FeedmanSheetShell<Content: View, PrimaryAction: View>: View {
    let title: String
    let subtitle: String?
    let dismissAccessibilityLabel: String
    let onDismiss: () -> Void
    private let content: Content
    private let primaryAction: PrimaryAction?

    init(
        title: String,
        subtitle: String? = nil,
        dismissAccessibilityLabel: String = "閉じる",
        onDismiss: @escaping () -> Void,
        @ViewBuilder primaryAction: () -> PrimaryAction,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.dismissAccessibilityLabel = dismissAccessibilityLabel
        self.onDismiss = onDismiss
        self.primaryAction = primaryAction()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }

            if let primaryAction {
                VStack(spacing: 0) {
                    Divider()
                        .overlay(FeedmanTheme.border)

                    primaryAction
                        .buttonStyle(FeedmanPrimaryButtonStyle())
                        .padding(16)
                }
                .background(FeedmanTheme.surface)
            }
        }
        .background(FeedmanTheme.background)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(FeedmanTheme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(FeedmanTheme.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .foregroundStyle(FeedmanTheme.foreground)
            .background(FeedmanTheme.muted)
            .clipShape(Circle())
            .accessibilityLabel(dismissAccessibilityLabel)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(FeedmanTheme.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(FeedmanTheme.border)
                .frame(height: 1)
        }
        .accessibilityLabel(title)
    }
}

extension FeedmanSheetShell where PrimaryAction == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        dismissAccessibilityLabel: String = "閉じる",
        onDismiss: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.dismissAccessibilityLabel = dismissAccessibilityLabel
        self.onDismiss = onDismiss
        self.primaryAction = nil
        self.content = content()
    }
}

extension View {
    func feedmanSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        title: String,
        subtitle: String? = nil,
        detents: Set<PresentationDetent> = [.medium, .large],
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        sheet(isPresented: isPresented) {
            FeedmanSheetShell(
                title: title,
                subtitle: subtitle,
                onDismiss: { isPresented.wrappedValue = false },
                content: content
            )
            .presentationDetents(detents)
        }
    }

    func feedmanSheet<SheetContent: View, PrimaryAction: View>(
        isPresented: Binding<Bool>,
        title: String,
        subtitle: String? = nil,
        detents: Set<PresentationDetent> = [.medium, .large],
        @ViewBuilder primaryAction: @escaping () -> PrimaryAction,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        sheet(isPresented: isPresented) {
            FeedmanSheetShell(
                title: title,
                subtitle: subtitle,
                onDismiss: { isPresented.wrappedValue = false },
                primaryAction: primaryAction,
                content: content
            )
            .presentationDetents(detents)
        }
    }
}

private struct FeedmanPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(FeedmanTheme.accentOn)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .background(configuration.isPressed ? FeedmanTheme.accent.opacity(0.82) : FeedmanTheme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct FeedmanSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.semibold))
            .foregroundStyle(FeedmanTheme.accent)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: 36)
            .padding(.horizontal, 12)
            .background(configuration.isPressed ? FeedmanTheme.accentSoft.opacity(0.72) : FeedmanTheme.accentSoft)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview("Shared Primitives") {
    ScrollView {
        VStack(spacing: 16) {
            FeedmanLoadingView("最新の記事を読み込んでいます")
            FeedmanCompactLoadingRow("さらに読み込み中")
            FeedmanEmptyStateView(
                systemImage: "tray",
                title: "記事がありません",
                subtitle: "購読フィードに新しい記事が届くとここに表示されます。"
            ) {
                Button("フィードを追加") {}
            }
            FeedmanRecoverableErrorView(
                title: "読み込みに失敗しました",
                message: "通信状態を確認してからもう一度お試しください。"
            ) {
                Button("再試行") {}
            }
            FeedmanBannerView(message: "一部のフィードの取得が停止しています。", style: .warning) {
                Button("確認") {}
            }
            FeedmanToastView(toast: FeedmanToast(message: "保存しました", style: .success))
        }
        .padding()
    }
    .background(FeedmanTheme.background)
}

#Preview("Shared Primitives Dark") {
    ScrollView {
        VStack(spacing: 16) {
            FeedmanLoadingView("最新の記事を読み込んでいます")
            FeedmanEmptyStateView(
                systemImage: "star",
                title: "スター付き記事はまだありません",
                subtitle: "あとで読みたい記事にスターを付けるとここにまとまります。"
            )
            FeedmanRecoverableErrorView(
                title: "接続できません",
                message: "時間をおいて再試行してください。",
                usesDangerEmphasis: false
            ) {
                Button("再試行") {}
            }
            FeedmanBannerView(message: "登録が完了しました。", style: .success)
            FeedmanToastView(toast: FeedmanToast(message: "外部ブラウザで開きます"))
        }
        .padding()
    }
    .background(FeedmanTheme.background)
    .preferredColorScheme(.dark)
}

#Preview("Sheet Shell") {
    FeedmanSheetShell(
        title: "記事詳細",
        subtitle: "Publickey",
        onDismiss: {},
        primaryAction: {
            Button("元記事を開く") {}
        }
    ) {
        VStack(alignment: .leading, spacing: 12) {
            Text("SwiftUI reusable primitives")
                .font(.title3.bold())
            Text("Sheet shell は native sheet の上で header と action bar を共通化します。")
                .font(.body)
        }
    }
}
