import SwiftUI

struct FeedView: View {
    @ObservedObject var viewModel: FeedViewModel

    let feed: Feed
    private let repository: any FeedRepository
    private let onSelectItem: (String) -> Void
    private let onOpenLink: (URL) -> Void
    private let onRequestResume: (String) -> Void

    init(
        viewModel: FeedViewModel,
        feed: Feed,
        repository: any FeedRepository,
        onSelectItem: @escaping (String) -> Void,
        onOpenLink: @escaping (URL) -> Void,
        onRequestResume: @escaping (String) -> Void
    ) {
        self.viewModel = viewModel
        self.feed = feed
        self.repository = repository
        self.onSelectItem = onSelectItem
        self.onOpenLink = onOpenLink
        self.onRequestResume = onRequestResume
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                topStatusContent
                refreshFeedbackContent
                filterControl
                stateContent
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FeedmanTheme.background)
        .task(id: feed.id) {
            viewModel.configure(repository: repository)
            await viewModel.loadInitialIfNeeded(feedID: feed.id)
        }
        .refreshable {
            await viewModel.refreshFeed(
                feedID: feed.id,
                subscriptionID: feed.subscriptionID
            )
        }
    }

    @ViewBuilder
    private var topStatusContent: some View {
        if let banner = viewModel.statusBanner(for: feed.status) {
            FeedmanBannerView(
                message: banner.message,
                style: banner.style
            ) {
                Button(banner.actionLabel) {
                    viewModel.requestResume(feedID: feed.id)
                    onRequestResume(feed.id)
                }
                .accessibilityLabel(banner.actionLabel)
            }
        }
    }

    @ViewBuilder
    private var refreshFeedbackContent: some View {
        if let feedback = viewModel.refreshFeedback {
            FeedmanBannerView(
                message: feedback.message,
                style: feedback.style
            )
        }
    }

    private var filterControl: some View {
        Picker("表示", selection: filterSelection) {
            Text("すべて").tag(FeedItemFilter.all)
            Text("未読").tag(FeedItemFilter.unread)
            Text("スター").tag(FeedItemFilter.starred)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: .infinity, minHeight: 44)
        .accessibilityLabel("表示フィルター")
    }

    private var filterSelection: Binding<FeedItemFilter> {
        Binding(
            get: { viewModel.filter },
            set: { newFilter in
                Task {
                    await viewModel.selectFilter(newFilter, feedID: feed.id)
                }
            }
        )
    }

    @ViewBuilder
    private var stateContent: some View {
        switch viewModel.visibleState(for: feed.id) {
        case .idle, .loading:
            FeedmanLoadingView(
                "記事を読み込んでいます",
                accessibilityLabel: "フィードの記事を読み込み中"
            )
        case .empty:
            emptyContent
        case let .failed(message):
            failedContent(message: message)
        case .loaded:
            itemList
        }
    }

    private var emptyContent: some View {
        FeedmanEmptyStateView(
            systemImage: "tray",
            title: "記事がありません",
            subtitle: viewModel.emptySubtitle
        )
    }

    private func failedContent(message: String) -> some View {
        FeedmanRecoverableErrorView(
            title: "フィードの記事を読み込めませんでした",
            message: message
        ) {
            Button("再試行") {
                Task {
                    await viewModel.retryInitialLoad(feedID: feed.id)
                }
            }
        }
    }

    private var itemList: some View {
        LazyVStack(spacing: 12) {
            ForEach(viewModel.items, id: \.id) { item in
                FeedItemCard(
                    descriptor: viewModel.descriptor(for: item),
                    onSelectItem: { id in
                        viewModel.selectItem(id: id)
                        onSelectItem(id)
                    },
                    onToggleStar: { id in
                        viewModel.toggleStar(id: id)
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

private struct FeedItemCard: View {
    let descriptor: FeedItemCardDescriptor
    let onSelectItem: (String) -> Void
    let onToggleStar: (String) -> Void
    let onOpenLink: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                descriptor.select(onSelectItem)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    ArticleSourceRow(
                        metadata: descriptor.sourceMetadata,
                        size: .standard
                    )

                    Text(descriptor.title)
                        .font(.headline)
                        .foregroundStyle(FeedmanTheme.foreground)
                        .lineLimit(2)
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
                    size: .standard
                )

                Spacer(minLength: 8)

                ArticleStarControl(
                    isStarred: descriptor.isStarred,
                    size: .standard,
                    onToggle: {
                        descriptor.toggleStar(onToggleStar)
                    }
                )

                ArticleOpenLinkControl(
                    value: descriptor.linkURL,
                    unavailableBehavior: .hidden,
                    size: .standard,
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
    FeedView(
        viewModel: FeedViewModel(repository: MockFeedRepository()),
        feed: Feed(
            id: "feed-swift",
            subscriptionID: "sub-feed-swift",
            title: "Swift News",
            unreadCount: 3,
            status: .stopped(message: "前回の取得でエラーが続いたため停止しています")
        ),
        repository: MockFeedRepository(),
        onSelectItem: { _ in },
        onOpenLink: { _ in },
        onRequestResume: { _ in }
    )
}
