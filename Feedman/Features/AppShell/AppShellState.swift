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

    var id: String {
        switch self {
        case .account:
            return "account"
        case .feedRegistration:
            return "feedRegistration"
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

struct AppShellState: Equatable {
    private(set) var currentRoute: AppShellRoute
    private(set) var isDrawerOpen: Bool
    private(set) var activePresentation: AppShellPresentation?
    private(set) var themeOverride: AppShellThemeOverride

    init(
        currentRoute: AppShellRoute = .timeline,
        isDrawerOpen: Bool = false,
        activePresentation: AppShellPresentation? = nil,
        themeOverride: AppShellThemeOverride = .system
    ) {
        self.currentRoute = currentRoute
        self.isDrawerOpen = isDrawerOpen
        self.activePresentation = activePresentation
        self.themeOverride = themeOverride
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

    mutating func dismissPresentation() {
        activePresentation = nil
    }

    mutating func toggleThemeOverride() {
        themeOverride = themeOverride.next
    }
}
