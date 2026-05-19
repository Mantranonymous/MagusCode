import XCTest
@testable import MagusCore

final class StateDiffTests: XCTestCase {

    private func snapshot(
        item: Item? = nil,
        history: [MageHistoryEntry] = [],
        sink: Int? = nil,
        jobLevel: Int? = nil
    ) -> GameStateSnapshot {
        GameStateSnapshot(
            timestamp: Date(),
            item: item,
            history: history,
            sink: sink.map { Sink(percent: $0) },
            jobLevel: jobLevel
        )
    }

    func testNoChanges() {
        let s1 = snapshot()
        let s2 = snapshot()
        let diff = StateDiff(from: s1, to: s2)
        XCTAssertFalse(diff.hasChanges)
    }

    func testCombineLanded() {
        let s1 = snapshot(history: [])
        let newEntry = MageHistoryEntry(result: .success, kind: .raRune, delta: 1)
        let s2 = snapshot(history: [newEntry])
        let diff = StateDiff(from: s1, to: s2)
        XCTAssertTrue(diff.hasChanges)
        XCTAssertNotNil(diff.combineLanded)
        XCTAssertEqual(diff.combineLanded?.count, 1)
    }

    func testStatChanged() {
        let kind = StatKind(characteristicId: 11)
        let item1 = Item(name: "X", stats: [Stat(kind: kind, value: 100, minValue: 50, maxValue: 200)])
        let item2 = Item(id: item1.id, name: "X", stats: [Stat(kind: kind, value: 101, minValue: 50, maxValue: 200)])
        let diff = StateDiff(from: snapshot(item: item1), to: snapshot(item: item2))

        let statChanges = diff.changes.compactMap { change -> (Int, Int)? in
            if case .statChanged(_, let old, let new) = change { return (old, new) }
            return nil
        }
        XCTAssertEqual(statChanges.count, 1)
        XCTAssertEqual(statChanges.first?.0, 100)
        XCTAssertEqual(statChanges.first?.1, 101)
    }

    func testSinkChanged() {
        let s1 = snapshot(sink: 50)
        let s2 = snapshot(sink: 87)
        let diff = StateDiff(from: s1, to: s2)
        let sinkChange = diff.changes.first { if case .sinkChanged = $0 { return true } else { return false } }
        XCTAssertNotNil(sinkChange)
    }

    func testJobLeveledUp() {
        let s1 = snapshot(jobLevel: 158)
        let s2 = snapshot(jobLevel: 159)
        let diff = StateDiff(from: s1, to: s2)
        let levelChange = diff.changes.first { if case .jobLeveledUp = $0 { return true } else { return false } }
        XCTAssertNotNil(levelChange)
    }

    func testJobLevelDownNotDetected() {
        // Niveau descend = pas de levelUp détecté (probable OCR error)
        let s1 = snapshot(jobLevel: 159)
        let s2 = snapshot(jobLevel: 158)
        let diff = StateDiff(from: s1, to: s2)
        let levelChange = diff.changes.first { if case .jobLeveledUp = $0 { return true } else { return false } }
        XCTAssertNil(levelChange)
    }
}
