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
        // capsLock 등은 무시하고 ⌘ 계열 4개 수정자만 비교한다
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        // 글자(ASCII)로 먼저 판별해 Dvorak 등 배열을 따른다.
        // 한글 등 ASCII 가 아닌 입력 소스일 때만 keyCode 13(W) 으로 판별한다 (PanelController 의 편집 단축키와 같은 규칙)
        let isW: Bool
        if let characters = event.charactersIgnoringModifiers, !characters.isEmpty, characters.allSatisfy(\.isASCII) {
            isW = characters.lowercased() == "w"
        } else {
            isW = event.keyCode == 13
        }
        if flags == .command, isW {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
