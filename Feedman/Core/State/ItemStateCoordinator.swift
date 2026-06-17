import Combine
import Foundation

enum ItemStateField: Hashable {
    case read
    case starred
}

struct ItemStateSnapshot: Equatable {
    let isRead: Bool
    let isStarred: Bool
    let isReadPending: Bool
    let isStarredPending: Bool
}

struct ItemStateMutationToken: Equatable {
    let id: UUID
    let itemID: String
    let fields: Set<ItemStateField>

    init(
        id: UUID = UUID(),
        itemID: String,
        fields: Set<ItemStateField>
    ) {
        self.id = id
        self.itemID = itemID
        self.fields = fields
    }
}

@MainActor
final class ItemStateCoordinator: ObservableObject {
    private struct PendingFieldState: Equatable {
        let tokenID: UUID
        let previousValue: Bool
        let optimisticValue: Bool
    }

    private struct ItemStateEntry: Equatable {
        var confirmedRead: Bool?
        var confirmedStarred: Bool?
        var pendingRead: PendingFieldState?
        var pendingStarred: PendingFieldState?
    }

    private var entries: [String: ItemStateEntry] = [:]

    func effectiveState(
        itemID: String,
        baseRead: Bool,
        baseStarred: Bool
    ) -> ItemStateSnapshot {
        let entry = entries[itemID]
        return ItemStateSnapshot(
            isRead: entry?.pendingRead?.optimisticValue ?? entry?.confirmedRead ?? baseRead,
            isStarred: entry?.pendingStarred?.optimisticValue ?? entry?.confirmedStarred ?? baseStarred,
            isReadPending: entry?.pendingRead != nil,
            isStarredPending: entry?.pendingStarred != nil
        )
    }

    func isPending(itemID: String, field: ItemStateField) -> Bool {
        let entry = entries[itemID]
        switch field {
        case .read:
            return entry?.pendingRead != nil
        case .starred:
            return entry?.pendingStarred != nil
        }
    }

    func beginMutation(
        itemID: String,
        baseRead: Bool,
        baseStarred: Bool,
        isRead targetRead: Bool? = nil,
        isStarred targetStarred: Bool? = nil
    ) -> ItemStateMutationToken? {
        guard targetRead != nil || targetStarred != nil else {
            return nil
        }

        let current = effectiveState(
            itemID: itemID,
            baseRead: baseRead,
            baseStarred: baseStarred
        )

        if targetRead != nil, current.isReadPending {
            return nil
        }
        if targetStarred != nil, current.isStarredPending {
            return nil
        }

        var fields = Set<ItemStateField>()
        if targetRead != nil {
            fields.insert(.read)
        }
        if targetStarred != nil {
            fields.insert(.starred)
        }

        let token = ItemStateMutationToken(itemID: itemID, fields: fields)
        objectWillChange.send()

        var entry = entries[itemID] ?? ItemStateEntry()
        if let targetRead {
            entry.pendingRead = PendingFieldState(
                tokenID: token.id,
                previousValue: current.isRead,
                optimisticValue: targetRead
            )
        }
        if let targetStarred {
            entry.pendingStarred = PendingFieldState(
                tokenID: token.id,
                previousValue: current.isStarred,
                optimisticValue: targetStarred
            )
        }
        entries[itemID] = entry
        return token
    }

    func commitMutation(_ token: ItemStateMutationToken) {
        guard var entry = entries[token.itemID] else {
            return
        }

        var didChange = false
        if token.fields.contains(.read),
           entry.pendingRead?.tokenID == token.id,
           let pending = entry.pendingRead {
            entry.confirmedRead = pending.optimisticValue
            entry.pendingRead = nil
            didChange = true
        }

        if token.fields.contains(.starred),
           entry.pendingStarred?.tokenID == token.id,
           let pending = entry.pendingStarred {
            entry.confirmedStarred = pending.optimisticValue
            entry.pendingStarred = nil
            didChange = true
        }

        guard didChange else {
            return
        }

        objectWillChange.send()
        entries[token.itemID] = pruned(entry)
    }

