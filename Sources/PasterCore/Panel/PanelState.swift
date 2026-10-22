/// 패널의 두 칼럼.
public enum PanelColumn: Equatable, Sendable {
    case clipboard
    case pinned

    var focus: PanelFocus {
        switch self {
        case .clipboard: .clipboard
        case .pinned: .pinned
        }
    }
}

/// 키보드 포커스 위치.
public enum PanelFocus: Equatable, Sendable {
    case search
    case clipboard
    case pinned
}

/// 붙여넣기 방식.
public enum PasteMode: Equatable, Sendable {
    /// Enter: 서식 유지
    case formatted
    /// ⇧Enter: 일반 텍스트
    case plainText
    /// ⌘Enter: 복사만
    case copyOnly
}

/// 패널의 포커스 · 선택 상태. 항목 자체가 아니라 개수와 위치만 가진다.
public struct PanelState: Equatable, Sendable {
    public var focus: PanelFocus
    public var query: String
    public var clipboardCount: Int
    public var pinnedCount: Int
    /// 칼럼별 마지막 선택 위치
    public var clipboardIndex: Int
    public var pinnedIndex: Int

    public init(
        focus: PanelFocus = .search,
        query: String = "",
        clipboardCount: Int = 0,
        pinnedCount: Int = 0,
        clipboardIndex: Int = 0,
        pinnedIndex: Int = 0
    ) {
        self.focus = focus
        self.query = query
        self.clipboardCount = clipboardCount
        self.pinnedCount = pinnedCount
        self.clipboardIndex = clipboardIndex
        self.pinnedIndex = pinnedIndex
    }

    /// ⌘숫자 힌트 · 미리보기 · Enter 의 대상 칼럼. 검색창 포커스면 Clipboard.
    public var activeColumn: PanelColumn {
        focus == .pinned ? .pinned : .clipboard
    }

    /// 대상 칼럼의 선택 위치. 칼럼이 비어 있으면 nil.
    public var activeIndex: Int? {
        count(of: activeColumn) > 0 ? selectedIndex(in: activeColumn) : nil
    }

    public func count(of column: PanelColumn) -> Int {
        switch column {
        case .clipboard: clipboardCount
        case .pinned: pinnedCount
        }
    }

    public func selectedIndex(in column: PanelColumn) -> Int {
        switch column {
        case .clipboard: clipboardIndex
        case .pinned: pinnedIndex
        }
    }

    mutating func setIndex(_ index: Int, in column: PanelColumn) {
        switch column {
        case .clipboard: clipboardIndex = index
        case .pinned: pinnedIndex = index
        }
    }

    /// 목록을 다시 읽은 뒤 호출한다. 선택을 범위 안으로 맞추고, 비어 버린 칼럼에서 포커스를 옮긴다.
    public mutating func updateCounts(clipboard: Int, pinned: Int) {
        clipboardCount = clipboard
        pinnedCount = pinned
        clipboardIndex = min(clipboardIndex, max(clipboard - 1, 0))
        pinnedIndex = min(pinnedIndex, max(pinned - 1, 0))
        switch focus {
        case .clipboard where clipboard == 0:
            focus = pinned > 0 ? .pinned : .search
        case .pinned where pinned == 0:
            focus = clipboard > 0 ? .clipboard : .search
        default:
            break
        }
    }

    /// 다시 읽은 목록에서 이전 선택 항목의 새 위치로 선택을 옮긴다. `updateCounts` 다음에 호출한다.
    /// nil 이거나 범위를 벗어난 위치는 무시하고 기존(범위로 맞춘) 선택을 둔다.
    public mutating func reselect(clipboardIndex: Int?, pinnedIndex: Int?) {
        if let clipboardIndex, clipboardIndex >= 0, clipboardIndex < clipboardCount {
            self.clipboardIndex = clipboardIndex
        }
        if let pinnedIndex, pinnedIndex >= 0, pinnedIndex < pinnedCount {
            self.pinnedIndex = pinnedIndex
        }
    }

    /// 검색어가 바뀌면 결과가 달라지므로 두 칼럼의 선택을 맨 위로 되돌린다.
    public mutating func setQuery(_ newQuery: String) {
        guard newQuery != query else { return }
        query = newQuery
        clipboardIndex = 0
        pinnedIndex = 0
    }
}
