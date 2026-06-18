import SwiftUI

struct StarredView: View {
    @ObservedObject var viewModel: StarredViewModel

    private let repository: any FeedRepository
    private let itemRepository: any ItemRepository
    private let accessToken: String?
    private let itemStateChange: ItemStateChange?
    private let onSelectItem: (ArticleDetailSheetInput) -> Void
    private let onOpenLink: (URL) -> Void
    private let onAuthRequired: () -> Void

    init(
        viewModel: StarredViewModel,
        repository: any FeedRepository,
        itemRepository: any ItemRepository,
        accessToken: String?,
        itemStateChange: ItemStateChange?,
        onSelectItem: @escaping (ArticleDetailSheetInput) -> Void,
        onOpenLink: @escaping (URL) -> Void,
        onAuthRequired: @escaping () -> Void = {}
    ) {
        self.viewModel = viewModel
        self.repository = repository
        self.itemRepository = itemRepository
        self.accessToken = accessToken
        self.itemStateChange = itemStateChange
        self.onSelectItem = onSelectItem
        self.onOpenLink = onOpenLink
        self.onAuthRequired = onAuthRequired
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FeedmanTheme.background)
            .task {
                viewModel.configure(
                    repository: repository,
                    itemRepository: itemRepository,
                    accessToken: accessToken,
                    onAuthRequired: onAuthRequired
                )
                viewModel.handleItemStateChange(itemStateChange)
                await viewModel.loadInitialIfNeeded()
            }
            .onChange(of: itemStateChange) { change in
                viewModel.handleItemStateChange(change)
            }
            .refreshable {
                viewModel.configure(
                    repository: repository,
                    itemRepository: itemRepository,
                    accessToken: accessToken,
                    onAuthRequired: onAuthRequired
                )
                await viewModel.refresh()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ScrollView {
                FeedmanLoadingView(
                    "お気に入りを読み込んでいます",
                    accessibilityLabel: "お気に入りを読み込み中"
                )
                .padding(16)
            }
        case .empty:
            emptyContent
        case let .failed(message, isAuthRequired):
            failedContent(message: message, isAuthRequired: isAuthRequired)
        case .loaded:
            starredList
        }
    }

    private var emptyContent: some View {
        ScrollView {
            FeedmanEmptyStateView(
                systemImage: "star",
                title: "お気に入りはありません",
                subtitle: "スターを付けた記事がここに表示されます。"
            )
            .padding(16)
        }
    }

    private func failedContent(message: String, isAuthRequired: Bool) -> some View {
        ScrollView {
            FeedmanRecoverableErrorView(
                title: isAuthRequired ? "再ログインが必要です" : "お気に入りを読み込めませんでした",
                message: message,
                usesDangerEmphasis: !isAuthRequired,
                retryDescriptor: FeedmanRetryDescriptor(accessibilityLabel: "お気に入りの読み込みを再試行")
            ) {
                Button("再試行") {
                    Task {
                        await viewModel.retryInitialLoad()
                    }
                }
            }
            .padding(16)
        }
    }

    private var starredList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if let refreshErrorMessage = viewModel.refreshErrorMessage {
                    FeedmanBannerView(
                        message: refreshErrorMessage,
                        style: .warning
                    ) {
                        Button("再試行") {
                            Task {
                                await viewModel.refresh()
                            }
                        }
                    }
                }

                if let starMutationErrorMessage = viewModel.starMutationErrorMessage {
                    FeedmanBannerView(
                        message: starMutationErrorMessage,
                        style: .warning
                    )
                }

                ForEach(viewModel.items, id: \.id) { item in
                    StarredItemCard(
                        descriptor: viewModel.descriptor(for: item),
                        onSelectItem: { id in
                            viewModel.selectItem(id: id)
                            onSelectItem(viewModel.detailInput(for: id))
                        },
                        onToggleStar: { id in
                            Task {
                                await viewModel.toggleStar(id: id)
                            }
                        },
                        onOpenLink: onOpenLink
                    )
                    .onAppear {
                        Task {
                            await viewModel.loadNextPageIfNeeded(currentItemID: item.id)
                        }
                    }
                }

                bottomPaginationContent
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var bottomPaginationContent: some View {
        if viewModel.isLoadingNextPage {
            FeedmanCompactLoadingRow("続きを読み込んでいます")
        } else if let nextPageErrorMessage = viewModel.nextPageErrorMessage {
            FeedmanBannerView(
                message: nextPageErrorMessage,
                style: .warning
            ) {
                Button("再試行") {
                    Task {
                        await viewModel.retryNextPage()
                    }
                }
            }
        } else if !viewModel.canLoadMore, !viewModel.items.isEmpty {
            Text("最後まで読みました")
                .font(.footnote)
                .foregroundStyle(FeedmanTheme.mutedForeground)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityLabel("最後まで読みました")
        }
    }
}

private struct StarredItemCard: View {
    let descriptor: StarredItemCardDescriptor
    let onSelectItem: (String) -> Void
    let onToggleStar: (String) -> Void
    let onOpenLink: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                descriptor.select(onSelectItem)
            } label: {
                VStack(alignment: .leading, spacing: 10) {
                    ArticleSourceRow(
                        metadata: descriptor.sourceMetadata,
                        size: .timeline
                    )

                    Text(descriptor.title)
                        .font(.headline)
                        .foregroundStyle(FeedmanTheme.foreground)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if let summary = descriptor.summary {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(FeedmanTheme.mutedForeground)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                ArticleHatebuCountControl(
                    state: descriptor.hatebuState,
                    size: .timeline
                )

                Spacer(minLength: 8)

                ArticleStarControl(
                    isStarred: descriptor.isStarred,
                    isEnabled: descriptor.isStarControlEnabled,
                    size: .timeline,
                    onToggle: {
                        descriptor.toggleStar(onToggleStar)
                    }
                )
                .accessibilityHint(descriptor.isStarMutationPending ? "スターを保存中です" : "")

                ArticleOpenLinkControl(
                    value: descriptor.linkURL,
                    unavailableBehavior: .hidden,
                    size: .timeline,
                    onOpen: onOpenLink
                )
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FeedmanTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(FeedmanTheme.border, lineWidth: 1)
        }
        .opacity(descriptor.opacity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(descriptor.accessibilityLabel)
        .accessibilityValue(descriptor.item.isRead ? "既読" : "未読")
    }
}

#Preview {
    StarredView(
        viewModel: StarredViewModel(repository: MockFeedRepository(starredItemsState: .defaultItems)),
        repository: MockFeedRepository(starredItemsState: .defaultItems),
        itemRepository: MockItemRepository(),
        accessToken: "preview-access-token",
        itemStateChange: nil,
        onSelectItem: { _ in },
        onOpenLink: { _ in },
        onAuthRequired: {}
    )
}
