import Foundation
import GRDB

/// 검색어 → SQL 조건. 3글자 이상은 FTS5 trigram, 1~2글자는 LIKE.
enum SearchFilter: Equatable {
    case none
    case fullText(pattern: String)
    case like(pattern: String)

    init(query: String) {
        let trimmed = query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
        if trimmed.isEmpty {
            self = .none
        } else if trimmed.unicodeScalars.count >= 3 {
            // 큰따옴표로 감싸 FTS 문법을 무력화하고 부분 문자열로 찾는다
            self = .fullText(pattern: "\"" + trimmed.replacingOccurrences(of: "\"", with: "\"\"") + "\"")
        } else {
            let escaped = trimmed
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            self = .like(pattern: "%" + escaped + "%")
        }
    }

    var sql: SQL? {
        switch self {
        case .none:
            return nil
        case let .fullText(pattern):
            return SQL(sql: "id IN (SELECT rowid FROM clip_fts WHERE clip_fts MATCH ?)", arguments: [pattern])
        case let .like(pattern):
            return SQL(
                sql: "(plain_text LIKE ? ESCAPE '\\' OR IFNULL(source_app_name, '') LIKE ? ESCAPE '\\')",
                arguments: [pattern, pattern]
            )
        }
    }
}
