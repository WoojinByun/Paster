import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let model: SettingsModel
    private var window: NSWindow?

    init(environment: AppEnvironment, updater: UpdaterService, onDataChanged: @escaping () -> Void) {
        model = SettingsModel(environment: environment, updater: updater, onDataChanged: onDataChanged)
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
        let window = SettingsWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
        window.title = "Paster 설정"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        model.hostWindow = window
        return window
    }
}

/// 메인 메뉴가 없어 ⌘W 가 동작하지 않으므로 직접 처리한다.
private final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // 한글 입력 소스에서도 동작하도록 keyCode 13(W) 도 본다
        let isW = event.charactersIgnoringModifiers?.lowercased() == "w" || event.keyCode == 13
        if flags == .command, isW {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
