import Foundation
import GRDB

extension ClipStore {
    /// 고정한다. Pinned 칼럼 맨 아래에 붙는다.
    public func pin(id: Int64, now: Date) throws {
        try dbQueue.write { db in
            let maxOrder = try Int.fetchOne(db, sql: "SELECT MAX(pin_order) FROM clip_items WHERE pinned_at IS NOT NULL") ?? -1
            try db.execute(
                sql: "UPDATE clip_items SET pinned_at = ?, pin_order = ? WHERE id = ? AND pinned_at IS NULL",
                arguments: [now, maxOrder + 1, id]
            )
        }
    }

    /// 고정 해제. 해제 즉시 만료되지 않도록 last_copied_at 을 now 로 바꾼다.
    public func unpin(id: Int64, now: Date) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    UPDATE clip_items SET pinned_at = NULL, pin_order = NULL, last_copied_at = ?
                    WHERE id = ? AND pinned_at IS NOT NULL
                    """,
                arguments: [now, id]
            )
        }
    }

    /// Pinned 칼럼 안에서 한 칸 옮긴다. 옮겼으면 true.
    @discardableResult
    public func movePinned(id: Int64, direction: MoveDirection) throws -> Bool {
        try dbQueue.write { db in
            var ids = try Int64.fetchAll(
                db, sql: "SELECT id FROM clip_items WHERE pinned_at IS NOT NULL ORDER BY pin_order, id"
            )
            guard let index = ids.firstIndex(of: id) else { return false }
            let target = direction == .up ? index - 1 : index + 1
            guard ids.indices.contains(target) else { return false }
            ids.swapAt(index, target)
            for (order, pinnedID) in ids.enumerated() {
                try db.execute(sql: "UPDATE clip_items SET pin_order = ? WHERE id = ?", arguments: [order, pinnedID])
            }
            return true
        }
    }
}
