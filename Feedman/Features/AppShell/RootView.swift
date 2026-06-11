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
                    onSelectRoute: { route in
                        shellState.selectRoute(route)
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        shellState.selectRoute(.search)
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("検索")
                }
            }
            .task {
                items = (try? await environment.feedRepository.crossFeedItems()) ?? []
            }
        }
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
    let onSelectRoute: (AppShellRoute) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

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

            Divider()
                .overlay(FeedmanTheme.border)

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

            Spacer(minLength: 12)

            DrawerRouteButton(
                title: "アカウント",
                systemImage: "person",
                isSelected: selectedItem == .account,
                onTap: { onSelectRoute(.account) }
            )
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(FeedmanTheme.background)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(FeedmanTheme.border)
                .frame(width: 1)
        }
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
        .padding(.top, 8)
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
