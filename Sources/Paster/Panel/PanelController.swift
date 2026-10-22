import AppKit
import PasterCore
import SwiftUI

/// 패널 열기 / 닫기, 키 라우팅, effect 실행.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let environment: AppEnvironment
    private let model: PanelModel
    private let pasteService: PasteService
    private lazy var panel: PasterPanel = makePanel()
    private var keyMonitor: Any?
    /// 패널을 열기 직전의 frontmost 앱. 붙여넣기 대상.
    private var previousApp: NSRunningApplication?
    /// orderOut → windowDidResignKey → close() 재진입 방지
    private var isClosing = false

    init(environment: AppEnvironment) {
        self.environment = environment
        model = PanelModel(store: environment.store, settings: environment.settings)
        pasteService = PasteService(store: environment.store)
        super.init()
        model.effectHandler = { [weak self] effect in self?.perform(effect) }
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        isVisible ? close() : show()
    }

    func show() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        // 자기 자신이 frontmost 면 예전 대상을 쓰지 않는다
        previousApp = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost
        model.resetForOpen()
        panel.centerOnMouseScreen()
        panel.makeKeyAndOrderFront(nil)
        // 처음 열 때는 SwiftUI 가 아직 검색창을 만들지 않았을 수 있어 먼저 배치한다
        panel.contentView?.layoutSubtreeIfNeeded()
        if let field = model.searchField { panel.makeFirstResponder(field) }
        installKeyMonitor()
    }

    func close() {
        guard !isClosing else { return }
        isClosing = true
        defer { isClosing = false }
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    func reloadIfVisible() {
        guard isVisible else { return }
        model.reload()
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        // 바깥을 클릭하면 닫는다
        close()
    }

    // MARK: 키 라우팅

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        // 로컬 모니터는 메인 스레드에서 불린다
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handleKeyDown(event)
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard event.window === panel else { return event }
        // 한글 등 IME 조합 중에는 Enter · Esc · 화살표까지 모두 검색창(field editor)에 맡긴다
        if isComposingText { return event }
        let modifiers = KeyModifiers(event.modifierFlags)
        // 메인 메뉴가 없는 앱이라 ⌘C/⌘V 등 편집 단축키를 직접 보낸다
        if modifiers == .command, let action = Self.editAction(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers) {
            if model.state.focus != .search {
                // 목록 포커스의 ⌘C 는 선택 항목 복사 (⌘Enter 와 같은 경로)
                if action == #selector(NSText.copy(_:)) {
                    model.send(.cmdEnter)
                    return nil
                }
                // 그 밖의 편집 단축키는 먼저 검색창으로 돌아간다
                model.send(.textInput)
            }
            focusSearchField()
            NSApp.sendAction(action, to: nil, from: nil)
            return nil
        }
        guard let key = PanelKeyMapper.key(
            keyCode: event.keyCode,
            modifiers: modifiers,
            characters: event.charactersIgnoringModifiers
        ) else { return event }

        let effect = model.send(key)
        if effect == .passThrough {
            focusSearchField()
            return event
        }
        return nil
    }

    /// 검색창이 항상 first responder 이지만, 혹시 잃었으면 되돌린다.
    /// 되돌릴 때 전체 선택이 되므로 커서를 끝으로 옮겨 이어서 입력되게 한다.
    private func focusSearchField() {
        guard let field = model.searchField, panel.firstResponder !== field.currentEditor() else { return }
        panel.makeFirstResponder(field)
        if let editor = field.currentEditor() {
            editor.selectedRange = NSRange(location: (editor.string as NSString).length, length: 0)
        }
    }

    /// 검색창 field editor 에 조합 중인 글자가 있는지.
    private var isComposingText: Bool {
        guard let field = model.searchField else { return false }
        let editor = field.currentEditor() ?? panel.fieldEditor(false, for: field)
        return (editor as? NSTextView)?.hasMarkedText() ?? false
    }

    /// 글자(ASCII)로 먼저 판별해 Dvorak 등 배열을 따른다.
    /// 한글 등 ASCII 가 아닌 입력 소스일 때만 키 코드(kVK_ANSI_*)로 판별한다.
    private static func editAction(keyCode: UInt16, characters: String?) -> Selector? {
        let letter: String?
        if let characters, !characters.isEmpty, characters.allSatisfy(\.isASCII) {
            letter = characters.lowercased()
        } else {
            letter = [7: "x", 8: "c", 9: "v", 0: "a", 6: "z"][keyCode]
        }
        switch letter {
        case "x": return #selector(NSText.cut(_:))
        case "c": return #selector(NSText.copy(_:))
        case "v": return #selector(NSText.paste(_:))
        case "a": return #selector(NSText.selectAll(_:))
        case "z": return Selector(("undo:"))
        default: return nil
        }
    }

    // MARK: effect

    private func perform(_ effect: PanelEffect) {
        let store = environment.store
        do {
            switch effect {
            case .passThrough:
                return
            case .close:
                close()
            case let .paste(column, index, mode):
                guard let item = model.item(column, index) else { return }
                paste(item, mode: mode)
            case let .togglePin(column, index):
                guard let id = model.item(column, index)?.id else { return }
                if column == .clipboard {
                    try store.pin(id: id, now: Date())
                } else {
                    try store.unpin(id: id, now: Date())
                }
                model.reload()
            case let .movePinned(index, direction):
                guard let id = model.item(.pinned, index)?.id else { return }
                try store.movePinned(id: id, direction: direction)
                model.reload()
            case let .delete(column, index):
                guard let id = model.item(column, index)?.id else { return }
                try store.delete(id: id)
                model.reload()
            }
        } catch {
            Log.app.error("패널 동작 실패: \(String(describing: error), privacy: .public)")
            // 실패해도 화면은 DB 상태를 따라가게 한다
            model.reload()
        }
    }

    private func paste(_ item: ClipItem, mode: PasteMode) {
        // 원본 없음은 패널을 닫지 않고 안내만 한다
        switch pasteService.write(item, mode: mode) {
        case .missingFiles:
            model.message = .missingFiles
            return
        case .missingImage:
            model.message = .missingImage
            return
        case .written:
            break
        }
        if mode == .copyOnly {
            close()
            return
        }
        guard AccessibilityPermission.isTrusted else {
            // 권한이 없으면 복사만 하고 안내 + "시스템 설정 열기"
            model.message = .needsAccessibility
            model.reload()
            return
        }
        let target = previousApp
        close()
        Task { await pasteService.activateAndPaste(into: target) }
    }

    // MARK: 패널 생성

    private func makePanel() -> PasterPanel {
        let panel = PasterPanel()
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: PanelView(model: model))
        return panel
    }
}
