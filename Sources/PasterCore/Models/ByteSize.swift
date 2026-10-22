import Foundation

/// 크기 표시 문자열. Finder 와 같은 10진 단위 (1 KB = 1000 B).
public enum ByteSize {
    public static func format(_ bytes: Int) -> String {
        let units = ["KB", "MB", "GB", "TB"]
        guard bytes >= 1000 else { return "\(bytes) B" }
        var value = Double(bytes)
        var unit = "B"
        for next in units {
            // 소수 첫째 자리로 반올림했을 때 1000 이 되면 다음 단위로 올린다
            guard (value * 10).rounded() / 10 >= 1000 else { break }
            value /= 1000
            unit = next
        }
        return String(format: "%.1f %@", value, unit)
    }
}
