import AppKit
import Sparkle

/// Sparkle 업데이트 (스펙 13절).
@MainActor
final class UpdaterService: NSObject {
    static let checkTitle = "업데이트 확인…"
    static let pendingTitle = "업데이트 설치 가능…"

    private(set) var controller: SPUStandardUpdaterController!
    /// 예약 확인에서 찾은 업데이트를 바로 띄우지 않았을 때 (메뉴바 앱이라 창이 뒤에 묻힌다).
    var onUpdateAvailable: (() -> Void)?
    /// 사용자가 업데이트를 봤거나 업데이트 세션이 끝났을 때.
    var onUpdateAttended: (() -> Void)?
    private var menuItems: [NSMenuItem] = []
    private var canCheckObservation: NSKeyValueObservation?

    override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        // 기본값 ON. 한 번도 정한 적 없으면 켜 두어 Sparkle 의 허락 요청 창을 생략한다.
        if UserDefaults.standard.object(forKey: "SUEnableAutomaticChecks") == nil {
            controller.updater.automaticallyChecksForUpdates = true
        }
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            let canCheck = change.newValue ?? false
            Task { @MainActor in
                self?.menuItems.forEach { $0.isEnabled = canCheck }
            }
        }
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func makeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: Self.checkTitle,
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        item.target = controller
        item.isEnabled = controller.updater.canCheckForUpdates
        menuItems.append(item)
        return item
    }
}

// MARK: 부드러운 예약 업데이트 알림

extension UpdaterService: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// 앱이 막 실행돼 초점이 있을 때만 Sparkle 이 직접 띄운다. 그 밖에는 메뉴바 배지로 알린다.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard !state.userInitiated, !handleShowingUpdate else { return }
        MainActor.assumeIsolated { onUpdateAvailable?() }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { onUpdateAttended?() }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated { onUpdateAttended?() }
    }
}
