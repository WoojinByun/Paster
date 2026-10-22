import Foundation
import GRDB

extension ClipStore {
    /// 목록 행에 담는 `plain_text` 의 최대 글자 수. 제목과 검색 결과 표시에 충분한 만큼만 읽는다.
    public static let listTextLimit = 2000

    /// 목록 투영: `rtf` · `html` 은 읽지 않고 `plain_text` 는 앞 `listTextLimit` 글자만 읽는다.
    static let listSelection = """
        id, kind, substr(plain_text, 1, \(listTextLimit)) AS plain_text,
        image_blob, image_width, image_height, byte_size, file_paths,
        source_bundle_id, source_app_name, content_hash,
        created_at, last_copied_at, pinned_at, pin_order
        """

    /// Clipboard 칼럼: 미고정 · 미만료 항목, 최근 복사 순.
    ///
    /// 목록 투영을 돌려준다: `rtf` · `html` 은 nil, `plainText` 는 앞 `listTextLimit` 글자까지.
    /// 붙여넣기 · 미리보기처럼 전체 내용이 필요하면 `item(id:)` 로 다시 읽는다. 이 값으로 행을 update 하지 않는다.
    public func fetchUnpinned(
        matching query: String = "",
        settings: RetentionSettings,
        now: Date,
        calendar: Calendar = .current,
        limit: Int = 1000
    ) throws -> [ClipItem] {
        var request = ClipItem
            .select(sql: Self.listSelection)
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
    ///
    /// `fetchUnpinned` 와 같은 목록 투영을 돌려준다.
    public func fetchPinned(matching query: String = "") throws -> [ClipItem] {
        var request = ClipItem
            .select(sql: Self.listSelection)
            .filter(Column("pinned_at") != nil)
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
