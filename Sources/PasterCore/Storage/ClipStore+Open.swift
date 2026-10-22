import Foundation
import GRDB

extension ClipStore {
    /// `directory/paster.sqlite` 와 `directory/blobs/` 를 연다.
    /// DB 를 열 수 없거나 손상됐으면 `paster.sqlite.corrupt-<timestamp>` 로 옮겨 보존하고 새 DB 를 만든다.
    public static func open(directory: URL, now: Date = Date()) throws -> ClipStore {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let blobs = try BlobStore(directory: directory.appendingPathComponent(blobDirectoryName, isDirectory: true))
        let databaseURL = directory.appendingPathComponent(databaseFileName)
        do {
            return try openChecked(at: databaseURL, blobs: blobs)
        } catch {
            Log.store.error("DB 열기 실패, 손상본을 보존하고 새로 만듦: \(String(describing: error), privacy: .public)")
            try quarantine(databaseURL, now: now)
            return try openChecked(at: databaseURL, blobs: blobs)
        }
    }

    private static func openChecked(at url: URL, blobs: BlobStore) throws -> ClipStore {
        let dbQueue = try DatabaseQueue(path: url.path)
        let result = try dbQueue.read { try String.fetchOne($0, sql: "PRAGMA quick_check") }
        guard result == "ok" else {
            throw DatabaseError(resultCode: .SQLITE_CORRUPT, message: "quick_check: \(result ?? "nil")")
        }
        return try ClipStore(dbQueue: dbQueue, blobs: blobs)
    }

    private static func quarantine(_ url: URL, now: Date) throws {
        let suffix = ".corrupt-\(Int(now.timeIntervalSince1970))"
        let fileManager = FileManager.default
        for extra in ["", "-wal", "-shm", "-journal"] {
            let source = URL(fileURLWithPath: url.path + extra)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = URL(fileURLWithPath: url.path + suffix + extra)
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: source, to: destination)
        }
    }
}
