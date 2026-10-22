import Testing
@testable import PasterCore

/// 스펙 8.4절 키 표.
struct PanelActionTests {
    let search = PanelState(focus: .search, clipboardCount: 3, pinnedCount: 2, clipboardIndex: 1)
    let clipboard = PanelState(focus: .clipboard, clipboardCount: 3, pinnedCount: 2, clipboardIndex: 2)
    let pinned = PanelState(focus: .pinned, clipboardCount: 3, pinnedCount: 3, pinnedIndex: 1)

    func effect(_ state: PanelState, _ key: PanelKey) -> PanelEffect? {
        PanelReducer.reduce(state, key).1
    }

    // Enter / ⇧Enter / ⌘Enter

    @Test func enterPastesFocusedSelectionFormatted() {
        #expect(effect(clipboard, .enter) == .paste(.clipboard, index: 2, mode: .formatted))
        #expect(effect(pinned, .enter) == .paste(.pinned, index: 1, mode: .formatted))
    }

    @Test func enterInSearchPastesClipboardSelection() {
        #expect(effect(search, .enter) == .paste(.clipboard, index: 1, mode: .formatted))
    }

    @Test func shiftEnterPastesPlainText() {
        #expect(effect(clipboard, .shiftEnter) == .paste(.clipboard, index: 2, mode: .plainText))
        #expect(effect(search, .shiftEnter) == .paste(.clipboard, index: 1, mode: .plainText))
    }

    @Test func cmdEnterCopiesOnly() {
        #expect(effect(pinned, .cmdEnter) == .paste(.pinned, index: 1, mode: .copyOnly))
        #expect(effect(search, .cmdEnter) == .paste(.clipboard, index: 1, mode: .copyOnly))
    }

    @Test func enterWithNothingToPasteDoesNothing() {
        #expect(effect(PanelState(), .enter) == nil)
    }

    @Test func doubleClickSelectsAndPastes() {
        let (state, effect) = PanelReducer.reduce(search, .doubleClick(.pinned, 0))
        #expect(effect == .paste(.pinned, index: 0, mode: .formatted))
        #expect(state.focus == .pinned)
        #expect(state.pinnedIndex == 0)
    }

    // ⌘1~9

    @Test func cmdNumberPastesNthItemOfFocusedColumn() {
        #expect(effect(clipboard, .cmdNumber(1)) == .paste(.clipboard, index: 0, mode: .formatted))
        #expect(effect(pinned, .cmdNumber(3)) == .paste(.pinned, index: 2, mode: .formatted))
    }

    @Test func cmdNumberInSearchUsesClipboard() {
        #expect(effect(search, .cmdNumber(2)) == .paste(.clipboard, index: 1, mode: .formatted))
    }

    @Test func cmdNumberBeyondCountDoesNothing() {
        #expect(effect(clipboard, .cmdNumber(4)) == nil)
        #expect(effect(search, .cmdNumber(9)) == nil)
    }

    // ⌘P

    @Test func cmdPTogglesPinOfSelection() {
        #expect(effect(clipboard, .cmdP) == .togglePin(.clipboard, index: 2))
        #expect(effect(pinned, .cmdP) == .togglePin(.pinned, index: 1))
    }

    @Test func cmdPInSearchDoesNothing() {
        #expect(PanelReducer.reduce(search, .cmdP) == (search, nil))
    }

    // ⌥⌘↑ / ↓

    @Test func optCmdArrowsReorderPinnedAndFollowTheItem() {
        let (up, upEffect) = PanelReducer.reduce(pinned, .optCmdUp)
        #expect(upEffect == .movePinned(index: 1, direction: .up))
        #expect(up.pinnedIndex == 0)

        let (down, downEffect) = PanelReducer.reduce(pinned, .optCmdDown)
        #expect(downEffect == .movePinned(index: 1, direction: .down))
        #expect(down.pinnedIndex == 2)
    }

    @Test func optCmdArrowsStopAtEdges() {
        var top = pinned
        top.pinnedIndex = 0
        #expect(effect(top, .optCmdUp) == nil)
        var bottom = pinned
        bottom.pinnedIndex = 2
        #expect(effect(bottom, .optCmdDown) == nil)
    }

    @Test func optCmdArrowsOnlyWorkInPinned() {
        #expect(effect(clipboard, .optCmdUp) == nil)
        #expect(effect(search, .optCmdDown) == nil)
    }

    // ⌘⌫

    @Test func cmdDeleteDeletesSelection() {
        #expect(effect(clipboard, .cmdDelete) == .delete(.clipboard, index: 2))
        #expect(effect(pinned, .cmdDelete) == .delete(.pinned, index: 1))
    }

    @Test func cmdDeleteInSearchEditsText() {
        #expect(effect(search, .cmdDelete) == .passThrough)
    }

    // Esc

    @Test func escapeClearsQueryFirst() {
        var state = clipboard
        state.query = "abc"
        let (next, effect) = PanelReducer.reduce(state, .escape)
        #expect(next.query == "")
        #expect(next.focus == .search)
        #expect(next.clipboardIndex == 0)
        #expect(effect == nil)
    }

    @Test func escapeWithEmptyQueryCloses() {
        #expect(effect(search, .escape) == .close)
        #expect(effect(pinned, .escape) == .close)
    }
}
