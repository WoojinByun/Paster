import Foundation
import Testing
@testable import PasterCore

struct ClipStoreQueryTests {
    let store: ClipStore
    let hour: TimeInterval = 3600

    init() throws {
        store = try Fixtures.makeStore()
    }

    @Test func unpinnedAreNewestFirst() throws {
        try Fixtures.save(Fixtures.textClip("old"), in: store, at: Fixtures.now)
        try Fixtures.save(Fixtures.textClip("new"), in: store, at: Fixtures.now.addingTimeInterval(hour))
        try Fixtures.save(Fixtures.textClip("old"), in: store, at: Fixtures.now.addingTimeInterval(2 * hour))
        let texts = try store.fetchUnpinned(settings: .default, now: Fixtures.now.addingTimeInterval(3 * hour)).map(\.plainText)
        #expect(texts == ["old", "new"])
    }

    @Test func expiredItemsAreHiddenBeforePurge() throws {
        var settings = RetentionSettings.default
        settings.text.period = .day
        try Fixtures.save(Fixtures.textClip("stale"), in: store, at: Fixtures.now.addingTimeInterval(-25 * hour))
        try Fixtures.save(Fixtures.textClip("fresh"), in: store, at: Fixtures.now.addingTimeInterval(-23 * hour))
        try Fixtures.save(Fixtures.imageClip(seed: 1), in: store, at: Fixtures.now.addingTimeInterval(-25 * hour))
        let items = try store.fetchUnpinned(settings: settings, now: Fixtures.now)
        #expect(items.map(\.kind) == [.text, .image])
        #expect(items.first?.plainText == "fresh")
    }

    @Test func disabledKindKeepsShowingUntilItsPeriodEnds() throws {
        var settings = RetentionSettings.default
        settings.text = KindRetention(isEnabled: false, period: .week)
        try Fixtures.save(Fixtures.textClip("kept"), in: store, at: Fixtures.now.addingTimeInterval(-6 * 24 * hour))
        #expect(try store.fetchUnpinned(settings: settings, now: Fixtures.now).count == 1)
    }

    @Test func pinnedAreExcludedFromUnpinnedAndOrderedByPinOrder() throws {
        let a = try Fixtures.save(Fixtures.textClip("a"), in: store)
        let b = try Fixtures.save(Fixtures.textClip("b"), in: store)
        try Fixtures.save(Fixtures.textClip("c"), in: store)
        try store.dbQueue.write { db in
            try db.execute(sql: "UPDATE clip_items SET pinned_at = ?, pin_order = 1 WHERE id = ?", arguments: [Fixtures.now, a])
            try db.execute(sql: "UPDATE clip_items SET pinned_at = ?, pin_order = 0 WHERE id = ?", arguments: [Fixtures.now, b])
        }
        #expect(try store.fetchUnpinned(settings: .default, now: Fixtures.now).map(\.plainText) == ["c"])
        #expect(try store.fetchPinned().map(\.plainText) == ["b", "a"])
    }

    @Test func pinnedNeverExpireInQueries() throws {
        let id = try Fixtures.save(Fixtures.textClip("ancient"), in: store, at: Fixtures.now.addingTimeInterval(-365 * 24 * hour))
        try store.dbQueue.write { db in
            try db.execute(sql: "UPDATE clip_items SET pinned_at = ?, pin_order = 0 WHERE id = ?", arguments: [Fixtures.now, id])
        }
        #expect(try store.fetchPinned().count == 1)
    }

    @Test func limitCapsResults() throws {
        for index in 0..<5 {
            try Fixtures.save(Fixtures.textClip("item \(index)"), in: store, at: Fixtures.now.addingTimeInterval(Double(index)))
        }
        #expect(try store.fetchUnpinned(settings: .default, now: Fixtures.now.addingTimeInterval(10), limit: 3).count == 3)
    }
}
