import Foundation

/// 보관 기간. 설정 화면 선택지와 같다.
public enum RetentionPeriod: String, Codable, CaseIterable, Sendable {
    case day = "24h"
    case week = "7d"
    case month = "1m"
    case threeMonths = "3m"

    public var label: String {
        switch self {
        case .day: "24시간"
        case .week: "7일"
        case .month: "1개월"
        case .threeMonths: "3개월"
        }
    }

    /// 이 시각보다 `last_copied_at` 이 이른 미고정 항목은 만료된 것이다.
    public func cutoff(from now: Date, calendar: Calendar) -> Date {
        switch self {
        case .day: now.addingTimeInterval(-24 * 60 * 60)
        case .week: now.addingTimeInterval(-7 * 24 * 60 * 60)
        case .month: calendar.date(byAdding: .month, value: -1, to: now)!
        case .threeMonths: calendar.date(byAdding: .month, value: -3, to: now)!
        }
    }
}

/// 타입 하나의 보관 설정.
public struct KindRetention: Codable, Equatable, Sendable {
    /// 꺼져 있으면 새로 캡처하지 않는다. 기존 항목은 기간 만료까지 유지한다.
    public var isEnabled: Bool
    public var period: RetentionPeriod

    public init(isEnabled: Bool = true, period: RetentionPeriod = .threeMonths) {
        self.isEnabled = isEnabled
        self.period = period
    }
}

/// 타입별 보관 설정. 기본값은 모두 켬 · 3개월.
public struct RetentionSettings: Codable, Equatable, Sendable {
    public var text: KindRetention
    public var image: KindRetention
    public var files: KindRetention

    public init(text: KindRetention = .init(), image: KindRetention = .init(), files: KindRetention = .init()) {
        self.text = text
        self.image = image
        self.files = files
    }

    public static let `default` = RetentionSettings()

    public subscript(kind: ClipKind) -> KindRetention {
        get {
            switch kind {
            case .text: text
            case .image: image
            case .files: files
            }
        }
        set {
            switch kind {
            case .text: text = newValue
            case .image: image = newValue
            case .files: files = newValue
            }
        }
    }

    public var enabledKinds: Set<ClipKind> {
        Set(ClipKind.allCases.filter { self[$0].isEnabled })
    }
}
