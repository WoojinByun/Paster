/// 패널 키 처리 (스펙 8.3, 8.4절). 순수 함수.
/// 반환한 effect 가 nil 이면 이벤트를 소비하고 아무 부수 효과도 없다.
public enum PanelReducer {
    public static func reduce(_ state: PanelState, _ key: PanelKey) -> (PanelState, PanelEffect?) {
        var state = state
        switch key {
        case .escape:
            guard !state.query.isEmpty else { return (state, .close) }
            state.setQuery("")
            state.focus = .search
            return (state, nil)
        case .textInput:
            state.focus = .search
            return (state, .passThrough)
        case .cmdComma:
            return (state, .openSettings)
        case let .click(column, index):
            guard select(&state, column, index) else { return (state, nil) }
            return (state, nil)
        case let .doubleClick(column, index):
            guard select(&state, column, index) else { return (state, nil) }
            return (state, .paste(column, index: index, mode: .formatted))
        default:
            break
        }

        switch state.focus {
        case .search: return reduceSearch(state, key)
        case .clipboard: return reduceList(state, .clipboard, key)
        case .pinned: return reduceList(state, .pinned, key)
        }
    }

    private static func reduceSearch(_ state: PanelState, _ key: PanelKey) -> (PanelState, PanelEffect?) {
        var state = state
        switch key {
        case .down:
            if let column = state.firstNonEmptyColumn { state.focus = column.focus }
            return (state, nil)
        case .pageUp, .pageDown, .home, .end:
            // ↓ 와 같은 규칙으로 목록에 들어간 뒤 그 칼럼에서 키를 적용한다
            guard let column = state.firstNonEmptyColumn else { return (state, nil) }
            state.focus = column.focus
            return reduceList(state, column, key)
        case .up, .left, .right, .cmdDelete:
            // 검색창 안의 커서 이동 · 편집
            return (state, .passThrough)
        case .enter:
            return paste(state, .clipboard, state.clipboardIndex, .formatted)
        case .shiftEnter:
            return paste(state, .clipboard, state.clipboardIndex, .plainText)
        case .cmdEnter:
            return paste(state, .clipboard, state.clipboardIndex, .copyOnly)
        case let .cmdNumber(number):
            return paste(state, .clipboard, number - 1, .formatted)
        case .cmdP, .optCmdUp, .optCmdDown:
            return (state, nil)
        case .escape, .textInput, .cmdComma, .click, .doubleClick:
            return (state, nil)
        }
    }

    private static func reduceList(_ state: PanelState, _ column: PanelColumn, _ key: PanelKey) -> (PanelState, PanelEffect?) {
        var state = state
        let index = state.selectedIndex(in: column)
        let count = state.count(of: column)
        switch key {
        case .up:
            if index == 0 {
                state.focus = .search
            } else {
                state.setIndex(index - 1, in: column)
            }
            return (state, nil)
        case .down:
            if index + 1 < count { state.setIndex(index + 1, in: column) }
            return (state, nil)
        case .pageUp, .pageDown, .home, .end:
            // ↑ 와 달리 맨 위에서도 검색창으로 가지 않고, 칼럼도 넘나들지 않는다
            guard count > 0 else { return (state, nil) }
            let page = max(state.pageSize, 1)
            let target = switch key {
            case .pageUp: index - page
            case .pageDown: index + page
            case .home: 0
            default: count - 1
            }
            state.setIndex(min(max(target, 0), count - 1), in: column)
            return (state, nil)
        case .left:
            if column == .pinned, state.clipboardCount > 0 { state.focus = .clipboard }
            return (state, nil)
        case .right:
            if column == .clipboard, state.pinnedCount > 0 { state.focus = .pinned }
            return (state, nil)
        case .enter:
            return paste(state, column, index, .formatted)
        case .shiftEnter:
            return paste(state, column, index, .plainText)
        case .cmdEnter:
            return paste(state, column, index, .copyOnly)
        case let .cmdNumber(number):
            return paste(state, column, number - 1, .formatted)
        case .cmdP:
            guard index < count else { return (state, nil) }
            return (state, .togglePin(column, index: index))
        case .optCmdUp:
            // 검색 중에는 걸러진 목록과 실제 순서가 달라 엉뚱한 이웃과 바뀌므로 막는다
            guard column == .pinned, state.query.isEmpty, index > 0, index < count else { return (state, nil) }
            state.setIndex(index - 1, in: column)
            return (state, .movePinned(index: index, direction: .up))
        case .optCmdDown:
            guard column == .pinned, state.query.isEmpty, index + 1 < count else { return (state, nil) }
            state.setIndex(index + 1, in: column)
            return (state, .movePinned(index: index, direction: .down))
        case .cmdDelete:
            guard index < count else { return (state, nil) }
            return (state, .delete(column, index: index))
        case .escape, .textInput, .cmdComma, .click, .doubleClick:
            return (state, nil)
        }
    }

    private static func paste(_ state: PanelState, _ column: PanelColumn, _ index: Int, _ mode: PasteMode) -> (PanelState, PanelEffect?) {
        guard index >= 0, index < state.count(of: column) else { return (state, nil) }
        return (state, .paste(column, index: index, mode: mode))
    }

    private static func select(_ state: inout PanelState, _ column: PanelColumn, _ index: Int) -> Bool {
        guard index >= 0, index < state.count(of: column) else { return false }
        state.focus = column.focus
        state.setIndex(index, in: column)
        return true
    }
}
