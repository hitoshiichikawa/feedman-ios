import SwiftUI

struct KeywordSettingsRowPresentation: Equatable {
    let term: String
    let hitsText: String
    let enabledText: String
    let accessibilityLabel: String

    init(keyword: KeywordResponse) {
        self.term = keyword.term
        self.hitsText = "\(keyword.hits) 件"
        self.enabledText = keyword.enabled ? "有効" : "無効"
        self.accessibilityLabel = "\(keyword.term)、\(enabledText)、過去の一致数 \(keyword.hits) 件"
    }
}

struct KeywordSettingsSheet: View {
    @StateObject private var viewModel: KeywordSettingsViewModel
    @State private var didStartInitialLoad = false
    @State private var editingKeyword: KeywordResponse?
    @State private var editingTerm = ""

    private let onDismiss: () -> Void

    init(
        repository: any KeywordRepository,
        accessToken: String?,
        onDismiss: @escaping () -> Void,
        onAuthRequired: @escaping () -> Void = {}
    ) {
        _viewModel = StateObject(
            wrappedValue: KeywordSettingsViewModel(
                repository: repository,
                accessToken: accessToken,
                authRequiredHandler: onAuthRequired
            )
        )
        self.onDismiss = onDismiss
    }

    var body: some View {
        FeedmanSheetShell(
            title: "キーワード通知",
            subtitle: "記事タイトルに一致したキーワードを通知対象にします",
            onDismiss: onDismiss,
            primaryAction: {
                addButton
            }
        ) {
            VStack(alignment: .leading, spacing: 16) {
                inputSection
                messageSection
                contentSection
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(isBlockingDismiss)
        .task {
            guard !didStartInitialLoad else {
                return
            }
            didStartInitialLoad = true
            await viewModel.loadKeywords()
        }
        .alert("キーワードを編集", isPresented: editAlertBinding) {
            TextField("キーワード", text: $editingTerm)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Button("キャンセル", role: .cancel) {
                editingKeyword = nil
                editingTerm = ""
            }
            Button("保存") {
                guard let editingKeyword else {
                    return
                }
                Task {
                    let didUpdate = await viewModel.updateKeyword(id: editingKeyword.id, term: editingTerm)
                    if didUpdate {
                        self.editingKeyword = nil
                        self.editingTerm = ""
                    }
                }
            }
        } message: {
            Text("記事タイトルに含まれるキーワードを入力してください。")
        }
        .alert("キーワードを削除しますか？", isPresented: deleteAlertBinding) {
            Button("キャンセル", role: .cancel) {
                viewModel.cancelDeleteConfirmation()
            }
            Button("削除", role: .destructive) {
                Task {
                    await viewModel.confirmDeleteKeyword()
                }
            }
        } message: {
            Text("「\(viewModel.deleteConfirmation?.term ?? "")」を通知対象から削除します。")
        }
    }

    private var addButton: some View {
        Button {
            Task {
                await viewModel.createKeyword()
            }
        } label: {
            HStack(spacing: 8) {
                if viewModel.operation == .creating {
                    ProgressView()
                        .controlSize(.small)
                        .tint(FeedmanTheme.accentOn)
                        .frame(width: 18, height: 18)
                        .accessibilityHidden(true)
                }

                Label(viewModel.operation == .creating ? "追加中" : "追加", systemImage: "plus")
                    .labelStyle(.titleAndIcon)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minWidth: 72)
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(!viewModel.canCreate)
        .opacity(viewModel.canCreate ? 1 : 0.58)
        .accessibilityLabel(viewModel.operation == .creating ? "キーワードを追加中" : "キーワードを追加")
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("キーワード")
                .font(.caption.weight(.semibold))
                .foregroundStyle(FeedmanTheme.mutedForeground)

            HStack(spacing: 10) {
                Image(systemName: "text.magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FeedmanTheme.mutedForeground)
                    .accessibilityHidden(true)

                TextField("例: SwiftUI", text: $viewModel.draftTerm)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .disabled(viewModel.operation == .creating)
                    .onSubmit {
                        guard viewModel.canCreate else {
                            return
                        }
                        Task {
                            await viewModel.createKeyword()
                        }
                    }
                    .accessibilityLabel("通知キーワード")
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(FeedmanTheme.muted)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var messageSection: some View {
        if let message = viewModel.message {
            switch message {
            case .success(let text):
                FeedmanBannerView(message: text, style: .success)
            case .failure(let error):
                FeedmanBannerView(
                    message: "\(error.title)。\(error.message)",
                    style: bannerStyle(for: error.kind)
                )
            }
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        switch viewModel.contentState {
        case .idle, .loading:
            FeedmanLoadingView(
                "キーワードを読み込んでいます",
                accessibilityLabel: "キーワード通知設定を読み込み中"
            )
        case .empty:
            FeedmanEmptyStateView(
                systemImage: "bell.badge",
                title: "キーワードはありません",
                subtitle: "記事タイトルに含まれる語句を追加すると通知対象にできます。"
            )
        case .failed(let error):
            FeedmanRecoverableErrorView(
                title: error.title,
                message: error.message,
                usesDangerEmphasis: error.kind != .network
            ) {
                Button("再試行") {
                    Task {
                        await viewModel.retryInitialLoad()
                    }
                }
            }
        case .loaded(let keywords):
            VStack(spacing: 10) {
                ForEach(keywords, id: \.id) { keyword in
                    keywordRow(keyword)
                }
            }
        }
    }

    private func keywordRow(_ keyword: KeywordResponse) -> some View {
        let presentation = KeywordSettingsRowPresentation(keyword: keyword)
        let isUpdating = viewModel.operation == .updating(id: keyword.id)
        let isToggling = viewModel.operation == .toggling(id: keyword.id)
        let isDeleting = viewModel.operation == .deleting(id: keyword.id)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(presentation.term)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FeedmanTheme.foreground)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("一致数 \(presentation.hitsText)")
                        .font(.caption)
                        .foregroundStyle(FeedmanTheme.mutedForeground)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Toggle(
                    presentation.enabledText,
                    isOn: Binding(
                        get: { keyword.enabled },
                        set: { enabled in
                            Task {
                                await viewModel.setKeywordEnabled(id: keyword.id, enabled: enabled)
                            }
                        }
                    )
                )
                .labelsHidden()
                .disabled(isUpdating || isToggling || isDeleting)
                .accessibilityLabel("キーワード通知を\(keyword.enabled ? "無効" : "有効")にする")
                .accessibilityValue(presentation.enabledText)
            }

            HStack(spacing: 8) {
                Button {
                    editingKeyword = keyword
                    editingTerm = keyword.term
                } label: {
                    Label(isUpdating ? "保存中" : "編集", systemImage: "pencil")
                }
                .buttonStyle(.bordered)
                .disabled(isUpdating || isToggling || isDeleting)
                .accessibilityLabel(isUpdating ? "キーワードを保存中" : "キーワードを編集")

                Button(role: .destructive) {
                    viewModel.requestDeleteConfirmation(id: keyword.id)
                } label: {
                    Label(isDeleting ? "削除中" : "削除", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .disabled(isUpdating || isToggling || isDeleting)
                .accessibilityLabel(isDeleting ? "キーワードを削除中" : "キーワードを削除")

                if isUpdating || isToggling || isDeleting {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 22, height: 22)
                        .accessibilityLabel("キーワード操作中")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FeedmanTheme.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(FeedmanTheme.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private var editAlertBinding: Binding<Bool> {
        Binding(
            get: {
                editingKeyword != nil
            },
            set: { isPresented in
                if !isPresented {
                    editingKeyword = nil
                    editingTerm = ""
                }
            }
        )
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: {
                viewModel.deleteConfirmation != nil
            },
            set: { isPresented in
                if !isPresented {
                    viewModel.cancelDeleteConfirmation()
                }
            }
        )
    }

    private var isBlockingDismiss: Bool {
        switch viewModel.operation {
        case .deleting:
            return true
        case .loading, .creating, .updating, .toggling, .none:
            return false
        }
    }

    private func bannerStyle(for kind: KeywordSettingsErrorPresentation.Kind) -> FeedmanToast.Style {
        switch kind {
        case .duplicate, .rateLimit:
            return .warning
        case .emptyTerm, .authRequired, .network, .api, .generic:
            return .error
        }
    }
}

#Preview("Keyword Settings") {
    KeywordSettingsSheet(
        repository: MockKeywordRepository(),
        accessToken: "preview-access-token",
        onDismiss: {}
    )
}