    func rollbackMutation(_ token: ItemStateMutationToken) {
        guard var entry = entries[token.itemID] else {
            return
        }

        var didChange = false
        if token.fields.contains(.read),
           entry.pendingRead?.tokenID == token.id,
           let pending = entry.pendingRead {
            entry.confirmedRead = pending.previousValue
            entry.pendingRead = nil
            didChange = true
        }

        if token.fields.contains(.starred),
           entry.pendingStarred?.tokenID == token.id,
           let pending = entry.pendingStarred {
            entry.confirmedStarred = pending.previousValue
            entry.pendingStarred = nil
            didChange = true
        }

        guard didChange else {
            return
        }

        objectWillChange.send()
        entries[token.itemID] = pruned(entry)
    }

    func confirmStateChange(_ change: ItemStateChange) {
        var entry = entries[change.itemID] ?? ItemStateEntry()
        if let isRead = change.isRead {
            entry.confirmedRead = isRead
            entry.pendingRead = nil
        }
        if let isStarred = change.isStarred {
            entry.confirmedStarred = isStarred
            entry.pendingStarred = nil
        }

        objectWillChange.send()
        entries[change.itemID] = pruned(entry)
    }

    private func pruned(_ entry: ItemStateEntry) -> ItemStateEntry? {
        if entry.confirmedRead == nil,
           entry.confirmedStarred == nil,
           entry.pendingRead == nil,
           entry.pendingStarred == nil {
            return nil
        }
        return entry
    }
}

extension ItemStateCoordinator {
    func effectiveSummary(_ item: ItemSummary) -> ItemSummary {
        let snapshot = effectiveState(
            itemID: item.id,
            baseRead: item.isRead,
            baseStarred: item.isStarred
        )
        return item.withReadStarState(
            isRead: snapshot.isRead,
            isStarred: snapshot.isStarred
        )
    }

    func effectiveDetail(_ detail: ItemDetail) -> ItemDetail {
        let snapshot = effectiveState(
            itemID: detail.id,
            baseRead: detail.isRead,
            baseStarred: detail.isStarred
        )
        return detail.withReadStarState(
            isRead: snapshot.isRead,
            isStarred: snapshot.isStarred
        )
    }

    func effectiveSearchHit(_ hit: ItemSearchHit) -> ItemSearchHit {
        let snapshot = effectiveState(
            itemID: hit.id,
            baseRead: hit.isRead ?? false,
            baseStarred: hit.isStarred ?? false
        )
        return hit.withReadStarState(
            isRead: snapshot.isRead,
            isStarred: snapshot.isStarred
        )
    }
}

extension ItemSummary {
    func withReadStarState(isRead: Bool, isStarred: Bool) -> ItemSummary {
        ItemSummary(
            id: id,
            feedID: feedID,
            feedTitle: feedTitle,
            feedFaviconURL: feedFaviconURL,
            title: title,
            summary: summary,
            link: link,
            publishedAt: publishedAt,
            isDateEstimated: isDateEstimated,
            isRead: isRead,
            isStarred: isStarred,
            hatebuCount: hatebuCount,
            hatebuFetchedAt: hatebuFetchedAt,
            author: author
        )
    }
}

extension ItemDetail {
    func withReadStarState(isRead: Bool, isStarred: Bool) -> ItemDetail {
        ItemDetail(
            id: id,
            feedID: feedID,
            feedTitle: feedTitle,
            feedFaviconURL: feedFaviconURL,
            title: title,
            summary: summary,
            content: content,
            link: link,
            publishedAt: publishedAt,
            isDateEstimated: isDateEstimated,
            isRead: isRead,
            isStarred: isStarred,
            hatebuCount: hatebuCount,
            hatebuFetchedAt: hatebuFetchedAt,
            author: author
        )
    }
}

extension ItemSearchHit {
    func withReadStarState(isRead: Bool, isStarred: Bool) -> ItemSearchHit {
        ItemSearchHit(
            id: id,
            feedID: feedID,
            feedTitle: feedTitle,
            faviconURL: faviconURL,
            title: title,
            summary: summary,
            link: link,
            publishedAt: publishedAt,
            isDateEstimated: isDateEstimated,
            isRead: isRead,
            isStarred: isStarred,
            hatebuCount: hatebuCount,
            author: author
        )
    }
}
