import AppKit
import Sparkle

/// Sparkle 업데이트 (스펙 13절).
@MainActor
final class UpdaterService {
    let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        // 기본값 ON. 한 번도 정한 적 없으면 켜 두어 Sparkle 의 허락 요청 창을 생략한다.
        if UserDefaults.standard.object(forKey: "SUEnableAutomaticChecks") == nil {
            controller.updater.automaticallyChecksForUpdates = true
        }
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func makeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: "업데이트 확인…",
            action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        item.target = controller
        return item
    }
}
