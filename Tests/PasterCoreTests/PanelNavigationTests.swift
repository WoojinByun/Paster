import Testing
@testable import PasterCore

/// 스펙 8.3절 포커스 이동 규칙.
struct PanelNavigationTests {
    let base = PanelState(clipboardCount: 3, pinnedCount: 2)

    func reduce(_ state: PanelState, _ key: PanelKey) -> (PanelState, PanelEffect?) {
        PanelReducer.reduce(state, key)
    }

    @Test func opensWithSearchFocused() {
        #expect(PanelState().focus == .search)
    }

    @Test func downFromSearchGoesToClipboard() {
        let (state, effect) = reduce(base, .down)
        #expect(state.focus == .clipboard)
        #expect(state.clipboardIndex == 0)
        #expect(effect == nil)
    }

    @Test func downFromSearchGoesToPinnedWhenClipboardIsEmpty() {
        var empty = base
        empty.clipboardCount = 0
        #expect(reduce(empty, .down).0.focus == .pinned)
        empty.pinnedCount = 0
        #expect(reduce(empty, .down).0.focus == .search)
    }

    @Test func arrowsInsideSearchMoveTheCursorOnly() {
        for key in [PanelKey.left, .right, .up] {
            let (state, effect) = reduce(base, key)
            #expect(state == base)
            #expect(effect == .passThrough)
        }
    }

    @Test func downAndUpMoveWithinColumn() {
        var state = PanelState(focus: .clipboard, clipboardCount: 3, pinnedCount: 2)
        state = reduce(state, .down).0
        state = reduce(state, .down).0
        #expect(state.clipboardIndex == 2)
        state = reduce(state, .down).0
        #expect(state.clipboardIndex == 2) // 맨 아래에서 멈춤
        state = reduce(state, .up).0
        #expect(state.clipboardIndex == 1)
        #expect(state.focus == .clipboard)
    }

    @Test func upFromTopOfEitherColumnGoesToSearch() {
        let fromClipboard = reduce(PanelState(focus: .clipboard, clipboardCount: 3, pinnedCount: 2), .up).0
        #expect(fromClipboard.focus == .search)
        let fromPinned = reduce(PanelState(focus: .pinned, clipboardCount: 3, pinnedCount: 2), .up).0
        #expect(fromPinned.focus == .search)
    }

    @Test func leftRightSwitchColumns() {
        let start = PanelState(focus: .clipboard, clipboardCount: 3, pinnedCount: 2)
        let right = reduce(start, .right).0
        #expect(right.focus == .pinned)
        let left = reduce(right, .left).0
        #expect(left.focus == .clipboard)
    }

    @Test func leftInLeftColumnAndRightInRightColumnDoNothing() {
        let clipboard = PanelState(focus: .clipboard, clipboardCount: 3, pinnedCount: 2, clipboardIndex: 1)
        let (afterLeft, leftEffect) = reduce(clipboard, .left)
        #expect(afterLeft == clipboard)
        #expect(leftEffect == nil)

        let pinned = PanelState(focus: .pinned, clipboardCount: 3, pinnedCount: 2, pinnedIndex: 1)
        let (afterRight, rightEffect) = reduce(pinned, .right)
        #expect(afterRight == pinned)
        #expect(rightEffect == nil)
    }

    @Test func switchingToAnEmptyColumnDoesNothing() {
        let state = PanelState(focus: .clipboard, clipboardCount: 3, pinnedCount: 0)
        #expect(reduce(state, .right).0.focus == .clipboard)
    }

    @Test func eachColumnRemembersItsSelection() {
        var state = PanelState(focus: .clipboard, clipboardCount: 3, pinnedCount: 2)
        state = reduce(state, .down).0
        state = reduce(state, .down).0      // clipboard 2
        state = reduce(state, .right).0
        state = reduce(state, .down).0      // pinned 1
        state = reduce(state, .left).0
        #expect(state.focus == .clipboard)
        #expect(state.clipboardIndex == 2)
        state = reduce(state, .right).0
        #expect(state.pinnedIndex == 1)
    }

    @Test func typingInAListReturnsToSearchAndForwardsTheKey() {
        let state = PanelState(focus: .pinned, clipboardCount: 3, pinnedCount: 2, pinnedIndex: 1)
        let (next, effect) = reduce(state, .textInput)
        #expect(next.focus == .search)
        #expect(next.pinnedIndex == 1)
        #expect(effect == .passThrough)
    }

    @Test func typingInSearchPassesThrough() {
        #expect(reduce(base, .textInput) == (base, .passThrough))
    }

    @Test func activeColumnIsClipboardWhileSearching() {
        #expect(base.activeColumn == .clipboard)
        #expect(PanelState(focus: .pinned, pinnedCount: 1).activeColumn == .pinned)
        #expect(PanelState(focus: .search).activeIndex == nil)
        #expect(PanelState(focus: .search, clipboardCount: 2, clipboardIndex: 1).activeIndex == 1)
    }

    @Test func updateCountsClampsSelectionAndMovesFocusOutOfEmptyColumns() {
        var state = PanelState(focus: .pinned, clipboardCount: 5, pinnedCount: 1, clipboardIndex: 4, pinnedIndex: 0)
        state.updateCounts(clipboard: 2, pinned: 0)
        #expect(state.clipboardIndex == 1)
        #expect(state.focus == .clipboard)
        state.updateCounts(clipboard: 0, pinned: 0)
        #expect(state.focus == .search)
        #expect(state.clipboardIndex == 0)
    }

    @Test func setQueryResetsSelections() {
        var state = PanelState(focus: .search, clipboardCount: 5, pinnedCount: 3, clipboardIndex: 4, pinnedIndex: 2)
        state.setQuery("abc")
        #expect(state.query == "abc")
        #expect(state.clipboardIndex == 0)
        #expect(state.pinnedIndex == 0)
    }

    @Test func clickSelectsAndFocusesColumn() {
        let (state, effect) = reduce(base, .click(.pinned, 1))
        #expect(state.focus == .pinned)
        #expect(state.pinnedIndex == 1)
        #expect(effect == nil)
        #expect(reduce(base, .click(.pinned, 5)).0 == base)
    }
}
