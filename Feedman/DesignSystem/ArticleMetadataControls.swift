import SwiftUI

enum ArticleMetadataControlSize: Equatable {
    case compact
    case standard
    case timeline

    var touchTarget: CGFloat {
        44
    }

    var iconSize: CGFloat {
        switch self {
        case .compact:
            return 15
        case .standard:
            return 17
        case .timeline:
            return 18
        }
    }

    var faviconSize: CGFloat {
        switch self {
        case .compact:
            return 20
        case .standard:
            return 24
        case .timeline:
            return 26
        }
    }

    var sourceRowHeight: CGFloat {
        max(faviconSize, 24)
    }

    var hatebuMinWidth: CGFloat {
        switch self {
        case .compact:
            return 38
        case .standard, .timeline:
            return 44
        }
    }

    var controlFont: Font {
        switch self {
        case .compact:
            return .caption2.weight(.semibold)
        case .standard, .timeline:
            return .caption.weight(.semibold)
        }
    }

    var iconFont: Font {
        .system(size: iconSize, weight: .semibold)
    }
}

enum ArticleMetadataColorRole: Equatable {
    case foreground
    case mutedForeground
    case accent
    case star

    var color: Color {
        switch self {
        case .foreground:
            return FeedmanTheme.foreground
        case .mutedForeground:
            return FeedmanTheme.mutedForeground
        case .accent:
            return FeedmanTheme.accent
        case .star:
            return FeedmanTheme.star
        }
    }
}

struct ArticleStarControlDescriptor: Equatable {
    let isStarred: Bool
    let isEnabled: Bool
    let size: ArticleMetadataControlSize

    init(
        isStarred: Bool,
        isEnabled: Bool = true,
        size: ArticleMetadataControlSize = .standard
    ) {
        self.isStarred = isStarred
        self.isEnabled = isEnabled
        self.size = size
    }

    var systemImageName: String {
        isStarred ? "star.fill" : "star"
    }

    var colorRole: ArticleMetadataColorRole {
        isStarred ? .star : .mutedForeground
    }

    var accessibilityLabel: String {
        isStarred ? "スターを解除" : "スターを付ける"
    }

    var accessibilityValue: String {
        isStarred ? "オン" : "オフ"
    }

    var isSelected: Bool {
        isStarred
    }

    var accessibilityHint: String? {
        isEnabled ? nil : "操作できません"
    }

    func activate(_ action: () -> Void) {
        guard isEnabled else {
            return
        }

        action()
    }
}

struct ArticleStarControl: View {
    private let descriptor: ArticleStarControlDescriptor
    private let onToggle: () -> Void

    init(
        isStarred: Bool,
        isEnabled: Bool = true,
        size: ArticleMetadataControlSize = .standard,
        onToggle: @escaping () -> Void
    ) {
        descriptor = ArticleStarControlDescriptor(
            isStarred: isStarred,
            isEnabled: isEnabled,
            size: size
        )
        self.onToggle = onToggle
    }

    var body: some View {
        Button {
            descriptor.activate(onToggle)
        } label: {
            Image(systemName: descriptor.systemImageName)
                .font(descriptor.size.iconFont)
                .foregroundStyle(descriptor.colorRole.color)
                .frame(
                    width: descriptor.size.touchTarget,
                    height: descriptor.size.touchTarget
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!descriptor.isEnabled)
        .accessibilityLabel(Text(descriptor.accessibilityLabel))
        .accessibilityValue(Text(descriptor.accessibilityValue))
        .accessibilityHint(Text(descriptor.accessibilityHint ?? ""))
        .accessibilityAddTraits(descriptor.isSelected ? [.isSelected] : [])
    }
}

enum ArticleHatebuCountState: Equatable {
    case available(Int)
    case unavailable

    init(count: Int?, isFetched: Bool) {
        if isFetched, let count {
            self = .available(max(count, 0))
        } else {
            self = .unavailable
        }
    }
}

struct ArticleHatebuCountDescriptor: Equatable {
    let state: ArticleHatebuCountState
    let size: ArticleMetadataControlSize

    init(
        state: ArticleHatebuCountState,
        size: ArticleMetadataControlSize = .standard
    ) {
        self.state = state
        self.size = size
    }

    init(
        count: Int?,
        isFetched: Bool,
        size: ArticleMetadataControlSize = .standard
    ) {
        self.init(
            state: ArticleHatebuCountState(count: count, isFetched: isFetched),
            size: size
        )
    }

    var displayText: String {
        switch state {
        case .available(let count):
            return "\(count)"
        case .unavailable:
            return "-"
        }
    }

    var isHot: Bool {
        guard case .available(let count) = state else {
            return false
        }

        return count >= 100
    }

    var colorRole: ArticleMetadataColorRole {
        isHot ? .accent : .mutedForeground
    }

    var accessibilityLabel: String {
        switch state {
        case .available(let count):
            return "はてなブックマーク \(count) 件"
        case .unavailable:
            return "はてなブックマーク未取得"
        }
    }
}

struct ArticleHatebuCountControl: View {
    private let descriptor: ArticleHatebuCountDescriptor

