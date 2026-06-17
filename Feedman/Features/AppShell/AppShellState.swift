import Foundation

enum AppShellRoute: Equatable, Hashable {
    case timeline
    case starred
    case feed(id: String, title: String)
    case search
    case account

    var title: String {
        switch self {
        case .timeline:
            return "すべての新着"
        case .starred:
            return "お気に入り"
        case let .feed(_, title):
            return title.isEmpty ? "フィード" : title
        case .search:
            return "検索"
        case .account:
            return "アカウント"
        }
    }

    var drawerSelection: AppShellDrawerSelection {
        switch self {
        case .timeline:
            return .timeline
        case .starred:
            return .starred
        case let .feed(id, _):
            return .feed(id: id)
        case .search:
            return .search
        case .account:
            return .account
        }
    }
}

enum AppShellDrawerSelection: Equatable, Hashable {
    case timeline
    case starred
    case feed(id: String)
    case search
    case account
}

enum AppShellPresentation: Equatable, Identifiable {
    case account
    case feedRegistration
    case articleDetail(ArticleDetailSheetInput)
    case subscriptionSettings(Feed)

    var id: String {
        switch self {
        case .account:
            return "account"
        case .feedRegistration:
            return "feedRegistration"
        case let .articleDetail(input):
            return "articleDetail-\(input.id)"
        case let .subscriptionSettings(feed):
            return "subscriptionSettings-\(feed.subscriptionID ?? feed.id)"
        }
    }
}

enum AppShellThemeOverride: Equatable {
    case system
    case dark
    case light

    var title: String {
        switch self {
        case .system:
            return "システム"
        case .dark:
            return "ダーク"
        case .light:
            return "ライト"
        }
    }

    var next: AppShellThemeOverride {
        switch self {
        case .system:
            return .dark
        case .dark:
            return .light
        case .light:
            return .system
        }
    }
}

enum AppShellSearchResultOpenLinkFailure: Equatable {
    case authRequired
    case readMarkingFailed

    var message: String {
        switch self {
        case .authRequired:
            return "再ログインが必要です。"
        case .readMarkingFailed:
            return "既読状態を保存できませんでした。"
        }
    }
}

@MainActor
struct AppShellSearchResultOpenLinkCoordinator {
    let itemRepository: any ItemRepository
    let accessToken: String?
    let openURL: (URL) -> Void
    let onItemStateChange: (ItemStateChange) -> Void
    let onFailure: (AppShellSearchResultOpenLinkFailure) -> Void

    func open(_ request: SearchResultOpenLinkRequest) async {
        openURL(request.url)

        guard let accessToken = accessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !accessToken.isEmpty
        else {
            onFailure(.authRequired)
            return
        }

        do {
            try await itemRepository.updateItemState(
                id: request.itemID,
                request: ItemStateUpdateRequest(isRead: true, isStarred: nil),
                accessToken: accessToken
            )
            onItemStateChange(ItemStateChange(itemID: request.itemID, isRead: true, isStarred: nil))
        } catch {
            if case FeedmanAPIError.authRequired = error {
                onFailure(.authRequired)
            } else {
                onFailure(.readMarkingFailed)
            }
        }
    }
}

struct AppShellState: Equatable {
    private(set) var currentRoute: AppShellRoute
    private(set) var isDrawerOpen: Bool
    private(set) var activePresentation: AppShellPresentation?
    private(set) var themeOverride: AppShellThemeOverride
    private(set) var itemStateChange: ItemStateChange?

    init(
        currentRoute: AppShellRoute = .timeline,
        isDrawerOpen: Bool = false,
        activePresentation: AppShellPresentation? = nil,
        themeOverride: AppShellThemeOverride = .system,
        itemStateChange: ItemStateChange? = nil
    ) {
        self.currentRoute = currentRoute
        self.isDrawerOpen = isDrawerOpen
        self.activePresentation = activePresentation
        self.themeOverride = themeOverride
        self.itemStateChange = itemStateChange
    }

    var title: String {
        currentRoute.title
    }

    var drawerSelection: AppShellDrawerSelection {
        currentRoute.drawerSelection
    }

    mutating func openDrawer() {
        isDrawerOpen = true
    }

    mutating func toggleDrawer() {
        isDrawerOpen.toggle()
    }

    mutating func dismissDrawer() {
        isDrawerOpen = false
    }

    mutating func selectRoute(_ route: AppShellRoute) {
        if route != currentRoute {
            currentRoute = route
        }
        activePresentation = nil
        isDrawerOpen = false
    }

    mutating func activateSearch() {
        selectRoute(.search)
    }

    mutating func presentAccount() {
        activePresentation = .account
        isDrawerOpen = false
    }

    mutating func presentFeedRegistration() {
        activePresentation = .feedRegistration
        isDrawerOpen = false
    }

    mutating func presentArticleDetail(_ input: ArticleDetailSheetInput) -> Bool {
        guard !input.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        activePresentation = .articleDetail(input)
        isDrawerOpen = false
        return true
    }

    mutating func presentSubscriptionSettings(feed: Feed) {
        activePresentation = .subscriptionSettings(feed)
        isDrawerOpen = false
    }

    mutating func dismissPresentation() {
        activePresentation = nil
    }

    mutating func applyItemStateChange(_ change: ItemStateChange) {
        itemStateChange = change
    }

    mutating func selectTimelineIfCurrentFeedWasRemoved(feedID: String) {
        guard case let .feed(id, _) = currentRoute, id == feedID else {
            return
        }

        currentRoute = .timeline
    }

    mutating func toggleThemeOverride() {
        themeOverride = themeOverride.next
    }
}
