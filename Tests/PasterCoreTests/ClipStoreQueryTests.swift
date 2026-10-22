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
        try Fixtures.save(Fixtures.textClip("stale unpinned"), in: store, at: Fixtures.now.addingTimeInterval(-365 * 24 * hour))
        #expect(try store.fetchPinned().count == 1)
        #expect(try store.fetchUnpinned(settings: .default, now: Fixtures.now).isEmpty)
    }

    @Test func limitCapsResults() throws {
        for index in 0..<5 {
            try Fixtures.save(Fixtures.textClip("item \(index)"), in: store, at: Fixtures.now.addingTimeInterval(Double(index)))
        }
        #expect(try store.fetchUnpinned(settings: .default, now: Fixtures.now.addingTimeInterval(10), limit: 3).count == 3)
    }

    // MARK: 목록 투영

    private func richClip(_ text: String) -> CapturedClip {
        var clip = Fixtures.textClip(text)
        clip.rtf = Data("{\\rtf1 \(text)}".utf8)
        clip.html = Data("<b>\(text)</b>".utf8)
        return clip
    }

    @Test func listRowsLeaveOutRichDataAndCapText() throws {
        let long = "첫 줄\n" + String(repeating: "가", count: ClipStore.listTextLimit * 2)
        let unpinnedID = try Fixtures.save(richClip(long), in: store)
        let pinnedID = try Fixtures.save(richClip("pinned " + long), in: store)
        try store.pin(id: pinnedID, now: Fixtures.now)

        let rows = try store.fetchUnpinned(settings: .default, now: Fixtures.now) + store.fetchPinned()
        #expect(rows.map(\.id) == [unpinnedID, pinnedID])
        for row in rows {
            #expect(row.rtf == nil)
            #expect(row.html == nil)
            #expect(row.plainText.count == ClipStore.listTextLimit)
        }
        #expect(rows[0].title == "첫 줄")
        #expect(rows[0].byteSize == long.utf8.count)
        #expect(rows[0].contentHash == Fixtures.textClip(long).contentHash)
    }

    @Test func fullItemByIDKeepsEverything() throws {
        let long = String(repeating: "나", count: ClipStore.listTextLimit + 10)
        let id = try Fixtures.save(richClip(long), in: store)
        let full = try #require(try store.item(id: id))
        #expect(full.plainText == long)
        #expect(full.rtf == Data("{\\rtf1 \(long)}".utf8))
        #expect(full.html == Data("<b>\(long)</b>".utf8))
    }

    @Test func searchStillMatchesTextBeyondListCap() throws {
        let long = String(repeating: "x", count: ClipStore.listTextLimit + 100) + " 꼬리말찾기"
        let id = try Fixtures.save(Fixtures.textClip(long), in: store)
        try Fixtures.save(Fixtures.textClip("other"), in: store)
        #expect(try store.fetchUnpinned(matching: "꼬리말", settings: .default, now: Fixtures.now).map(\.id) == [id])
        #expect(try store.fetchUnpinned(matching: "꼬리", settings: .default, now: Fixtures.now).map(\.id) == [id])
    }

    @Test func listRowsKeepImageAndFileFields() throws {
        let imageID = try Fixtures.save(Fixtures.imageClip(seed: 3), in: store, at: Fixtures.now)
        let filesID = try Fixtures.save(Fixtures.filesClip(["/tmp/a.txt", "/tmp/b.txt"]), in: store, at: Fixtures.now.addingTimeInterval(1))
        let rows = try store.fetchUnpinned(settings: .default, now: Fixtures.now.addingTimeInterval(2))
        #expect(rows.map(\.id) == [filesID, imageID])
        #expect(rows[0].filePaths == ["/tmp/a.txt", "/tmp/b.txt"])
        #expect(rows[1].imageBlob != nil)
        #expect(rows[1].imageWidth == 4)
        #expect(rows[1].sourceAppName == "Finder")
    }
}
