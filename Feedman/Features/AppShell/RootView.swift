import SwiftUI

struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.openURL) private var openURL
    @State private var shellState = AppShellState()
    @StateObject private var drawerFeedViewModel = AppShellDrawerFeedViewModel()
    @StateObject private var timelineViewModel: TimelineViewModel
    @StateObject private var feedViewModel: FeedViewModel
    @StateObject private var starredViewModel: StarredViewModel
    @StateObject private var itemStateCoordinator: ItemStateCoordinator
    @StateObject private var toastCenter = FeedmanToastCenter()

    private let drawerWidth: CGFloat = 280

    @MainActor
    init() {
        let itemStateCoordinator = ItemStateCoordinator()
        _itemStateCoordinator = StateObject(wrappedValue: itemStateCoordinator)
        _timelineViewModel = StateObject(
            wrappedValue: TimelineViewModel(itemStateCoordinator: itemStateCoordinator)
        )
        _feedViewModel = StateObject(
            wrappedValue: FeedViewModel(itemStateCoordinator: itemStateCoordinator)
        )
        _starredViewModel = StateObject(
            wrappedValue: StarredViewModel(itemStateCoordinator: itemStateCoordinator)
        )
    }

    var body: some View {
        Group {
            switch environment.authenticationState {
            case .restoring:
                sessionRestoringView
            case .unauthenticated:
                LoginRouteView(
                    authBaseURL: environment.authBaseURL,
                    authRepository: environment.authRepository
                ) { credentials in
                    environment.completeLogin(with: credentials)
                }
            case .authenticated:
                authenticatedShell
            }
        }
        .onChange(of: environment.authenticationState) { _ in
            presentPendingNotificationArticleIfPossible()
        }
        .onChange(of: environment.pendingNotificationArticleTarget) { _ in
            presentPendingNotificationArticleIfPossible()
        }
    }

    private var sessionRestoringView: some View {
        FeedmanLoadingView("セッションを確認しています", accessibilityLabel: "セッションを確認中")
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FeedmanTheme.background)
    }

    private var authenticatedShell: some View {
        NavigationStack {
            ZStack(alignment: .leading) {
                routeContent
                    .disabled(shellState.isDrawerOpen)
                    .accessibilityHidden(shellState.isDrawerOpen)
                    .offset(x: shellState.isDrawerOpen ? drawerWidth : 0)

                if shellState.isDrawerOpen {
                    FeedmanTheme.scrim
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            shellState.dismissDrawer()
                        }
                        .accessibilityLabel("メニューを閉じる")
                        .accessibilityAddTraits(.isButton)
                }

                DrawerView(
                    feedSectionState: drawerFeedViewModel.sectionState,
                    selectedItem: shellState.drawerSelection,
                    themeOverride: shellState.themeOverride,
                    showsKeywordSettingsAction: keywordSettingsRouteGate.showsDrawerEntry,
                    onSelectRoute: { route in
                        shellState.selectRoute(route)
                    },
                    onShowAccount: {
                        shellState.presentAccount()
                    },
                    onToggleTheme: {
                        shellState.toggleThemeOverride()
                    },
                    onShowFeedRegistration: {
                        shellState.presentFeedRegistration()
                    },
                    onShowKeywordSettings: {
                        _ = keywordSettingsRouteGate.presentKeywordSettings(on: &shellState)
                    },
                    onShowFeedSettings: { feed in
                        shellState.presentSubscriptionSettings(feed: feed)
                    },
                    onRetryFeeds: {
                        Task {
                            await drawerFeedViewModel.loadSubscriptions(repository: environment.feedRepository)
                        }
                    },
                    onDismiss: {
                        shellState.dismissDrawer()
                    }
                )
                .frame(width: drawerWidth)
                .offset(x: shellState.isDrawerOpen ? 0 : -(drawerWidth + 20))
                .allowsHitTesting(shellState.isDrawerOpen)
                .accessibilityHidden(!shellState.isDrawerOpen)
            }
            .animation(.easeInOut(duration: 0.2), value: shellState.isDrawerOpen)
            .animation(.easeInOut(duration: 0.2), value: shellState.currentRoute)
            .navigationTitle(shellState.title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        shellState.toggleDrawer()
                    } label: {
                        Image(systemName: "line.3.horizontal")
                    }
                    .accessibilityLabel("メニュー")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        shellState.activateSearch()
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("検索")

                    Button {
                        shellState.toggleThemeOverride()
                    } label: {
                        Image(systemName: shellState.themeOverride.systemImage)
                    }
                    .accessibilityLabel("テーマ切替")
                    .accessibilityValue(shellState.themeOverride.title)
                }
            }
            .sheet(item: activePresentationBinding) { presentation in
                sheetContent(for: presentation)
            }
            .task {
                await drawerFeedViewModel.loadSubscriptions(repository: environment.feedRepository)
            }
            .onAppear {
                presentPendingNotificationArticleIfPossible()
            }
            .feedmanToastOverlay(toastCenter: toastCenter, edge: .top)
        }
        .preferredColorScheme(shellState.themeOverride.preferredColorScheme)
    }

    private var activePresentationBinding: Binding<AppShellPresentation?> {
        Binding(
            get: { keywordSettingsRouteGate.visiblePresentation(from: shellState.activePresentation) },
            set: { presentation in
                if presentation == nil {
                    dismissActivePresentation()
                }
            }
        )
    }

    @ViewBuilder
    private var routeContent: some View {
        switch shellState.currentRoute {
        case .timeline:
            TimelineView(
                viewModel: timelineViewModel,
                repository: environment.feedRepository,
                itemRepository: environment.itemRepository,
                accessToken: environment.currentAccessToken,
                onSelectItem: { input in
                    presentArticleDetail(input)
                },
                onOpenLink: { url in
                    openURL(url)
                }
            )
        case .starred:
            StarredView(
                viewModel: starredViewModel,
                repository: environment.feedRepository,
                itemRepository: environment.itemRepository,
                accessToken: environment.currentAccessToken,
                itemStateChange: shellState.itemStateChange,
                onSelectItem: { input in
                    presentArticleDetail(input)
                },
                onOpenLink: { url in
                    openURL(url)
                },
                onAuthRequired: {
                    toastCenter.show("再ログインが必要です。", style: .warning)
                }
            )
        case let .feed(id, title):
            feedContent(feedID: id, routeTitle: title)
        case .search:
            GlobalSearchView(
                repository: environment.makeSearchRepository(),
                itemStateChange: shellState.itemStateChange,
                itemStateCoordinator: itemStateCoordinator,
                onSelectItem: { input in
                    presentArticleDetail(input)
                },
                onOpenLink: { request in
                    openSearchResultLink(request)
                },
                onAuthRequired: {
                    toastCenter.show("再ログインが必要です。", style: .warning)
                }
            )
        case .account:
            placeholderContent(
                systemImage: "person.crop.circle",
                title: "アカウント",
                subtitle: "ログアウトと退会の処理は後続 Issue で追加します。"
            )
        }
    }

    @ViewBuilder
    private func feedContent(feedID: String, routeTitle _: String) -> some View {
        if let feed = drawerFeedViewModel.sectionState.feeds.first(where: { $0.id == feedID }) {
            FeedView(
                viewModel: feedViewModel,
                feed: feed,
                repository: environment.feedRepository,
                itemRepository: environment.itemRepository,
                accessToken: environment.currentAccessToken,
                onSelectItem: { input in
                    presentArticleDetail(input)
                },
                onOpenLink: { url in
                    openURL(url)
                },
                onRequestResume: { _ in
                    toastCenter.show("再開操作は後続の購読設定で対応します。")
                }
            )
        } else {
            placeholderContent(
                systemImage: "exclamationmark.triangle",
                title: "フィードを表示できません",
                subtitle: "選択中のフィードは現在の placeholder 一覧にありません。"
            )
        }
    }

    private func placeholderContent(
        systemImage: String,
        title: String,
        subtitle: String
    ) -> some View {
        ScrollView {
            FeedmanEmptyStateView(
                systemImage: systemImage,
                title: title,
                subtitle: subtitle
            )
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FeedmanTheme.background)
    }

    @ViewBuilder
    private func sheetContent(for presentation: AppShellPresentation) -> some View {
        switch presentation {
        case .account:
            AccountRouteView(
                repository: environment.accountRepository,
                accessToken: environment.currentAccessToken,
                onDismiss: {
                    shellState.dismissPresentation()
                },
                onLogout: {
                    await environment.logout()
                    shellState.dismissPresentation()
                },
                onAccountDeleted: {
                    await environment.clearLocalAuthenticationAfterAccountDeletion()
                    shellState.dismissPresentation()
                }
            )
        case .feedRegistration:
            RegisterFeedSheet(
                repository: environment.feedRepository,
                onDismiss: {
                    shellState.dismissPresentation()
                },
                onRegistered: { registeredFeed in
                    completeFeedRegistration(registeredFeed)
                }
            )
        case .keywordSettings:
            if keywordSettingsRouteGate.showsDrawerEntry {
                KeywordSettingsSheet(
                    repository: environment.keywordRepository,
                    accessToken: environment.currentAccessToken,
                    onDismiss: {
                        shellState.dismissPresentation()
                    },
                    onAuthRequired: {
                        toastCenter.show("再ログインが必要です。", style: .warning)
                    }
                )
            } else {
                EmptyView()
            }
        case let .articleDetail(input):
            ArticleDetailSheet(
                input: input,
                repository: environment.itemRepository,
                accessToken: environment.currentAccessToken,
                itemStateCoordinator: itemStateCoordinator,
                onDismiss: {
                    dismissActivePresentation()
                },
                onAuthRequired: {
                    toastCenter.show("再ログインが必要です。", style: .warning)
                },
                onItemStateChange: { change in
                    shellState.applyItemStateChange(change)
                }
            )
        case let .subscriptionSettings(feed):
            SubscriptionSettingsSheet(
                feed: feed,
                repository: environment.feedRepository,
                onDismiss: {
                    shellState.dismissPresentation()
                },
                onIntervalSaved: { subscriptionID, interval in
                    drawerFeedViewModel.applySubscriptionSettings(
                        subscriptionID: subscriptionID,
                        fetchIntervalMinutes: interval
                    )
                    toastCenter.show("取得間隔を保存しました", style: .success)
                },
                onResumed: { subscriptionID in
                    drawerFeedViewModel.applySubscriptionResume(subscriptionID: subscriptionID)
                    toastCenter.show("購読を再開しました", style: .success)
                },
                onUnsubscribed: { subscriptionID in
                    completeUnsubscribe(subscriptionID: subscriptionID)
                }
            )
        }
    }

    private func dismissActivePresentation() {
        AppShellPresentationDismissalHandler.dismissActivePresentation(
            shellState: &shellState,
            clearPendingNotificationArticleTarget: {
                environment.clearPendingNotificationArticleTarget()
            }
        )
    }

    private var keywordSettingsRouteGate: AppShellKeywordSettingsRouteGate {
        AppShellKeywordSettingsRouteGate(notificationFeatures: environment.notificationFeatures)
    }

    private func presentPendingNotificationArticleIfPossible() {
        guard case .authenticated = environment.authenticationState,
              let target = environment.pendingNotificationArticleTarget
        else {
            return
        }

        guard shellState.presentNotificationArticleTarget(target) else {
            toastCenter.show("通知先の記事詳細を開けませんでした。", style: .warning)
            environment.clearPendingNotificationArticleTarget()
            return
        }
    }

    private func placeholderSheet(for presentation: AppShellPresentation) -> some View {
        FeedmanSheetShell(
            title: presentation.title,
            subtitle: presentation.subtitle,
            onDismiss: {
                shellState.dismissPresentation()
            }
        ) {
            VStack(alignment: .leading, spacing: 14) {
                Label {
                    Text(presentation.title)
                        .font(.headline)
                        .foregroundStyle(FeedmanTheme.foreground)
                } icon: {
                    Image(systemName: presentation.systemImage)
                        .foregroundStyle(FeedmanTheme.accent)
                }

                Text(presentation.detail)
                    .font(.subheadline)
                    .foregroundStyle(FeedmanTheme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FeedmanTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(FeedmanTheme.border, lineWidth: 1)
            }
        }
        .presentationDetents([.medium])
    }

    private func completeFeedRegistration(_ registeredFeed: RegisteredFeed) {
        toastCenter.show("\(registeredFeed.title) を登録しました", style: .success)
        Task {
            await drawerFeedViewModel.refreshSubscriptionsAfterFeedRegistration(
                registeredFeed,
                repository: environment.feedRepository
            )
        }
    }

    private func presentArticleDetail(_ input: ArticleDetailSheetInput) {
        guard shellState.presentArticleDetail(input) else {
            toastCenter.show("記事詳細を開けませんでした。", style: .warning)
            return
        }
    }

    private func openSearchResultLink(_ request: SearchResultOpenLinkRequest) {
        Task {
            await AppShellSearchResultOpenLinkCoordinator(
                itemRepository: environment.itemRepository,
                accessToken: environment.currentAccessToken,
                itemStateCoordinator: itemStateCoordinator,
                openURL: { url in
                    openURL(url)
                },
                onItemStateChange: { change in
                    shellState.applyItemStateChange(change)
                },
                onFailure: { failure in
                    toastCenter.show(failure.message, style: .warning)
                }
            )
            .open(request)
        }
    }

    private func completeUnsubscribe(subscriptionID: String) {
        if let removedFeed = drawerFeedViewModel.removeSubscription(subscriptionID: subscriptionID) {
            shellState.selectTimelineIfCurrentFeedWasRemoved(feedID: removedFeed.id)
            toastCenter.show("\(removedFeed.title) の購読を解除しました", style: .success)
        } else {
            toastCenter.show("購読を解除しました", style: .success)
        }
        shellState.dismissPresentation()
    }
}

