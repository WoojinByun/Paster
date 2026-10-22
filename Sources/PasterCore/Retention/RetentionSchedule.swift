import Foundation

/// 정리 시점 계산 (스펙 7.2절). 순수 함수만 둔다.
public enum RetentionSchedule {
    /// `now` 이후 첫 로컬 0시. 0시가 없는 날(DST)에는 그날의 첫 시각.
    public static func nextMidnight(after now: Date, calendar: Calendar) -> Date {
        calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        )!
    }

    /// 로컬 날짜 키 `yyyy-MM-dd`. 마지막 정리 날짜 기록용.
    public static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    }

    /// 마지막 정리 이후 로컬 날짜가 바뀌었으면 true. 잠자기에서 깼을 때 쓴다.
    public static func shouldPurge(lastPurgeDay: String?, now: Date, calendar: Calendar) -> Bool {
        lastPurgeDay != dayKey(for: now, calendar: calendar)
    }
}