    init(
        state: ArticleHatebuCountState,
        size: ArticleMetadataControlSize = .standard
    ) {
        descriptor = ArticleHatebuCountDescriptor(state: state, size: size)
    }

    init(
        count: Int?,
        isFetched: Bool,
        size: ArticleMetadataControlSize = .standard
    ) {
        descriptor = ArticleHatebuCountDescriptor(
            count: count,
            isFetched: isFetched,
            size: size
        )
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(descriptor.displayText)
                .monospacedDigit()

            Text("B!")
        }
        .font(descriptor.size.controlFont)
        .foregroundStyle(descriptor.colorRole.color)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(
            minWidth: descriptor.size.hatebuMinWidth,
            minHeight: descriptor.size.touchTarget,
            alignment: .leading
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(descriptor.accessibilityLabel))
    }
}

struct ArticleSourceMetadata: Equatable {
    let feedTitle: String
    let faviconURL: String?
    let relativeDate: String?

    init(
        feedTitle: String,
        faviconURL: String? = nil,
        relativeDate: String? = nil
    ) {
        self.feedTitle = feedTitle
        self.faviconURL = faviconURL
        self.relativeDate = relativeDate
    }
}

struct ArticleSourceRow: View {
    private let metadata: ArticleSourceMetadata?
    private let size: ArticleMetadataControlSize

    init(
        metadata: ArticleSourceMetadata?,
        size: ArticleMetadataControlSize = .standard
    ) {
        self.metadata = metadata
        self.size = size
    }

    init(
        feedTitle: String,
        faviconURL: String? = nil,
        relativeDate: String? = nil,
        size: ArticleMetadataControlSize = .standard
    ) {
        metadata = ArticleSourceMetadata(
            feedTitle: feedTitle,
            faviconURL: faviconURL,
            relativeDate: relativeDate
        )
        self.size = size
    }

    var body: some View {
        if let metadata {
            HStack(spacing: 8) {
                FeedmanFaviconView(
                    faviconURL: metadata.faviconURL,
                    displayName: metadata.feedTitle,
                    size: size.faviconSize,
                    cornerRadius: 6
                )
                .accessibilityHidden(true)

                Text(metadata.feedTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(FeedmanTheme.mutedForeground)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)

                if let relativeDate = metadata.relativeDate,
                   !relativeDate.isEmpty {
                    Text(relativeDate)
                        .font(.caption)
                        .foregroundStyle(FeedmanTheme.mutedForeground)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .frame(minHeight: size.sourceRowHeight)
            .accessibilityElement(children: .combine)
        }
    }
}

enum ArticleUnavailableControlBehavior: Equatable {
    case disabled
    case hidden
}

struct ArticleOpenLinkControlDescriptor: Equatable {
    let isOpenable: Bool
    let unavailableBehavior: ArticleUnavailableControlBehavior
    let size: ArticleMetadataControlSize

    init(
        isOpenable: Bool,
        unavailableBehavior: ArticleUnavailableControlBehavior = .disabled,
        size: ArticleMetadataControlSize = .standard
    ) {
        self.isOpenable = isOpenable
        self.unavailableBehavior = unavailableBehavior
        self.size = size
    }

    var isHidden: Bool {
        !isOpenable && unavailableBehavior == .hidden
    }

    var isEnabled: Bool {
        isOpenable
    }

    var systemImageName: String {
        "arrow.up.forward.square"
    }

    var colorRole: ArticleMetadataColorRole {
        isEnabled ? .mutedForeground : .mutedForeground
    }

    var accessibilityLabel: String {
        "元記事をブラウザで開く"
    }

    var accessibilityHint: String? {
        isEnabled ? nil : "リンクを開けません"
    }

    func activate<Value>(value: Value?, action: (Value) -> Void) {
        guard isEnabled, !isHidden, let value else {
            return
        }

        action(value)
    }
}

struct ArticleOpenLinkControl<Value>: View {
    private let value: Value?
    private let descriptor: ArticleOpenLinkControlDescriptor
    private let onOpen: (Value) -> Void

    init(
        value: Value?,
        unavailableBehavior: ArticleUnavailableControlBehavior = .disabled,
        size: ArticleMetadataControlSize = .standard,
        onOpen: @escaping (Value) -> Void
    ) {
        self.value = value
        descriptor = ArticleOpenLinkControlDescriptor(
            isOpenable: value != nil,
            unavailableBehavior: unavailableBehavior,
            size: size
        )
        self.onOpen = onOpen
    }

    var body: some View {
        if !descriptor.isHidden {
            Button {
                descriptor.activate(value: value, action: onOpen)
            } label: {
                Image(systemName: descriptor.systemImageName)
                    .font(descriptor.size.iconFont)
                    .foregroundStyle(descriptor.colorRole.color)
                    .frame(
                        width: descriptor.size.touchTarget,
                        height: descriptor.size.touchTarget
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!descriptor.isEnabled)
            .accessibilityLabel(Text(descriptor.accessibilityLabel))
            .accessibilityHint(Text(descriptor.accessibilityHint ?? ""))
        }
    }
}
