import AppKit
import PasterCore

/// 정리 시점 관리 (스펙 7.2절): 실행 시, 매일 0시, 잠자기에서 깬 뒤 날짜가 바뀌었을 때.
/// 시계 · 시간대가 바뀌면 0시 타이머를 다시 잡는다.
/// 타이머와 알림은 메인 액터에서 받고, DB · 파일 I/O 가 있는 정리는 메인 밖에서 순서대로 실행한다.
@MainActor
final class RetentionScheduler {
    private let service: RetentionService
    private let settings: PasterSettings
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    /// 정리를 겹치지 않고 순서대로 처리하기 위한 마지막 작업
    private var pending: Task<Void, Never>?

    var onPurged: (() -> Void)?

    init(service: RetentionService, settings: PasterSettings) {
        self.service = service
        self.settings = settings
    }

    func start() {
        purge(onlyIfDayChanged: false)
        scheduleMidnight()

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        observe(workspaceCenter, NSWorkspace.didWakeNotification) { $0.didWake() }
        observe(.default, .NSSystemClockDidChange) { $0.clockDidChange() }
        observe(.default, .NSSystemTimeZoneDidChange) { $0.clockDidChange() }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ handler: @escaping @MainActor (RetentionScheduler) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                handler(self)
            }
        }
        observers.append((center, token))
    }

    private func didWake() {
        purge(onlyIfDayChanged: true)
        // 잠든 사이 0시가 지났을 수 있으니 다시 잡는다
        scheduleMidnight()
    }

    private func clockDidChange() {
        NSTimeZone.resetSystemTimeZone()
        scheduleMidnight()
    }

    /// `firedAt` 은 방금 울린 0시. 타이머가 조금 일찍 깨어도 같은 0시를 다시 잡지 않게 기준으로 쓴다.
    private func scheduleMidnight(after firedAt: Date? = nil) {
        timer?.invalidate()
        let reference = max(Date(), firedAt ?? .distantPast)
        let fireDate = RetentionSchedule.nextMidnight(after: reference, calendar: .autoupdatingCurrent)
        let timer = Timer(fire: fireDate, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.purge(onlyIfDayChanged: false)
                self?.scheduleMidnight(after: fireDate)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Log.retention.info("다음 정리: \(fireDate, privacy: .public)")
    }

    private func purge(onlyIfDayChanged: Bool) {
        let service = service
        let settings = settings
        let previous = pending
        pending = Task.detached { [weak self] in
            await previous?.value
            do {
                let report = onlyIfDayChanged
                    ? try service.purgeIfDayChanged(using: settings)
                    : try service.purge(using: settings)
                if report != nil { await self?.didPurge() }
            } catch {
                Log.retention.error("정리 실패: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func didPurge() {
        onPurged?()
    }
}
