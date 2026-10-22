import AppKit
import PasterCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var environment: AppEnvironment?
    private var monitor: ClipboardMonitor?
    private var scheduler: RetentionScheduler?
    private var panelController: PanelController?
    private var settingsWindow: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment: AppEnvironment
        do {
            environment = try AppEnvironment()
        } catch {
            Log.app.fault("저장소를 열 수 없음: \(String(describing: error), privacy: .public)")
            // 다른 인스턴스가 DB 를 잡고 있는 경우 등. 크래시 대신 알리고 종료한다
            let alert = NSAlert()
            alert.messageText = "Paster를 시작할 수 없습니다"
            alert.informativeText = "데이터베이스를 열 수 없습니다. Paster가 이미 실행 중인지 확인해 주세요."
            // .accessory 앱이라 활성화하지 않으면 알림이 다른 창 뒤에 숨을 수 있다
            NSApp.activate()
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        self.environment = environment

        let panelController = PanelController(environment: environment)
        self.panelController = panelController

        let monitor = ClipboardMonitor(store: environment.store, settings: environment.settings)
        monitor.onSaved = { [weak panelController] in panelController?.reloadIfVisible() }
        monitor.start()
        self.monitor = monitor

        let scheduler = RetentionScheduler(service: environment.retention, settings: environment.settings)
        scheduler.onPurged = { [weak panelController] in panelController?.reloadIfVisible() }
        scheduler.start()
        self.scheduler = scheduler

        settingsWindow = SettingsWindowController(environment: environment) { [weak panelController] in
            panelController?.reloadIfVisible()
        }

        HotkeyService.register { [weak panelController] in panelController?.toggle() }
        AccessibilityPermission.requestOnFirstLaunch()
        statusItem = makeStatusItem()
    }

    // MARK: 메뉴바

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: "Paster")
        item.menu = makeMenu()
        return item
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let open = NSMenuItem(title: "Paster 열기", action: #selector(openPanel), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let version = NSMenuItem(title: Self.versionTitle, action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "설정…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())
        menu.addItem(makeUpdateMenuItem())

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        return menu
    }

    /// Sparkle 연결 전까지는 비활성 항목이다 (플랜 3 에서 연결).
    private func makeUpdateMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "업데이트 확인…", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    static var versionTitle: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "Paster \(short) (\(build))"
    }

    @objc private func openPanel() {
        panelController?.show()
    }

    @objc private func openSettings() {
        settingsWindow?.show()
    }
}
