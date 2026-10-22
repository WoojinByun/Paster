import Foundation
import GRDB

extension ClipStore {
    /// 항목 하나와 그 blob 을 지운다. 지웠으면 true.
    @discardableResult
    public func delete(id: Int64) throws -> Bool {
        let blobName: String?? = try dbQueue.write { db in
            guard let item = try ClipItem.fetchOne(db, key: id) else { return nil }
            try item.delete(db)
            return .some(item.imageBlob)
        }
        guard let blobName else { return false }
        if let blobName { blobs.remove(blobName) }
        return true
    }

    /// Clear All History: 미고정 항목과 그 blob 만 지운다. 지운 행 수를 돌려준다.
    @discardableResult
    public func deleteAllUnpinned() throws -> Int {
        try deleteRows(where: SQL(sql: "pinned_at IS NULL"))
    }

    /// 만료 조건 `pinned_at IS NULL AND last_copied_at < now - 기간` 에 맞는 행과 blob 을 지운다.
    @discardableResult
    public func deleteExpired(settings: RetentionSettings, now: Date, calendar: Calendar = .current) throws -> Int {
        var conditions: [SQL] = []
        for kind in ClipKind.allCases {
            let cutoff = settings[kind].period.cutoff(from: now, calendar: calendar)
            conditions.append(SQL(sql: "(kind = ? AND last_copied_at < ?)", arguments: [kind.rawValue, cutoff]))
        }
        let expired = conditions.joined(separator: " OR ")
        return try deleteRows(where: "pinned_at IS NULL AND (\(expired))")
    }

    /// DB 가 참조하지 않는 blob 파일을 지운다. 지운 파일 수를 돌려준다.
    /// save 와 같은 write 큐 안에서 실행하므로 저장 중인 blob 을 지우지 않는다.
    @discardableResult
    public func sweepOrphanBlobs() throws -> Int {
        try dbQueue.write { db in
            let referenced = try Set(
                String.fetchAll(db, sql: "SELECT image_blob FROM clip_items WHERE image_blob IS NOT NULL")
            )
            let orphans = blobs.allNames().subtracting(referenced)
            for name in orphans { blobs.remove(name) }
            return orphans.count
        }
    }

    private func deleteRows(where condition: SQL) throws -> Int {
        let (count, blobNames): (Int, [String]) = try dbQueue.write { db in
            let names = try SQLRequest<String>(
                literal: "SELECT image_blob FROM clip_items WHERE image_blob IS NOT NULL AND \(condition)"
            ).fetchAll(db)
            try db.execute(literal: "DELETE FROM clip_items WHERE \(condition)")
            return (db.changesCount, names)
        }
        for name in blobNames { blobs.remove(name) }
        return count
    }
}
