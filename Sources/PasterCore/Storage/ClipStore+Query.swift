import Foundation
import GRDB

extension ClipStore {
    /// Clipboard 칼럼: 미고정 · 미만료 항목, 최근 복사 순.
    public func fetchUnpinned(
        matching query: String = "",
        settings: RetentionSettings,
        now: Date,
        calendar: Calendar = .current,
        limit: Int = 1000
    ) throws -> [ClipItem] {
        var request = ClipItem
            .filter(Column("pinned_at") == nil)
            .filter(Self.notExpired(settings: settings, now: now, calendar: calendar))
        if let condition = SearchFilter(query: query).sql {
            request = request.filter(condition)
        }
        return try dbQueue.read { db in
            try request
                .order(Column("last_copied_at").desc, Column("id").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Pinned 칼럼: pin_order 순. Pin 항목은 만료되지 않는다.
    public func fetchPinned(matching query: String = "") throws -> [ClipItem] {
        var request = ClipItem.filter(Column("pinned_at") != nil)
        if let condition = SearchFilter(query: query).sql {
            request = request.filter(condition)
        }
        return try dbQueue.read { db in
            try request.order(Column("pin_order"), Column("id")).fetchAll(db)
        }
    }

    /// 타입별 기간 안에 있는 행만 통과시키는 조건.
    static func notExpired(settings: RetentionSettings, now: Date, calendar: Calendar) -> SQLExpression {
        ClipKind.allCases
            .map { kind in
                Column("kind") == kind.rawValue
                    && Column("last_copied_at") >= settings[kind].period.cutoff(from: now, calendar: calendar)
            }
            .joined(operator: .or)
    }
}
