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
        Self.activateApp()
        window.makeKeyAndOrderFront(nil)
        // 활성화가 거절돼도 창은 다른 앱 창 앞에 보이게 한다
        window.orderFrontRegardless()
    }

    /// NSApp.activate() 는 협조적 활성화라, 메뉴바 메뉴의 ⌘, 처럼 클릭이 아닌 키로 불리면
    /// 시스템이 거절해 창이 frontmost 앱 뒤에 열린다. frontmost 앱에서 넘겨받는 방식으로 먼저 활성화한다.
    private static func activateApp() {
        let current = NSRunningApplication.current
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != current.processIdentifier,
           current.activate(from: frontmost, options: []) {
            return
        }
        NSApp.activate()
    }

    private func makeWindow() -> NSWindow {
        let hostingController = NSHostingController(rootView: SettingsView(model: model))
        let window = SettingsWindow(contentViewController: hostingController)
        window.title = "Paster 설정"
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        // NSHostingController 는 창을 최소 크기로 만든다. grouped Form 은 최소 높이가 0 이라 제목 막대만 남으므로
        // 내용 전체 높이(fittingSize)로 열되, 화면보다 크면 화면 높이에 맞춘다 (넘치는 부분은 Form 이 스크롤)
        let fitting = hostingController.view.fittingSize
        let visibleHeight = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? fitting.height
        let maxContentHeight = window.contentRect(forFrameRect: NSRect(x: 0, y: 0, width: fitting.width, height: visibleHeight)).height
        window.setContentSize(NSSize(width: fitting.width, height: min(fitting.height, maxContentHeight)))
        window.center()
        model.hostWindow = window
        return window
    }
}

/// ⌘W 를 직접 처리한다. 숨은 메인 메뉴에도 ⌘W(performClose:) 가 있지만,
/// 키 창이 메인 메뉴보다 먼저 받으므로 한글 입력 소스에서도 아래 규칙대로 닫힌다.
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
