import Foundation
import Testing
@testable import PasterCore

struct ClipStoreDeleteTests {
    let store: ClipStore
    let hour: TimeInterval = 3600

    init() throws {
        store = try Fixtures.makeStore()
    }

    func allTexts() throws -> [String] {
        try store.dbQueue.read { try String.fetchAll($0, sql: "SELECT plain_text FROM clip_items ORDER BY id") }
    }

    @Test func deleteRemovesRowBlobAndSearchEntry() throws {
        let image = try store.save(Fixtures.imageClip(seed: 1), now: Fixtures.now).item
        let text = try Fixtures.save(Fixtures.textClip("지울 항목입니다"), in: store)
        #expect(try store.delete(id: image.id!))
        #expect(try store.delete(id: text))
        #expect(store.blobs.allNames().isEmpty)
        #expect(try store.fetchUnpinned(matching: "지울 항목", settings: .default, now: Fixtures.now).isEmpty)
        #expect(try store.delete(id: text) == false)
    }

    @Test func deleteAllUnpinnedKeepsPinned() throws {
        let pinnedImage = try Fixtures.save(Fixtures.imageClip(seed: 1), in: store)
        try store.pin(id: pinnedImage, now: Fixtures.now)
        try Fixtures.save(Fixtures.imageClip(seed: 2), in: store)
        try Fixtures.save(Fixtures.textClip("bye"), in: store)

        #expect(try store.deleteAllUnpinned() == 2)
        #expect(try store.fetchPinned().map(\.id) == [pinnedImage])
        #expect(store.blobs.allNames() == [try store.item(id: pinnedImage)!.imageBlob!])
    }

    @Test func deleteExpiredUsesPerKindPeriodsAndSkipsPinned() throws {
        var settings = RetentionSettings.default
        settings.text.period = .day
        settings.image.period = .week
        settings.files = KindRetention(isEnabled: false, period: .day)

        try Fixtures.save(Fixtures.textClip("text 25h"), in: store, at: Fixtures.now.addingTimeInterval(-25 * hour))
        try Fixtures.save(Fixtures.textClip("text 23h"), in: store, at: Fixtures.now.addingTimeInterval(-23 * hour))
        let pinned = try Fixtures.save(Fixtures.textClip("pinned 1y"), in: store, at: Fixtures.now.addingTimeInterval(-365 * 24 * hour))
        try store.pin(id: pinned, now: Fixtures.now)
        try Fixtures.save(Fixtures.imageClip(seed: 1), in: store, at: Fixtures.now.addingTimeInterval(-8 * 24 * hour))
        let freshImage = try Fixtures.save(Fixtures.imageClip(seed: 2), in: store, at: Fixtures.now.addingTimeInterval(-6 * 24 * hour))
        try Fixtures.save(Fixtures.filesClip(["/tmp/old.txt"]), in: store, at: Fixtures.now.addingTimeInterval(-2 * 24 * hour))

        #expect(try store.deleteExpired(settings: settings, now: Fixtures.now) == 3)
        #expect(try allTexts() == ["text 23h", "pinned 1y", ""])
        #expect(store.blobs.allNames() == [try store.item(id: freshImage)!.imageBlob!])
    }

    @Test func sweepOrphanBlobsRemovesOnlyUnreferencedFiles() throws {
        let kept = try store.save(Fixtures.imageClip(seed: 1), now: Fixtures.now).item.imageBlob!
        let orphan = try store.blobs.write(Data([9]))
        #expect(try store.sweepOrphanBlobs() == 1)
        #expect(store.blobs.allNames() == [kept])
        #expect(store.blobs.read(orphan) == nil)
    }
}
