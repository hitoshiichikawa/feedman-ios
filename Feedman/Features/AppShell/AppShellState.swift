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

struct AppShellState: Equatable {
    private(set) var currentRoute: AppShellRoute
    private(set) var isDrawerOpen: Bool

    init(
        currentRoute: AppShellRoute = .timeline,
        isDrawerOpen: Bool = false
    ) {
        self.currentRoute = currentRoute
        self.isDrawerOpen = isDrawerOpen
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
        isDrawerOpen = false
    }
}
