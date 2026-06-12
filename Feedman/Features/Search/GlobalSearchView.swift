import SwiftUI

struct GlobalSearchView: View {
    @StateObject private var viewModel: GlobalSearchViewModel
    @FocusState private var isSearchFieldFocused: Bool

    private let onSelectItem: (String) -> Void
    private let onOpenLink: (URL) -> Void

    init(
        repository: any SearchRepository,
        onSelectItem: @escaping (String) -> Void,
        onOpenLink: @escaping (URL) -> Void,
        onAuthRequired: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(
            wrappedValue: GlobalSearchViewModel(
                repository: repository,
                onAuthRequired: onAuthRequired
            )
        )
        self.onSelectItem = onSelectItem
        self.onOpenLink = onOpenLink
    }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader

            Divider()
                .overlay(FeedmanTheme.border)

            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FeedmanTheme.background)
        .task {
            isSearchFieldFocused = true
        }
    }

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("購読フィードを横断検索")
                .font(.caption.weight(.semibold))
                .foregroundStyle(FeedmanTheme.mutedForeground)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FeedmanTheme.mutedForeground)
                    .accessibilityHidden(true)

                TextField("キーワード", text: $viewModel.query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isSearchFieldFocused)
                    .onSubmit {
                        Task {
                            await viewModel.submitSearch()
                        }
                    }

                if !viewModel.query.isEmpty {
                    Button {
                        viewModel.clearQuery()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(FeedmanTheme.mutedForeground)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("検索語をクリア")
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 46)
            .background(FeedmanTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(FeedmanTheme.border, lineWidth: 1)
            }
        }
        .padding(16)
        .background(FeedmanTheme.background)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .suggestions:
            suggestionsContent
        case let .loading(query):
            ScrollView {
                FeedmanLoadingView(
                    "「\(query)」を検索中",
                    accessibilityLabel: "検索中"
                )
                .padding(16)
            }
        case let .results(_, hits):
            resultList(hits)
        case let .empty(query):
            ScrollView {
                FeedmanEmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "「\(query)」に一致する記事はありません",
                    subtitle: "別のキーワードでお試しください。"
                )
                .padding(16)
            }
        case let .failed(_, message, isAuthRequired):
            ScrollView {
                FeedmanRecoverableErrorView(
                    title: isAuthRequired ? "再ログインが必要です" : "検索できませんでした",
                    message: message,
                    usesDangerEmphasis: !isAuthRequired
                ) {
                    Button("再試行") {
                        Task {
                            await viewModel.retry()
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    private var suggestionsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                FeedmanEmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "検索語を入力してください",
                    subtitle: nil
                )

                FlowSuggestionChips(
                    suggestions: GlobalSearchViewModel.suggestions,
                    onSelect: { suggestion in
                        Task {
                            await viewModel.submitSuggestion(suggestion)
                        }
                    }
                )
            }
            .padding(16)
        }
    }

    private func resultList(_ hits: [ItemSearchHit]) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(hits, id: \.id) { hit in
                    SearchResultCard(
                        descriptor: SearchResultRowDescriptor(hit: hit),
                        onSelectItem: onSelectItem,
                        onOpenLink: onOpenLink
                    )
                }
            }
            .padding(16)
        }
    }
}

private struct FlowSuggestionChips: View {
    let suggestions: [String]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("候補")
                .font(.caption.weight(.semibold))
                .foregroundStyle(FeedmanTheme.mutedForeground)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 92), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        onSelect(suggestion)
                    } label: {
                        Text(suggestion)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(FeedmanTheme.accent)
                    .background(FeedmanTheme.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityLabel("候補 \(suggestion)")
                }
            }
        }
    }
}

private struct SearchResultCard: View {
    let descriptor: SearchResultRowDescriptor
    let onSelectItem: (String) -> Void
    let onOpenLink: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ArticleSourceRow(
                metadata: descriptor.sourceMetadata,
                size: .compact
            )

            Text(descriptor.title)
                .font(.headline)
                .foregroundStyle(descriptor.isRead ? FeedmanTheme.mutedForeground : FeedmanTheme.foreground)
                .fixedSize(horizontal: false, vertical: true)

            if let summary = descriptor.summary {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(FeedmanTheme.mutedForeground)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 4) {
                ArticleHatebuCountControl(
                    state: descriptor.hatebuState,
                    size: .compact
                )

                Spacer(minLength: 8)

                ArticleStarControl(
                    isStarred: descriptor.isStarred,
                    isEnabled: descriptor.isStarMutationEnabled,
                    size: .compact,
                    onToggle: {}
                )

                ArticleOpenLinkControl(
                    value: descriptor.linkURL,
                    size: .compact,
                    onOpen: onOpenLink
                )
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FeedmanTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(FeedmanTheme.border, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            descriptor.select(onSelectItem)
        }
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    GlobalSearchView(
        repository: MockSearchRepository(),
        onSelectItem: { _ in },
        onOpenLink: { _ in }
    )
}
