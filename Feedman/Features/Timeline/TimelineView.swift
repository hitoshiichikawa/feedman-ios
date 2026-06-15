import SwiftUI

struct TimelineView: View {
    @ObservedObject var viewModel: TimelineViewModel

    private let repository: any FeedRepository
    private let onSelectItem: (String) -> Void
    private let onOpenLink: (URL) -> Void

    init(
        viewModel: TimelineViewModel,
        repository: any FeedRepository,
        onSelectItem: @escaping (String) -> Void,
        onOpenLink: @escaping (URL) -> Void
    ) {
        self.viewModel = viewModel
        self.repository = repository
        self.onSelectItem = onSelectItem
        self.onOpenLink = onOpenLink
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(FeedmanTheme.background)
            .task {
                viewModel.configure(repository: repository)
                await viewModel.loadInitialIfNeeded()
            }
            .refreshable {
                viewModel.configure(repository: repository)
                await viewModel.refresh()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ScrollView {
                FeedmanLoadingView(
                    "新着記事を読み込んでいます",
                    accessibilityLabel: "新着記事を読み込み中"
                )
                .padding(16)
            }
        case .empty:
            emptyContent
        case let .failed(message):
            failedContent(message: message)
        case .loaded:
            timelineList
        }
    }

    private var emptyContent: some View {
        ScrollView {
            FeedmanEmptyStateView(
                systemImage: "tray",
                title: "新着記事はありません",
                subtitle: "購読フィードの記事が取得できるとここに表示されます。"
            )
            .padding(16)
        }
    }

    private func failedContent(message: String) -> some View {
        ScrollView {
            FeedmanRecoverableErrorView(
                title: "タイムラインを読み込めませんでした",
                message: message
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

    private var timelineList: some View {
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

                ForEach(viewModel.items, id: \.id) { item in
                    TimelineCard(
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

private struct TimelineCard: View {
    let descriptor: TimelineCardDescriptor
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
                    size: .timeline,
                    onToggle: {
                        descriptor.toggleStar(onToggleStar)
                    }
                )

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
    }
}

#Preview {
    TimelineView(
        viewModel: TimelineViewModel(repository: MockFeedRepository()),
        repository: MockFeedRepository(),
        onSelectItem: { _ in },
        onOpenLink: { _ in }
    )
}
