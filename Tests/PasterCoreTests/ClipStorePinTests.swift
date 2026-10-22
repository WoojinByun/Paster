import Foundation
import Testing
@testable import PasterCore

struct ClipStorePinTests {
    let store: ClipStore
    let hour: TimeInterval = 3600

    init() throws {
        store = try Fixtures.makeStore()
    }

    func pinnedTexts() throws -> [String] {
        try store.fetchPinned().map(\.plainText)
    }

    @Test func pinMovesItemToPinnedColumnAtTheEnd() throws {
        let a = try Fixtures.save(Fixtures.textClip("a"), in: store)
        let b = try Fixtures.save(Fixtures.textClip("b"), in: store)
        try store.pin(id: b, now: Fixtures.now)
        try store.pin(id: a, now: Fixtures.now)
        #expect(try pinnedTexts() == ["b", "a"])
        #expect(try store.fetchUnpinned(settings: .default, now: Fixtures.now).isEmpty)
        #expect(try store.item(id: a)?.pinnedAt == Fixtures.now)
    }

    @Test func pinningTwiceKeepsOrder() throws {
        let a = try Fixtures.save(Fixtures.textClip("a"), in: store)
        let b = try Fixtures.save(Fixtures.textClip("b"), in: store)
        try store.pin(id: a, now: Fixtures.now)
        try store.pin(id: b, now: Fixtures.now)
        try store.pin(id: a, now: Fixtures.now.addingTimeInterval(5))
        #expect(try pinnedTexts() == ["a", "b"])
        #expect(try store.item(id: a)?.pinnedAt == Fixtures.now)
    }

    @Test func unpinResetsLastCopiedAtSoItDoesNotExpireImmediately() throws {
        var settings = RetentionSettings.default
        settings.text.period = .day
        let old = Fixtures.now.addingTimeInterval(-30 * 24 * hour)
        let id = try Fixtures.save(Fixtures.textClip("long pinned"), in: store, at: old)
        try store.pin(id: id, now: old)
        try store.unpin(id: id, now: Fixtures.now)
        let item = try #require(try store.item(id: id))
        #expect(item.pinnedAt == nil)
        #expect(item.pinOrder == nil)
        #expect(item.lastCopiedAt == Fixtures.now)
        #expect(try store.fetchUnpinned(settings: settings, now: Fixtures.now).map(\.id) == [id])
    }

    @Test func unpinOnUnpinnedItemDoesNothing() throws {
        let id = try Fixtures.save(Fixtures.textClip("x"), in: store)
        try store.unpin(id: id, now: Fixtures.now.addingTimeInterval(99))
        #expect(try store.item(id: id)?.lastCopiedAt == Fixtures.now)
    }

    @Test func movePinnedSwapsNeighbours() throws {
        let ids = try ["a", "b", "c"].map { try Fixtures.save(Fixtures.textClip($0), in: store) }
        for id in ids { try store.pin(id: id, now: Fixtures.now) }

        #expect(try store.movePinned(id: ids[2], direction: .up))
        #expect(try pinnedTexts() == ["a", "c", "b"])
        #expect(try store.movePinned(id: ids[0], direction: .down))
        #expect(try pinnedTexts() == ["c", "a", "b"])
    }

    @Test func movePinnedStopsAtEdges() throws {
        let ids = try ["a", "b"].map { try Fixtures.save(Fixtures.textClip($0), in: store) }
        for id in ids { try store.pin(id: id, now: Fixtures.now) }
        #expect(try store.movePinned(id: ids[0], direction: .up) == false)
        #expect(try store.movePinned(id: ids[1], direction: .down) == false)
        #expect(try pinnedTexts() == ["a", "b"])
    }

    @Test func movePinnedIgnoresUnpinned() throws {
        let id = try Fixtures.save(Fixtures.textClip("x"), in: store)
        #expect(try store.movePinned(id: id, direction: .up) == false)
    }
}
