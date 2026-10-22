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
        } catch let error as DatabaseError where isCorruption(error) {
            // BUSY · 권한 등 손상이 아닌 오류는 정상 DB 를 건드리지 않도록 그대로 던진다.
            let name = try quarantine(databaseURL, now: now)
            Log.store.error("DB 손상(result code \(error.resultCode.rawValue, privacy: .public)), \(name, privacy: .public) 로 보존하고 새로 만듦")
            return try openChecked(at: databaseURL, blobs: blobs)
        }
    }

    private static func isCorruption(_ error: DatabaseError) -> Bool {
        switch error.resultCode.primaryResultCode {
        case .SQLITE_NOTADB, .SQLITE_CORRUPT: true
        default: false
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

    /// 손상본을 옮기고 본 파일의 새 이름을 돌려준다. 같은 이름이 이미 있으면 `-1`, `-2` ... 를 붙여 덮어쓰지 않는다.
    private static func quarantine(_ url: URL, now: Date) throws -> String {
        let base = ".corrupt-\(Int(now.timeIntervalSince1970))"
        let extras = ["", "-wal", "-shm", "-journal"]
        let fileManager = FileManager.default
        var suffix = base
        var attempt = 0
        while extras.contains(where: { fileManager.fileExists(atPath: url.path + suffix + $0) }) {
            attempt += 1
            suffix = "\(base)-\(attempt)"
        }
        for extra in extras {
            let source = URL(fileURLWithPath: url.path + extra)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.moveItem(at: source, to: URL(fileURLWithPath: url.path + suffix + extra))
        }
        return url.lastPathComponent + suffix
    }
}
