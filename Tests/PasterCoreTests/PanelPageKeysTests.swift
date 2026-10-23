import Testing
@testable import PasterCore

/// 스펙 8.4절 PageUp / PageDown / Home / End.
struct PanelPageKeysTests {
    func reduce(_ state: PanelState, _ key: PanelKey) -> (PanelState, PanelEffect?) {
        PanelReducer.reduce(state, key)
    }

    func list(_ focus: PanelFocus = .clipboard, clipboard: Int = 30, pinned: Int = 12,
              clipboardIndex: Int = 0, pinnedIndex: Int = 0, pageSize: Int = 10) -> PanelState {
        PanelState(focus: focus, clipboardCount: clipboard, pinnedCount: pinned,
                   clipboardIndex: clipboardIndex, pinnedIndex: pinnedIndex, pageSize: pageSize)
    }

    @Test func defaultPageSizeIsOne() {
        #expect(PanelState().pageSize == 1)
    }

    @Test func pageDownMovesByPageSizeAndStopsAtTheLastItem() {
        var state = list(clipboardIndex: 3)
        var effect: PanelEffect?
        (state, effect) = reduce(state, .pageDown)
        #expect(state.clipboardIndex == 13)
        #expect(effect == nil)
        state = reduce(state, .pageDown).0
        #expect(state.clipboardIndex == 23)
        state = reduce(state, .pageDown).0
        #expect(state.clipboardIndex == 29)
        state = reduce(state, .pageDown).0
        #expect(state.clipboardIndex == 29)
        #expect(state.focus == .clipboard)
    }

    @Test func pageUpMovesByPageSizeAndStopsAtTheFirstItem() {
        var state = list(clipboardIndex: 25)
        state = reduce(state, .pageUp).0
        #expect(state.clipboardIndex == 15)
        state = reduce(state, .pageUp).0
        state = reduce(state, .pageUp).0
        #expect(state.clipboardIndex == 0)
        // 맨 위에서 PageUp 은 ↑ 와 달리 검색창으로 가지 않는다
        let (top, effect) = reduce(state, .pageUp)
        #expect(top.clipboardIndex == 0)
        #expect(top.focus == .clipboard)
        #expect(effect == nil)
    }

    @Test func pageKeysWorkInThePinnedColumn() {
        var state = list(.pinned, pinnedIndex: 1)
        state = reduce(state, .pageDown).0
        #expect(state.pinnedIndex == 11)
        state = reduce(state, .pageDown).0
        #expect(state.pinnedIndex == 11)
        state = reduce(state, .pageUp).0
        #expect(state.pinnedIndex == 1)
        #expect(state.focus == .pinned)
        #expect(state.clipboardIndex == 0)
    }

    @Test func homeAndEndSelectFirstAndLast() {
        var state = list(clipboardIndex: 7)
        state = reduce(state, .end).0
        #expect(state.clipboardIndex == 29)
        state = reduce(state, .home).0
        #expect(state.clipboardIndex == 0)
        #expect(state.focus == .clipboard)

        var pinned = list(.pinned, pinnedIndex: 4)
        pinned = reduce(pinned, .end).0
        #expect(pinned.pinnedIndex == 11)
        pinned = reduce(pinned, .home).0
        #expect(pinned.pinnedIndex == 0)
        #expect(pinned.focus == .pinned)
    }

    @Test func pageSizeOfOneMovesOneRow() {
        var state = list(clipboard: 3, clipboardIndex: 0, pageSize: 1)
        state = reduce(state, .pageDown).0
        #expect(state.clipboardIndex == 1)
        state = reduce(state, .pageDown).0
        state = reduce(state, .pageDown).0
        #expect(state.clipboardIndex == 2)
        state = reduce(state, .pageUp).0
        #expect(state.clipboardIndex == 1)
    }

    @Test func nonPositivePageSizeStillMovesOneRow() {
        let state = reduce(list(clipboardIndex: 5, pageSize: 0), .pageDown).0
        #expect(state.clipboardIndex == 6)
    }

    @Test(arguments: [PanelKey.pageUp, .pageDown, .home, .end])
    func fromSearchFocusMovesToClipboardThenApplies(key: PanelKey) {
        let start = list(.search, clipboardIndex: 15, pinnedIndex: 3)
        let (state, effect) = reduce(start, key)
        #expect(state.focus == .clipboard)
        #expect(effect == nil)
        #expect(state.pinnedIndex == 3)
        let expected: Int = switch key {
        case .pageUp: 5
        case .pageDown: 25
        case .home: 0
        default: 29
        }
        #expect(state.clipboardIndex == expected)
    }

    @Test(arguments: [PanelKey.pageUp, .pageDown, .home, .end])
    func fromSearchFocusMovesToPinnedWhenClipboardIsEmpty(key: PanelKey) {
        let start = list(.search, clipboard: 0, pinnedIndex: 5)
        let (state, effect) = reduce(start, key)
        #expect(state.focus == .pinned)
        #expect(effect == nil)
        let expected: Int = switch key {
        case .pageUp: 0
        case .pageDown: 11
        case .home: 0
        default: 11
        }
        #expect(state.pinnedIndex == expected)
    }

    @Test(arguments: [PanelKey.pageUp, .pageDown, .home, .end])
    func emptyListsDoNothing(key: PanelKey) {
        let search = list(.search, clipboard: 0, pinned: 0)
        let (afterSearch, searchEffect) = reduce(search, key)
        #expect(afterSearch == search)
        #expect(searchEffect == nil)

        // 목록에서 칼럼을 넘나들지 않는다
        let pinnedOnly = list(.pinned, clipboard: 0, pinned: 0)
        #expect(reduce(pinnedOnly, key).0 == pinnedOnly)
    }

    @Test(arguments: [PanelKey.pageUp, .pageDown, .home, .end])
    func pageKeysNeverSwitchColumns(key: PanelKey) {
        let clipboard = list(.clipboard, clipboardIndex: 10, pinnedIndex: 4)
        let next = reduce(clipboard, key).0
        #expect(next.focus == .clipboard)
        #expect(next.pinnedIndex == 4)

        let pinned = list(.pinned, clipboardIndex: 10, pinnedIndex: 4)
        let after = reduce(pinned, key).0
        #expect(after.focus == .pinned)
        #expect(after.clipboardIndex == 10)
    }

    @Test func eachColumnRemembersItsSelection() {
        var state = list(.clipboard)
        state = reduce(state, .pageDown).0      // clipboard 10
        state = reduce(state, .right).0
        state = reduce(state, .end).0           // pinned 11
        state = reduce(state, .left).0
        #expect(state.focus == .clipboard)
        #expect(state.clipboardIndex == 10)
        state = reduce(state, .right).0
        #expect(state.pinnedIndex == 11)
    }

    @Test func pageSizeSurvivesCountsAndQueryChanges() {
        var state = list(pageSize: 7)
        state.updateCounts(clipboard: 3, pinned: 1)
        state.setQuery("abc")
        #expect(state.pageSize == 7)
    }

    @Test(arguments: [
        (300.0, 28.0, 10),   // 꽉 찬 행 10개 + 잘린 행
        (280.0, 28.0, 10),
        (279.9, 28.0, 9),
        (20.0, 28.0, 1),     // 한 행도 다 안 보여도 최소 1
        (300.0, 0.0, 1),     // 아직 행 높이를 모름
        (0.0, 28.0, 1),
    ] as [(Double, Double, Int)])
    func pageSizeFromLayout(visible: Double, row: Double, expected: Int) {
        #expect(PanelState.pageSize(visibleHeight: visible, rowHeight: row) == expected)
    }
}
