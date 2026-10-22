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
    /// 마지막으로 처리한 폴링 이후 한 번이라도 앞에 있었던 앱들 (그때 앞에 있던 앱 포함).
    /// 복사 후 폴링 전에 다른 앱으로 넘어가도 제외 앱의 복사를 놓치지 않기 위해 쓴다
    private var recentBundleIDs: Set<String> = []
    private var activationObserver: NSObjectProtocol?

    var onSaved: (() -> Void)?

    init(store: ClipStore, settings: PasterSettings, pasteboard: NSPasteboard = .general) {
        self.store = store
        self.settings = settings
        self.pasteboard = pasteboard
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        resetRecentApps()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            MainActor.assumeIsolated {
                if let bundleID { self?.recentBundleIDs.insert(bundleID) }
            }
        }
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
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    private func resetRecentApps() {
        recentBundleIDs = []
        if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            recentBundleIDs.insert(bundleID)
        }
    }

    private func poll() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }

        let now = Date()
        let frontmost = NSWorkspace.shared.frontmostApplication
        var source = SourceApp(bundleID: frontmost?.bundleIdentifier, name: frontmost?.localizedName)
        let capture = settings.makeCapture()
        // 복사한 앱을 알 수 없으니, 지난 폴링 이후 앞에 있었던 앱 중 하나라도 제외 앱이면 제외한다.
        // 내용은 읽지 않고, 출처를 그 제외 앱으로 두어 ClipCapture 가 excludedApp 을 돌려주게 한다
        var candidates = recentBundleIDs
        if let bundleID = source.bundleID { candidates.insert(bundleID) }
        let excludedID = candidates.sorted().first(where: capture.excludedBundleIDs.contains)
        if let excludedID, excludedID != source.bundleID {
            source = SourceApp(bundleID: excludedID, name: nil)
        }
        let isExcluded = excludedID != nil
        let snapshot = PasteboardReader.snapshot(of: pasteboard, readContent: !isExcluded)
        // 읽는 도중 다른 앱이 썼다면 타입과 내용이 섞였을 수 있다. 버리고 다음 폴링에서 다시 읽는다
        guard pasteboard.changeCount == changeCount else {
            Log.capture.debug("읽는 중 changeCount 가 바뀌어 버림")
            return
        }
        // clearContents 없이 마커만 덧붙이면 changeCount 가 그대로라 타입을 다시 확인한다
        if !PasteboardReader.hasSkipMarker(snapshot.types),
           PasteboardReader.hasSkipMarker(PasteboardReader.types(of: pasteboard)) {
            Log.capture.debug("읽는 중 건너뜀 마커가 붙어 버림")
            return
        }
        lastChangeCount = changeCount
        resetRecentApps()

        let store = store
        let previous = pending
        pending = Task.detached(priority: .utility) { [weak self] in
            await previous?.value
            guard case let .captured(clip) = capture.capture(snapshot, source: source) else { return }
            do {
                try store.save(clip, now: now)
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
