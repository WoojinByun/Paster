import Foundation
import Testing
@testable import PasterCore

/// 테스트에서 시계를 움직이기 위한 상자.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ date: Date) { current = date }

    var now: Date {
        lock.withLock { current }
    }

    func advance(by seconds: TimeInterval) {
        lock.withLock { current = current.addingTimeInterval(seconds) }
    }
}

/// 읽을 때마다 정해진 만큼 흐르고, 읽은 시각을 모두 기록하는 시계.
final class TickingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    private let step: TimeInterval
    private var reads: [Date] = []

    init(start: Date, step: TimeInterval) {
        current = start
        self.step = step
    }

    var readTimes: [Date] { lock.withLock { reads } }

    func read() -> Date {
        lock.withLock {
            let value = current
            reads.append(value)
            current = current.addingTimeInterval(step)
            return value
        }
    }
}

struct RetentionServiceTests {
    let store: ClipStore
    let clock = TestClock(Fixtures.now)
    let settings: PasterSettings
    let service: RetentionService
    let day: TimeInterval = 24 * 3600

    init() throws {
        store = try Fixtures.makeStore()
        settings = PasterSettings(store: InMemorySettingsStore())
        let calendar = Self.seoulCalendar
        let clock = clock
        service = RetentionService(store: store, calendar: calendar, now: { clock.now })
    }

    static var seoulCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return calendar
    }

    @Test func purgeDeletesExpiredPerKindAndKeepsPinned() throws {
        var retention = RetentionSettings.default
        retention.text.period = .week
        retention.image.period = .day
        try Fixtures.save(Fixtures.textClip("8 days"), in: store, at: Fixtures.now.addingTimeInterval(-8 * day))
        try Fixtures.save(Fixtures.textClip("6 days"), in: store, at: Fixtures.now.addingTimeInterval(-6 * day))
        try Fixtures.save(Fixtures.imageClip(seed: 1), in: store, at: Fixtures.now.addingTimeInterval(-2 * day))
        let pinned = try Fixtures.save(Fixtures.imageClip(seed: 2), in: store, at: Fixtures.now.addingTimeInterval(-90 * day))
        try store.pin(id: pinned, now: Fixtures.now.addingTimeInterval(-90 * day))

        let report = try service.purge(settings: retention)

        #expect(report == PurgeReport(expiredCount: 2, orphanBlobCount: 0))
        #expect(try store.fetchUnpinned(settings: retention, now: clock.now).map(\.plainText) == ["6 days"])
        #expect(try store.fetchPinned().map(\.id) == [pinned])
        #expect(store.blobs.allNames().count == 1)
    }

    @Test func purgeSweepsOrphanBlobs() throws {
        _ = try store.blobs.write(Data([1]))
        #expect(try service.purge(settings: .default).orphanBlobCount == 1)
        #expect(store.blobs.allNames().isEmpty)
    }

    @Test func expiryFollowsTheInjectedClock() throws {
        var retention = RetentionSettings.default
        retention.text.period = .day
        settings.retention = retention
        try Fixtures.save(Fixtures.textClip("today"), in: store, at: Fixtures.now)

        #expect(try service.purge(using: settings).expiredCount == 0)
        clock.advance(by: day + 1)
        #expect(try service.purge(using: settings).expiredCount == 1)
    }

    @Test func purgeRecordsTheLocalDay() throws {
        try service.purge(using: settings)
        // Fixtures.now = 2027-01-15 08:00 UTC = 17:00 KST
        #expect(settings.lastPurgeDay == "2027-01-15")
    }

    @Test func purgeIfDayChangedRunsOncePerDay() throws {
        #expect(try service.purgeIfDayChanged(using: settings) != nil)
        #expect(try service.purgeIfDayChanged(using: settings) == nil)
        clock.advance(by: 7 * 3600) // 2027-01-16 00:00 KST
        #expect(try service.purgeIfDayChanged(using: settings) != nil)
        #expect(settings.lastPurgeDay == "2027-01-16")
    }

    @Test func purgeReadsTheClockOnceSoCutoffAndDayKeyAgree() throws {
        // 2027-01-15 23:59:59 KST. 시계를 두 번 읽으면 두 번째는 다음 날이 된다
        let start = try #require(ISO8601DateFormatter().date(from: "2027-01-15T14:59:59Z"))
        let ticking = TickingClock(start: start, step: 1)
        let service = RetentionService(store: store, calendar: Self.seoulCalendar, now: { ticking.read() })

        try service.purge(using: settings)

        #expect(ticking.readTimes.count == 1)
        #expect(settings.lastPurgeDay == "2027-01-15")
    }

    @Test func purgeIfDayChangedReadsTheClockOnce() throws {
        let start = try #require(ISO8601DateFormatter().date(from: "2027-01-15T14:59:59Z"))
        let ticking = TickingClock(start: start, step: 1)
        let service = RetentionService(store: store, calendar: Self.seoulCalendar, now: { ticking.read() })

        #expect(try service.purgeIfDayChanged(using: settings) != nil)
        #expect(ticking.readTimes.count == 1)
        #expect(settings.lastPurgeDay == "2027-01-15")
    }
}
