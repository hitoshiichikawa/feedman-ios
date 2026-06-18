import SwiftUI

struct ArticleDetailSheet: View {
    @StateObject private var viewModel: ArticleDetailViewModel
    @State private var safariPresentation: ArticleDetailSafariPresentation?

    private let input: ArticleDetailSheetInput
    private let onDismiss: () -> Void

    @MainActor
    init(
        input: ArticleDetailSheetInput,
        repository: any ItemRepository,
        accessToken: String?,
        itemStateCoordinator: ItemStateCoordinator? = nil,
        onDismiss: @escaping () -> Void,
        onAuthRequired: @escaping () -> Void = {},
        onItemStateChange: @escaping (ItemStateChange) -> Void = { _ in }
    ) {
        self.input = input
        self.onDismiss = onDismiss
        _viewModel = StateObject(
            wrappedValue: ArticleDetailViewModel(
                itemID: input.id,
                summary: input.summary,
                repository: repository,
                accessToken: accessToken,
                itemStateCoordinator: itemStateCoordinator,
                onAuthRequired: onAuthRequired,
                onItemStateChange: onItemStateChange
            )
        )
    }

    var body: some View {
        FeedmanSheetShell(
            title: "記事詳細",
            subtitle: subtitle,
            dismissAccessibilityLabel: "記事詳細を閉じる",
            onDismiss: onDismiss,
            primaryAction: {
                ArticleDetailFooter(
                    presentation: viewModel.loadedPresentation,
                    summary: input.summary,
                    isStarUpdateInFlight: viewModel.isStarUpdateInFlight,
                    onOpenOriginal: {
                        Task {
                            if let request = await viewModel.openOriginal() {
                                safariPresentation = ArticleDetailSafariPresentation(request: request)
                            }
                        }
                    },
                    onToggleStar: {
                        Task {
                            await viewModel.toggleStar()
                        }
                    }
                )
            }
        ) {
            ArticleDetailBody(
                state: viewModel.state,
                mutationMessage: viewModel.mutationMessage,
                onDismissMessage: {
                    viewModel.dismissMutationMessage()
                },
                onRetry: {
                    Task {
                        await viewModel.retry()
                    }
                }
            )
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await viewModel.open()
        }
        .sheet(item: $safariPresentation) { presentation in
            ArticleDetailSafariView(url: presentation.url)
                .ignoresSafeArea()
        }
    }

    private var subtitle: String? {
        if let presentation = viewModel.loadedPresentation {
            return presentation.sourceMetadata.feedTitle
        }
        return input.summary?.feedTitle
    }
}

private struct ArticleDetailBody: View {
    let state: ArticleDetailViewState
    let mutationMessage: ArticleDetailMutationMessage?
    let onDismissMessage: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let mutationMessage {
                FeedmanBannerView(message: mutationMessage.message, style: .warning) {
                    Button("閉じる", action: onDismissMessage)
                }
            }

            switch state {
            case .idle:
                FeedmanLoadingView("記事を準備しています", accessibilityLabel: "記事詳細を準備中")

            case let .loading(summary):
                if let summary {
                    ArticleDetailSummaryPreview(summary: summary)
                }
                FeedmanLoadingView("記事詳細を読み込んでいます", accessibilityLabel: "記事詳細を読み込み中")

            case let .loaded(presentation):
                ArticleDetailLoadedContent(presentation: presentation)

            case let .failed(message, isAuthRequired):
                FeedmanRecoverableErrorView(
                    title: isAuthRequired ? "再ログインが必要です" : "記事詳細を読み込めませんでした",
                    message: message,
                    usesDangerEmphasis: !isAuthRequired,
                    retryDescriptor: FeedmanRetryDescriptor(accessibilityLabel: "記事詳細の読み込みを再試行")
                ) {
                    Button("再試行", action: onRetry)
                }
            }
        }
    }
}

private struct ArticleDetailSummaryPreview: View {
    let summary: ArticleDetailSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let feedTitle = summary.feedTitle {
                ArticleSourceRow(
                    feedTitle: feedTitle,
                    faviconURL: summary.feedFaviconURL,
                    relativeDate: ArticleDetailPublishedDateFormatter.string(
                        from: summary.publishedAt,
                        isEstimated: summary.isDateEstimated
                    ),
                    size: .standard
                )
            }

            if let title = summary.title {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(FeedmanTheme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }

            if let preview = summary.summary?.trimmingCharacters(in: .whitespacesAndNewlines),
               !preview.isEmpty {
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(FeedmanTheme.mutedForeground)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
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
        .accessibilityElement(children: .contain)
    }
}

private struct ArticleDetailLoadedContent: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let presentation: ArticleDetailPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                ArticleSourceRow(
                    metadata: presentation.sourceMetadata,
                    size: .standard
                )

