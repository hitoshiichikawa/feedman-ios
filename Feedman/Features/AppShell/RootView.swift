import SwiftUI

struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var shellState = AppShellState()
    @State private var items: [FeedItem] = []

    private let drawerWidth: CGFloat = 280
    private let drawerFeeds = AppShellPreviewData.drawerFeeds

    var body: some View {
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
                    feeds: drawerFeeds,
                    selectedItem: shellState.drawerSelection,
                    themeOverride: shellState.themeOverride,
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
                placeholderSheet(for: presentation)
            }
            .task {
                items = (try? await environment.feedRepository.crossFeedItems()) ?? []
            }
        }
        .preferredColorScheme(shellState.themeOverride.preferredColorScheme)
    }

    private var activePresentationBinding: Binding<AppShellPresentation?> {
        Binding(
            get: { shellState.activePresentation },
            set: { presentation in
                if presentation == nil {
                    shellState.dismissPresentation()
                }
            }
        )
    }

    @ViewBuilder
    private var routeContent: some View {
        switch shellState.currentRoute {
        case .timeline:
            itemList(
                items,
                emptyTitle: "新着記事はありません",
                emptySubtitle: "購読フィードの記事が取得できるとここに表示されます。"
            )
        case .starred:
            itemList(
                items.filter(\.isStarred),
                emptyTitle: "お気に入りはありません",
                emptySubtitle: "スターした記事がここに表示されます。"
            )
        case let .feed(id, title):
            feedContent(feedID: id, routeTitle: title)
        case .search:
            placeholderContent(
                systemImage: "magnifyingglass",
                title: "検索",
                subtitle: "検索画面の本実装は後続 Issue で追加します。"
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
    private func feedContent(feedID: String, routeTitle: String) -> some View {
        if drawerFeeds.contains(where: { $0.id == feedID }) {
            itemList(
                items.filter { $0.feedID == feedID },
                emptyTitle: "\(routeTitle.isEmpty ? "フィード" : routeTitle) の記事はありません",
                emptySubtitle: "フィード別一覧の本実装は後続 Issue で追加します。"
            )
        } else {
            placeholderContent(
                systemImage: "exclamationmark.triangle",
                title: "フィードを表示できません",
                subtitle: "選択中のフィードは現在の placeholder 一覧にありません。"
            )
        }
    }

    private func itemList(
        _ visibleItems: [FeedItem],
        emptyTitle: String,
        emptySubtitle: String
    ) -> some View {
        Group {
            if visibleItems.isEmpty {
                placeholderContent(
                    systemImage: "tray",
                    title: emptyTitle,
                    subtitle: emptySubtitle
                )
            } else {
                List(visibleItems) { item in
                    ItemSummaryRow(item: item)
                }
                .listStyle(.plain)
                .background(FeedmanTheme.background)
            }
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
}

private struct ItemSummaryRow: View {
    let item: FeedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.feedTitle)
                    .font(.caption)
                    .foregroundStyle(FeedmanTheme.mutedForeground)
                    .lineLimit(1)
                Spacer()
                if item.isStarred {
                    Image(systemName: "star.fill")
                        .foregroundStyle(FeedmanTheme.star)
                        .accessibilityLabel("スター済み")
                }
            }
            Text(item.title)
                .font(.headline)
                .foregroundStyle(item.isRead ? FeedmanTheme.mutedForeground : FeedmanTheme.foreground)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.summary)
                .font(.subheadline)
                .foregroundStyle(FeedmanTheme.mutedForeground)
                .lineLimit(2)
        }
        .padding(.vertical, 6)
    }
}

private struct DrawerView: View {
    let feeds: [Feed]
    let selectedItem: AppShellDrawerSelection
    let themeOverride: AppShellThemeOverride
    let onSelectRoute: (AppShellRoute) -> Void
    let onShowAccount: () -> Void
    let onToggleTheme: () -> Void
    let onShowFeedRegistration: () -> Void
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
                ForEach(feeds) { feed in
                    DrawerFeedButton(
                        feed: feed,
                        isSelected: selectedItem == .feed(id: feed.id),
                        onTap: {
                            onSelectRoute(.feed(id: feed.id, title: feed.title))
                        }
                    )
                }
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
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

    var body: some View {
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
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
            .background(isSelected ? FeedmanTheme.accentSoft : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(feed.title)
        .accessibilityValue(isSelected ? "選択中" : "")
    }

    private var feedIcon: some View {
        Text(String(feed.title.prefix(1)))
            .font(.caption.bold())
            .foregroundStyle(FeedmanTheme.accent)
            .frame(width: 28, height: 28)
            .background(FeedmanTheme.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
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

private enum AppShellPreviewData {
    static let drawerFeeds = [
        Feed(id: "publickey", title: "Publickey", unreadCount: 12, status: .active),
        Feed(id: "zenn", title: "Zenn トレンド", unreadCount: 5, status: .active),
        Feed(id: "qiita", title: "Qiita 人気の記事", unreadCount: 0, status: .stopped(message: "手動で停止しました"))
    ]
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
        }
    }

    var subtitle: String {
        switch self {
        case .account:
            return "アカウント機能の入口"
        case .feedRegistration:
            return "フィード登録機能の入口"
        }
    }

    var detail: String {
        switch self {
        case .account:
            return "ログアウト、退会、ユーザー情報の表示は後続 Issue で実装します。この placeholder は実データや認証 API を使用しません。"
        case .feedRegistration:
            return "フィード URL の入力、検出、登録 API 連携は後続 Issue で実装します。この placeholder からネットワーク送信は行いません。"
        }
    }

    var systemImage: String {
        switch self {
        case .account:
            return "person.crop.circle"
        case .feedRegistration:
            return "plus.circle"
        }
    }
}
