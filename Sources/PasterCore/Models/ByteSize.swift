import Foundation

/// 크기 표시 문자열. Finder 와 같은 10진 단위 (1 KB = 1000 B).
public enum ByteSize {
    public static func format(_ bytes: Int) -> String {
        let units = ["KB", "MB", "GB", "TB"]
        guard bytes >= 1000 else { return "\(bytes) B" }
        var value = Double(bytes)
        var unit = "B"
        for next in units where value >= 1000 {
            value /= 1000
            unit = next
        }
        return String(format: "%.1f %@", value, unit)
    }
}
