import Foundation
import GRDB
import Testing
@testable import PasterCore

struct ClipStoreSaveTests {
    let store: ClipStore

    init() throws {
        store = try Fixtures.makeStore()
    }

    @Test func insertAssignsIDAndTimestamps() throws {
        let outcome = try store.save(Fixtures.textClip("hello"), now: Fixtures.now)
        guard case let .inserted(item) = outcome else { Issue.record("inserted 가 아님"); return }
        let id = try #require(item.id)
        let loaded = try #require(try store.item(id: id))
        #expect(loaded == item)
        #expect(loaded.createdAt == Fixtures.now)
        #expect(loaded.lastCopiedAt == Fixtures.now)
        #expect(loaded.pinnedAt == nil)
        #expect(loaded.sourceAppName == "Finder")
    }

    @Test func sameHashBumpsInsteadOfInserting() throws {
        let first = try store.save(Fixtures.textClip("hello"), now: Fixtures.now).item
        let later = Fixtures.now.addingTimeInterval(60)
        let outcome = try store.save(Fixtures.textClip("hello", source: Fixtures.safari), now: later)
        guard case let .bumped(bumped) = outcome else { Issue.record("bumped 가 아님"); return }
        #expect(bumped.id == first.id)
        #expect(bumped.createdAt == Fixtures.now)
        #expect(bumped.lastCopiedAt == later)
        #expect(bumped.sourceBundleID == "com.apple.Safari")
        #expect(bumped.sourceAppName == "Safari")
        let count = try store.dbQueue.read { try ClipItem.fetchCount($0) }
        #expect(count == 1)
    }

    @Test func filePathsRoundTripAsJSON() throws {
        let id = try Fixtures.save(Fixtures.filesClip(["/tmp/a b.txt", "/tmp/한글.pdf"]), in: store)
        #expect(try store.item(id: id)?.filePaths == ["/tmp/a b.txt", "/tmp/한글.pdf"])
        let raw = try store.dbQueue.read { try String.fetchOne($0, sql: "SELECT file_paths FROM clip_items") }
        #expect(raw?.hasPrefix("[") == true)
    }

    @Test func imageIsWrittenAsBlob() throws {
        let clip = Fixtures.imageClip(seed: 2)
        let item = try store.save(clip, now: Fixtures.now).item
        let blobName = try #require(item.imageBlob)
        #expect(store.blobs.read(blobName) == clip.pngData)
    }

    @Test func bumpingAnImageDoesNotWriteANewBlob() throws {
        let clip = Fixtures.imageClip(seed: 2)
        try store.save(clip, now: Fixtures.now)
        try store.save(clip, now: Fixtures.now.addingTimeInterval(1))
        #expect(store.blobs.allNames().count == 1)
    }

    @Test func touchMovesLastCopiedAt() throws {
        let id = try Fixtures.save(Fixtures.textClip("x"), in: store)
        let later = Fixtures.now.addingTimeInterval(3600)
        try store.touch(id: id, now: later)
        #expect(try store.item(id: id)?.lastCopiedAt == later)
    }
}
