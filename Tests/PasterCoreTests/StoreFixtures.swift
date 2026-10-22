import Foundation
@testable import PasterCore

extension Fixtures {
    static let finder = SourceApp(bundleID: "com.apple.finder", name: "Finder")
    static let safari = SourceApp(bundleID: "com.apple.Safari", name: "Safari")

    static func makeStore() throws -> ClipStore {
        try ClipStore.inMemory(blobDirectory: temporaryDirectory())
    }

    static func textClip(_ text: String, source: SourceApp = finder) -> CapturedClip {
        CapturedClip(kind: .text, plainText: text, byteSize: text.utf8.count, source: source,
                     contentHash: ContentHasher.hash(kind: .text, payload: Data(text.utf8)))
    }

    static func imageClip(seed: Int, source: SourceApp = finder) -> CapturedClip {
        let png = image(width: seed + 1, height: 1, type: .png)
        return CapturedClip(kind: .image, plainText: "", pngData: png, imageWidth: seed + 1, imageHeight: 1,
                            byteSize: png.count, source: source,
                            contentHash: ContentHasher.hash(kind: .image, payload: png))
    }

    static func filesClip(_ paths: [String], source: SourceApp = finder) -> CapturedClip {
        let names = paths
            .map { URL(fileURLWithPath: $0).lastPathComponent.precomposedStringWithCanonicalMapping }
            .joined(separator: "\n")
        return CapturedClip(kind: .files, plainText: names, byteSize: 0, filePaths: paths, source: source,
                            contentHash: ContentHasher.hash(kind: .files, payload: Data(paths.joined(separator: "\n").utf8)))
    }

    /// 저장 후 id 를 돌려준다.
    @discardableResult
    static func save(_ clip: CapturedClip, in store: ClipStore, at date: Date = now) throws -> Int64 {
        try store.save(clip, now: date).item.id!
    }
}