private struct DrawerView: View {
    let feedSectionState: AppShellDrawerFeedSectionState
    let selectedItem: AppShellDrawerSelection
    let themeOverride: AppShellThemeOverride
    let showsKeywordSettingsAction: Bool
    let onSelectRoute: (AppShellRoute) -> Void
    let onShowAccount: () -> Void
    let onToggleTheme: () -> Void
    let onShowFeedRegistration: () -> Void
    let onShowKeywordSettings: () -> Void
    let onShowFeedSettings: (Feed) -> Void
    let onRetryFeeds: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    primaryRoutes

                    Divider()
                        .overlay(FeedmanTheme.border)

                    feedsSection

                    footer
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 18)
            }
            .scrollIndicators(.automatic)
        }
        .padding(.horizontal, 18)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(FeedmanTheme.background)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(FeedmanTheme.border)
                .frame(width: 1)
        }
    }

    private var primaryRoutes: some View {
        VStack(spacing: 6) {
            DrawerRouteButton(
                title: "すべての新着",
                systemImage: "sparkles",
                isSelected: selectedItem == .timeline,
                onTap: { onSelectRoute(.timeline) }
            )
            DrawerRouteButton(
                title: "お気に入り",
                systemImage: "star",
                isSelected: selectedItem == .starred,
                onTap: { onSelectRoute(.starred) }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var feedsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("フィード")
                .font(.caption.bold())
                .foregroundStyle(FeedmanTheme.mutedForeground)
                .padding(.horizontal, 6)

            VStack(spacing: 6) {
                ForEach(Array(feedSectionState.feeds.enumerated()), id: \.offset) { _, feed in
                    DrawerFeedButton(
                        feed: feed,
                        isSelected: selectedItem == .feed(id: feed.id),
                        onTap: {
                            onSelectRoute(.feed(id: feed.id, title: feed.title))
                        },
                        onSettingsTap: {
                            onShowFeedSettings(feed)
                        }
                    )
                }

                feedSectionStatus
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .foregroundStyle(FeedmanTheme.accentOn)
                .frame(width: 34, height: 34)
                .background(FeedmanTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            Text("Feedman")
                .font(.title3.bold())
                .foregroundStyle(FeedmanTheme.foreground)
                .lineLimit(1)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .foregroundStyle(FeedmanTheme.mutedForeground)
            .accessibilityLabel("閉じる")
        }
        .padding(.top, 18)
        .padding(.bottom, 4)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .overlay(FeedmanTheme.border)
                .padding(.bottom, 4)

            DrawerFooterActionButton(
                title: "アカウント",
                subtitle: "設定と利用状況",
                systemImage: "person.crop.circle",
                onTap: onShowAccount
            )

            DrawerFooterActionButton(
                title: "テーマ",
                subtitle: themeOverride.title,
                systemImage: themeOverride.systemImage,
                onTap: onToggleTheme
            )
            .accessibilityLabel("テーマ切替")
            .accessibilityValue(themeOverride.title)

            DrawerFooterActionButton(
                title: "フィードを登録",
                subtitle: "新しい購読を追加",
                systemImage: "plus.circle",
                onTap: onShowFeedRegistration
            )

            if showsKeywordSettingsAction {
                DrawerFooterActionButton(
                    title: "キーワード通知",
                    subtitle: "記事タイトルの通知条件",
                    systemImage: "bell.badge",
                    onTap: onShowKeywordSettings
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var feedSectionStatus: some View {
        switch feedSectionState {
        case let .loading(feeds) where feeds.isEmpty:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("読み込み中")
                    .font(.caption)
                    .foregroundStyle(FeedmanTheme.mutedForeground)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .accessibilityLabel("フィードを読み込み中")
        case .loading:
            EmptyView()
        case .loaded:
            EmptyView()
        case .empty:
            Text("購読フィードはありません")
                .font(.caption)
                .foregroundStyle(FeedmanTheme.mutedForeground)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .failed(message, _):
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(FeedmanTheme.mutedForeground)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: onRetryFeeds) {
                    Label("再試行", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(FeedmanTheme.accent)
                .accessibilityLabel("フィードを再試行")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
        }
    }
}
private struct DrawerRouteButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 22)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(isSelected ? FeedmanTheme.accent : FeedmanTheme.foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(isSelected ? FeedmanTheme.accentSoft : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "選択中" : "")
    }
}

private struct DrawerFeedButton: View {
    let feed: Feed
    let isSelected: Bool
    let onTap: () -> Void
    let onSettingsTap: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: onTap) {
                HStack(alignment: .center, spacing: 12) {
                    feedIcon

                    VStack(alignment: .leading, spacing: 3) {
                        Text(feed.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isSelected ? FeedmanTheme.accent : FeedmanTheme.foreground)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        if let statusText {
                            Text(statusText)
                                .font(.caption)
                                .foregroundStyle(FeedmanTheme.mutedForeground)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    if feed.unreadCount > 0 {
                        Text("\(feed.unreadCount)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(isSelected ? FeedmanTheme.accent : FeedmanTheme.mutedForeground)
                            .monospacedDigit()
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(isSelected ? FeedmanTheme.background : FeedmanTheme.muted)
                            .clipShape(Capsule())
                            .accessibilityLabel("未読 \(feed.unreadCount) 件")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(feed.title)
            .accessibilityValue(accessibilityValue)

            Button(action: onSettingsTap) {
                Image(systemName: "gearshape")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(feed.subscriptionID == nil ? FeedmanTheme.mutedForeground.opacity(0.5) : FeedmanTheme.mutedForeground)
            .disabled(feed.subscriptionID == nil)
            .accessibilityLabel("\(feed.title) の購読設定")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .background(isSelected ? FeedmanTheme.accentSoft : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var feedIcon: some View {
        FeedmanFaviconView(
            faviconURL: feed.faviconURL,
            displayName: feed.title,
            size: 28,
            cornerRadius: 8
        )
            .accessibilityHidden(true)
    }

    private var statusText: String? {
        switch feed.status {
        case .active:
            return nil
        case .stopped:
            return "停止中"
        case .error:
            return "取得エラー"
        }
    }

    private var accessibilityValue: String {
        var values: [String] = []
        if isSelected {
            values.append("選択中")
        }
        if feed.unreadCount > 0 {
            values.append("未読 \(feed.unreadCount) 件")
        }
        if let statusText {
            values.append(statusText)
        }
        return values.joined(separator: "、")
    }
}

private struct DrawerFooterActionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FeedmanTheme.accent)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FeedmanTheme.foreground)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(FeedmanTheme.mutedForeground)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(FeedmanTheme.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

#Preview {
    RootView()
        .environmentObject(AppEnvironment.preview)
}

private extension AppShellThemeOverride {
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .dark:
            return .dark
        case .light:
            return .light
        }
    }

    var systemImage: String {
        switch self {
        case .system:
            return "circle.lefthalf.filled"
        case .dark:
            return "moon"
        case .light:
            return "sun.max"
        }
    }
}

private extension AppShellPresentation {
    var title: String {
        switch self {
        case .account:
            return "アカウント"
        case .feedRegistration:
            return "フィードを登録"
        case .keywordSettings:
            return "キーワード通知"
        case .articleDetail:
            return "記事詳細"
        case .subscriptionSettings:
            return "購読設定"
        }
    }

    var subtitle: String {
        switch self {
        case .account:
            return "アカウント機能の入口"
        case .feedRegistration:
            return "サイト URL から購読を追加"
        case .keywordSettings:
            return "記事タイトルの通知条件"
        case .articleDetail:
            return "記事詳細"
        case .subscriptionSettings:
            return "取得間隔と購読状態"
        }
    }

    var detail: String {
        switch self {
        case .account:
            return "ログアウト、退会、ユーザー情報の表示は後続 Issue で実装します。この placeholder は実データや認証 API を使用しません。"
        case .feedRegistration:
            return "サイトの URL か RSS/Atom の URL を入力してフィードを登録します。"
        case .keywordSettings:
            return "記事タイトルに一致したキーワード通知の条件を管理します。"
        case .articleDetail:
            return "記事本文の詳細を表示します。"
        case .subscriptionSettings:
            return "購読フィードの取得間隔、再開、購読解除を操作します。"
        }
    }

    var systemImage: String {
        switch self {
        case .account:
            return "person.crop.circle"
        case .feedRegistration:
            return "plus.circle"
        case .keywordSettings:
            return "bell.badge"
        case .articleDetail:
            return "doc.text"
        case .subscriptionSettings:
            return "gearshape"
        }
    }
}
