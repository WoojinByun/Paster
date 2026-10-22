import Foundation
import GRDB

/// 검색어 → SQL 조건. 공백으로 나눈 단어를 모두 만족해야 한다(AND).
/// 단어마다 3글자 이상은 FTS5 trigram, 1~2글자는 LIKE.
struct SearchFilter: Equatable {
    enum Term: Equatable {
        /// MATCH 패턴. NFC / NFD 변형 중 하나라도 맞으면 통과한다.
        case fullText(patterns: [String])
        /// LIKE 패턴. NFC / NFD 변형 중 하나라도 맞으면 통과한다.
        case like(patterns: [String])
    }

    let terms: [Term]

    init(query: String) {
        terms = query
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map(Self.term(for:))
    }

    private static func term(for raw: String) -> Term {
        let nfc = raw.precomposedStringWithCanonicalMapping
        // 저장된 텍스트는 NFC 일 수도 NFD 일 수도 있어서 두 형태를 모두 찾는다
        var variants = [nfc]
        let nfd = raw.decomposedStringWithCanonicalMapping
        // Swift String 의 == 는 정규 동등이라 NFC/NFD 를 같다고 보므로 스칼라로 비교한다
        if !nfd.unicodeScalars.elementsEqual(nfc.unicodeScalars) { variants.append(nfd) }

        if nfc.unicodeScalars.count >= 3 {
            // 큰따옴표로 감싸 FTS 문법을 무력화하고 부분 문자열로 찾는다
            return .fullText(patterns: variants.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"" })
        }
        return .like(patterns: variants.map { variant in
            let escaped = variant
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            return "%" + escaped + "%"
        })
    }

    var sql: SQL? {
        guard !terms.isEmpty else { return nil }
        var clauses: [String] = []
        var arguments: [any DatabaseValueConvertible] = []
        for term in terms {
            switch term {
            case let .fullText(patterns):
                clauses.append("(" + patterns
                    .map { _ in "id IN (SELECT rowid FROM clip_fts WHERE clip_fts MATCH ?)" }
                    .joined(separator: " OR ") + ")")
                arguments += patterns
            case let .like(patterns):
                clauses.append("(" + patterns
                    .map { _ in "plain_text LIKE ? ESCAPE '\\' OR IFNULL(source_app_name, '') LIKE ? ESCAPE '\\'" }
                    .joined(separator: " OR ") + ")")
                arguments += patterns.flatMap { [$0, $0] }
            }
        }
        return SQL(sql: clauses.joined(separator: " AND "), arguments: StatementArguments(arguments))
    }
}
