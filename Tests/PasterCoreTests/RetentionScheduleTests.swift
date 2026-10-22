import Foundation
import Testing
@testable import PasterCore

struct RetentionScheduleTests {
    func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    func date(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    @Test func nextMidnightInSeoul() {
        let seoul = calendar("Asia/Seoul")
        // 2027-01-15 23:30 KST → 2027-01-16 00:00 KST
        #expect(RetentionSchedule.nextMidnight(after: date("2027-01-15T14:30:00Z"), calendar: seoul) == date("2027-01-15T15:00:00Z"))
    }

    @Test func exactlyMidnightMovesToTheNextDay() {
        let seoul = calendar("Asia/Seoul")
        #expect(RetentionSchedule.nextMidnight(after: date("2027-01-15T15:00:00Z"), calendar: seoul) == date("2027-01-16T15:00:00Z"))
    }

    @Test func missingMidnightFallsToFirstHourOfDay() {
        // 2018-11-04 상파울루는 00:00 → 01:00 으로 건너뛰었다
        let saoPaulo = calendar("America/Sao_Paulo")
        let next = RetentionSchedule.nextMidnight(after: date("2018-11-03T12:00:00Z"), calendar: saoPaulo)
        #expect(next == date("2018-11-04T03:00:00Z"))
    }

    @Test func dayKeyUsesLocalDate() {
        #expect(RetentionSchedule.dayKey(for: date("2027-01-15T15:30:00Z"), calendar: calendar("Asia/Seoul")) == "2027-01-16")
        #expect(RetentionSchedule.dayKey(for: date("2027-01-15T15:30:00Z"), calendar: calendar("UTC")) == "2027-01-15")
    }

    @Test func shouldPurgeOnlyWhenDayChanged() {
        let seoul = calendar("Asia/Seoul")
        let now = date("2027-01-15T03:00:00Z") // 12:00 KST
        #expect(RetentionSchedule.shouldPurge(lastPurgeDay: nil, now: now, calendar: seoul))
        #expect(RetentionSchedule.shouldPurge(lastPurgeDay: "2027-01-14", now: now, calendar: seoul))
        #expect(!RetentionSchedule.shouldPurge(lastPurgeDay: "2027-01-15", now: now, calendar: seoul))
    }
}
