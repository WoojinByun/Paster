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

    /// 디렉터리 밖으로 나가지 않는 평범한 `.png` 파일 이름만 허용한다.
    static func isPlainName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && name.hasSuffix(".png")
    }

    /// 잘못된 이름은 디렉터리 안의 존재하지 않는 자리 표시 경로로 바꾼다.
    public func url(for name: String) -> URL {
        directory.appendingPathComponent(Self.isPlainName(name) ? name : ".invalid", isDirectory: false)
    }

    public func read(_ name: String) -> Data? {
        guard Self.isPlainName(name) else { return nil }
        return try? Data(contentsOf: url(for: name))
    }

    public func remove(_ name: String) {
        guard Self.isPlainName(name) else { return }
        try? FileManager.default.removeItem(at: url(for: name))
    }

    /// 디렉터리 안의 모든 `.png` 파일 이름.
    public func allNames() -> Set<String> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(names.filter { $0.hasSuffix(".png") })
    }
}
