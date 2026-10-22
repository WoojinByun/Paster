import AppKit
import PasterCore

/// changeCount 를 0.5초마다 확인하고, 바뀌면 캡처해 저장한다.
@MainActor
final class ClipboardMonitor {
    static let interval: TimeInterval = 0.5

    private let store: ClipStore
    private let settings: PasterSettings
    private let pasteboard: NSPasteboard
    private var lastChangeCount: Int
    private var timer: Timer?
    /// 저장을 순서대로 처리하기 위한 마지막 작업
    private var pending: Task<Void, Never>?

    var onSaved: (() -> Void)?

    init(store: ClipStore, settings: PasterSettings, pasteboard: NSPasteboard = .general) {
        self.store = store
        self.settings = settings
        self.pasteboard = pasteboard
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.1
        // 메뉴가 열려 있는 동안에도 돌도록 common 모드에 넣는다
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        let snapshot = PasteboardReader.snapshot(of: pasteboard)
        let frontmost = NSWorkspace.shared.frontmostApplication
        let source = SourceApp(bundleID: frontmost?.bundleIdentifier, name: frontmost?.localizedName)
        let capture = settings.makeCapture()
        let store = store
        let previous = pending
        pending = Task.detached(priority: .utility) { [weak self] in
            await previous?.value
            guard case let .captured(clip) = capture.capture(snapshot, source: source) else { return }
            do {
                try store.save(clip, now: Date())
            } catch {
                Log.capture.error("저장 실패: \(String(describing: error), privacy: .public)")
                return
            }
            await self?.didSave()
        }
    }

    private func didSave() {
        onSaved?()
    }
}
