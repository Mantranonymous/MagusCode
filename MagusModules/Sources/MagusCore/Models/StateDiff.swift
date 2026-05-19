import Foundation

/// Différences entre deux GameStateSnapshot consécutifs.
/// Permet de détecter qu'un combine vient de "landed" et d'extraire ses effets.
public struct StateDiff: Sendable, Hashable {

    public enum Change: Sendable, Hashable {
        case itemSwapped(from: Item?, to: Item?)
        case combineLanded(newEntries: [MageHistoryEntry])
        case statChanged(kind: StatKind, oldValue: Int, newValue: Int)
        case sinkChanged(old: Int, new: Int)
        case jobLeveledUp(from: Int, to: Int)
    }

    public let changes: [Change]
    public let from: GameStateSnapshot
    public let to: GameStateSnapshot

    public init(from: GameStateSnapshot, to: GameStateSnapshot) {
        self.from = from
        self.to = to
        self.changes = StateDiff.compute(from: from, to: to)
    }

    public var hasChanges: Bool { !changes.isEmpty }

    public var combineLanded: [MageHistoryEntry]? {
        for change in changes {
            if case .combineLanded(let entries) = change { return entries }
        }
        return nil
    }

    private static func compute(from: GameStateSnapshot, to: GameStateSnapshot) -> [Change] {
        var changes: [Change] = []

        // Item swap
        if from.item?.referenceItemId != to.item?.referenceItemId
            || from.item?.name != to.item?.name {
            changes.append(.itemSwapped(from: from.item, to: to.item))
        }

        // History : nouvelles entrées en fin de liste
        if to.history.count > from.history.count {
            let newOnes = Array(to.history[from.history.count..<to.history.count])
            if !newOnes.isEmpty {
                changes.append(.combineLanded(newEntries: newOnes))
            }
        }

        // Stats changées (sur le même item)
        if let fromItem = from.item, let toItem = to.item,
           fromItem.referenceItemId == toItem.referenceItemId {
            for newStat in toItem.stats {
                if let oldStat = fromItem.stat(matching: newStat.kind),
                   oldStat.value != newStat.value {
                    changes.append(.statChanged(
                        kind: newStat.kind,
                        oldValue: oldStat.value,
                        newValue: newStat.value
                    ))
                }
            }
        }

        // Sink
        if let oldS = from.sink?.percent, let newS = to.sink?.percent, oldS != newS {
            changes.append(.sinkChanged(old: oldS, new: newS))
        }

        // Job level
        if let oldL = from.jobLevel, let newL = to.jobLevel, newL > oldL {
            changes.append(.jobLeveledUp(from: oldL, to: newL))
        }

        return changes
    }
}
