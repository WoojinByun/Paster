/// 클립 종류. DB 의 `kind` 칼럼 값과 같다.
public enum ClipKind: String, Codable, CaseIterable, Sendable {
    case text
    case image
    case files
}
