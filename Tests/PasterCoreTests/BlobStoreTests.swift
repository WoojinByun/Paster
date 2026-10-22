import Foundation
import Testing
@testable import PasterCore

struct BlobStoreTests {
    @Test func writeReadRemove() throws {
        let directory = try Fixtures.temporaryDirectory().appendingPathComponent("blobs")
        let store = try BlobStore(directory: directory)
        let name = try store.write(Data([1, 2, 3]))
        #expect(name.hasSuffix(".png"))
        #expect(UUID(uuidString: String(name.dropLast(4))) != nil)
        #expect(store.read(name) == Data([1, 2, 3]))
        #expect(store.allNames() == [name])

        store.remove(name)
        #expect(store.read(name) == nil)
        #expect(store.allNames().isEmpty)
    }

    @Test func allNamesIgnoresOtherFiles() throws {
        let store = try BlobStore(directory: Fixtures.temporaryDirectory())
        try Data().write(to: store.directory.appendingPathComponent(".DS_Store"))
        let name = try store.write(Data([0]))
        #expect(store.allNames() == [name])
    }

    @Test func removeIgnoresNamesOutsideDirectory() throws {
        let parent = try Fixtures.temporaryDirectory()
        let store = try BlobStore(directory: parent.appendingPathComponent("blobs"))
        let outside = parent.appendingPathComponent("x.png")
        try Data([7]).write(to: outside)

        store.remove("../x.png")
        #expect(FileManager.default.fileExists(atPath: outside.path))
        #expect(store.read("../x.png") == nil)
    }

    @Test func rejectsNonPlainNames() throws {
        let parent = try Fixtures.temporaryDirectory()
        let store = try BlobStore(directory: parent.appendingPathComponent("blobs"))
        try Data([7]).write(to: parent.appendingPathComponent("paster.sqlite"))
        let valid = try store.write(Data([1]))

        for name in ["../paster.sqlite", "a/b.png", "/etc/passwd", ".", "..", "", "x.txt", "x.png/"] {
            #expect(store.read(name) == nil, "\(name)")
            store.remove(name)
            #expect(store.url(for: name).deletingLastPathComponent().standardizedFileURL == store.directory.standardizedFileURL, "\(name)")
        }
        #expect(FileManager.default.fileExists(atPath: parent.appendingPathComponent("paster.sqlite").path))
        #expect(store.read(valid) == Data([1]))
    }
}
