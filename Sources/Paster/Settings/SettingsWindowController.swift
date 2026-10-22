import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let model: SettingsModel
    private var window: NSWindow?

    init(environment: AppEnvironment, onDataChanged: @escaping () -> Void) {
        model = SettingsModel(environment: environment, onDataChanged: onDataChanged)
    }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        model.refresh()
        // 메뉴바 앱이라 직접 활성화해야 창이 앞으로 나온다
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
        window.title = "Paster 설정"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        model.hostWindow = window
        return window
    }
}
