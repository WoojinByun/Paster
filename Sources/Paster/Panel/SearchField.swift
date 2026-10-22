import AppKit
import SwiftUI

/// AppKit 검색창. 키 라우팅 중 동기적으로 first responder 를 다루기 위해 NSTextField 를 직접 쓴다.
/// 글자는 model.state.query 에 묶인다 (입력 → queryChanged, 상태 변경 → updateNSView).
struct SearchField: NSViewRepresentable {
    let model: PanelModel

    func makeNSView(context: Context) -> NSTextField {
        let field = FocusingTextField()
        field.placeholderString = "검색"
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 18)
        field.delegate = context.coordinator
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.stringValue = model.state.query
        model.searchField = field
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        let query = model.state.query
        // IME 조합 중에는 건드리지 않는다
        if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() { return }
        if field.stringValue != query { field.stringValue = query }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    /// 창에 붙는 즉시 first responder 가 된다 (패널을 처음 열 때).
    final class FocusingTextField: NSTextField {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: PanelModel

        init(model: PanelModel) {
            self.model = model
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            model.queryChanged(field.stringValue)
        }
    }
}