                Text(presentation.title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(FeedmanTheme.foreground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                metadataLine
            }

            Divider()
                .overlay(FeedmanTheme.border)

            VStack(alignment: .leading, spacing: 10) {
                Text("本文プレビュー")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FeedmanTheme.mutedForeground)

                Text(presentation.preview.text)
                    .font(.body)
                    .foregroundStyle(FeedmanTheme.foreground)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("本文プレビュー")
                    .accessibilityValue(presentation.preview.text)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var metadataLine: some View {
        if FeedmanAccessibilityLayout.usesStackedControls(for: dynamicTypeSize) {
            VStack(alignment: .leading, spacing: 8) {
                metadataControls
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .center, spacing: 8) {
                metadataControls

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var metadataControls: some View {
        ArticleHatebuCountControl(
            state: presentation.hatebuState,
            size: .standard
        )

        if let authorText = presentation.authorText {
            Label {
                Text(authorText)
                    .lineLimit(FeedmanAccessibilityLayout.usesStackedControls(for: dynamicTypeSize) ? 2 : 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .truncationMode(.tail)
            } icon: {
                Image(systemName: "person")
                    .accessibilityHidden(true)
            }
            .font(.caption)
            .foregroundStyle(FeedmanTheme.mutedForeground)
            .labelStyle(.titleAndIcon)
        }

        if presentation.isDateEstimated {
            Text("推定日時")
                .font(.caption.weight(.semibold))
                .foregroundStyle(FeedmanTheme.mutedForeground)
                .padding(.horizontal, 8)
                .frame(minHeight: 28)
                .background(FeedmanTheme.muted)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct ArticleDetailFooter: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let presentation: ArticleDetailPresentation?
    let summary: ArticleDetailSummary?
    let isStarUpdateInFlight: Bool
    let onOpenOriginal: () -> Void
    let onToggleStar: () -> Void

    var body: some View {
        if FeedmanAccessibilityLayout.usesStackedControls(for: dynamicTypeSize) {
            VStack(alignment: .trailing, spacing: 10) {
                openOriginalButton

                starControl
            }
        } else {
            HStack(spacing: 12) {
                openOriginalButton

                starControl
            }
        }
    }

    private var openOriginalButton: some View {
        Button(action: onOpenOriginal) {
            Label("元記事を開く", systemImage: "arrow.up.forward.square")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .accessibilityLabel("元記事を開く")
        .accessibilityHint(
            linkURL == nil
                ? "リンクを確認できない場合はエラーを表示します"
                : "アプリ内Safariで元記事を開きます"
        )
    }

    private var starControl: some View {
        ArticleStarControl(
            isStarred: isStarred,
            isEnabled: presentation != nil && !isStarUpdateInFlight,
            size: .standard,
            onToggle: onToggleStar
        )
        .accessibilityHint(isStarUpdateInFlight ? "スター状態を保存中です" : "")
    }

    private var linkURL: URL? {
        if let presentation {
            return presentation.linkURL
        }

        guard let link = summary?.link else {
            return nil
        }

        return ArticleDetailOriginalArticleRequest.validHTTPURL(from: link)
    }

    private var isStarred: Bool {
        presentation?.isStarred ?? summary?.isStarred ?? false
    }
}

#Preview {
    ArticleDetailSheet(
        input: ArticleDetailSheetInput(
            id: "item-1",
            summary: ArticleDetailSummary(
                id: "item-1",
                feedTitle: "Publickey",
                title: "Go の新しいイテレータが安定版に",
                summary: "range-over-func が GA となりました。",
                link: "https://example.com/articles/1",
                publishedAt: "2026-06-08T08:30:00Z",
                isStarred: false,
                hatebuCount: 142
            )
        ),
        repository: MockItemRepository(
            itemDetails: [
                "item-1": ItemDetail(
                    id: "item-1",
                    feedID: "publickey",
                    feedTitle: "Publickey",
                    feedFaviconURL: nil,
                    title: "Go の新しいイテレータが安定版に",
                    summary: "range-over-func が GA となりました。",
                    content: "<p>range-over-func が GA となり、独自コレクションのイテレートが書きやすくなりました。</p>",
                    link: "https://example.com/articles/1",
                    publishedAt: "2026-06-08T08:30:00Z",
                    isDateEstimated: false,
                    isRead: false,
                    isStarred: false,
                    hatebuCount: 142,
                    hatebuFetchedAt: "2026-06-08T08:35:00Z",
                    author: "Feedman"
                )
            ]
        ),
        accessToken: "preview-access-token",
        onDismiss: {}
    )
}
