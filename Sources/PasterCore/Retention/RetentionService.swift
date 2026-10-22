import Foundation

public struct PurgeReport: Equatable, Sendable {
    public var expiredCount: Int
    public var orphanBlobCount: Int
}

/// 만료 항목과 고아 blob 정리.
public struct RetentionService: Sendable {
    public let store: ClipStore
    public let calendar: Calendar
    public let now: @Sendable () -> Date

    public init(store: ClipStore, calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.calendar = calendar
        self.now = now
    }

    @discardableResult
    public func purge(settings: RetentionSettings) throws -> PurgeReport {
        try purge(settings: settings, at: now())
    }

    /// 정리하고 오늘 날짜를 기록한다.
    @discardableResult
    public func purge(using settings: PasterSettings) throws -> PurgeReport {
        try purge(using: settings, at: now())
    }

    /// 마지막 정리 이후 날짜가 바뀌었을 때만 정리한다. 정리했으면 report, 아니면 nil.
    @discardableResult
    public func purgeIfDayChanged(using settings: PasterSettings) throws -> PurgeReport? {
        // 시계는 호출당 한 번만 읽어 자정에 걸쳐도 기준 시각이 하나로 유지된다
        let current = now()
        guard RetentionSchedule.shouldPurge(lastPurgeDay: settings.lastPurgeDay, now: current, calendar: calendar) else {
            return nil
        }
        return try purge(using: settings, at: current)
    }

    private func purge(settings: RetentionSettings, at current: Date) throws -> PurgeReport {
        let expired = try store.deleteExpired(settings: settings, now: current, calendar: calendar)
        let orphans = try store.sweepOrphanBlobs()
        Log.retention.info("정리 완료: 만료 \(expired, privacy: .public)건, 고아 blob \(orphans, privacy: .public)개")
        return PurgeReport(expiredCount: expired, orphanBlobCount: orphans)
    }

    private func purge(using settings: PasterSettings, at current: Date) throws -> PurgeReport {
        let report = try purge(settings: settings.retention, at: current)
        settings.lastPurgeDay = RetentionSchedule.dayKey(for: current, calendar: calendar)
        return report
    }
}
