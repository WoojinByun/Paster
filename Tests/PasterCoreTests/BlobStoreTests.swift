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
}
