import Foundation

/// `blobs/<uuid>.png` 파일 관리.
public struct BlobStore: Sendable {
    public let directory: URL

    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// 새 blob 을 쓰고 파일 이름을 돌려준다.
    public func write(_ data: Data) throws -> String {
        let name = UUID().uuidString.lowercased() + ".png"
        try data.write(to: url(for: name), options: .atomic)
        return name
    }

    public func url(for name: String) -> URL {
        directory.appendingPathComponent(name, isDirectory: false)
    }

    public func read(_ name: String) -> Data? {
        try? Data(contentsOf: url(for: name))
    }

    public func remove(_ name: String) {
        try? FileManager.default.removeItem(at: url(for: name))
    }

    /// 디렉터리 안의 모든 `.png` 파일 이름.
    public func allNames() -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(names.filter { $0.hasSuffix(".png") })
    }
}
