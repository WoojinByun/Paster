import Foundation
import Testing
@testable import PasterCore

struct RetentionSettingsTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }()

    func date(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: string)!
    }

    @Test func defaultIsAllEnabledThreeMonths() {
        let settings = RetentionSettings.default
        for kind in ClipKind.allCases {
            #expect(settings[kind] == KindRetention(isEnabled: true, period: .threeMonths))
        }
        #expect(settings.enabledKinds == Set(ClipKind.allCases))
    }

    @Test func subscriptSetsOnlyThatKind() {
        var settings = RetentionSettings.default
        settings[.image] = KindRetention(isEnabled: false, period: .day)
        #expect(settings.image == KindRetention(isEnabled: false, period: .day))
        #expect(settings.text == KindRetention())
        #expect(settings.enabledKinds == [.text, .files])
    }

    @Test func cutoffs() {
        let now = date("2026-05-31T12:00:00Z")
        #expect(RetentionPeriod.day.cutoff(from: now, calendar: calendar) == date("2026-05-30T12:00:00Z"))
        #expect(RetentionPeriod.week.cutoff(from: now, calendar: calendar) == date("2026-05-24T12:00:00Z"))
        // 5월 31일의 1개월 전은 4월 30일 (달력 기준)
        #expect(RetentionPeriod.month.cutoff(from: now, calendar: calendar) == date("2026-04-30T12:00:00Z"))
        #expect(RetentionPeriod.threeMonths.cutoff(from: now, calendar: calendar) == date("2026-02-28T12:00:00Z"))
    }

    @Test func codableRoundTrip() throws {
        var settings = RetentionSettings.default
        settings.files = KindRetention(isEnabled: false, period: .week)
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(RetentionSettings.self, from: data) == settings)
    }
}
