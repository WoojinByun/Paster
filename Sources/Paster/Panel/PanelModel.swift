import AppKit
import Observation
import PasterCore

/// 패널 하단에 띄우는 안내.
enum PanelMessage: Equatable {
    case missingFiles
    case missingImage
    case needsAccessibility

    var text: String {
        switch self {
        case .missingFiles: "원본 파일이 없습니다"
        case .missingImage: "이미지 파일을 찾을 수 없습니다"
        case .needsAccessibility: "손쉬운 사용 권한이 없어 복사만 했습니다. ⌘V 로 붙여넣으세요."
        }
    }
}

/// 패널 화면 상태. 키 처리는 PanelReducer 에 맡긴다.
@MainActor
@Observable
final class PanelModel {
    var state = PanelState()
    /// 목록 투영(`ClipStore.fetchUnpinned` 참고). 붙여넣기 · 미리보기는 `fullItem` 으로 전체를 다시 읽는다
    private(set) var clipboardItems: [ClipItem] = []
    private(set) var pinnedItems: [ClipItem] = []
    /// 원본 파일이 하나라도 없는 파일 항목. 행마다 파일 시스템을 보지 않도록 reload 때 한 번 계산한다
    private(set) var missingFileIDs: Set<Int64> = []
    var message: PanelMessage?

    @ObservationIgnored let store: ClipStore
    @ObservationIgnored private let settings: PasterSettings
    /// SearchField 가 만들어지면 자기 자신을 등록한다.
    @ObservationIgnored weak var searchField: NSTextField?
    /// 리듀서가 낸 effect 를 처리할 곳 (PanelController).
    @ObservationIgnored var effectHandler: ((PanelEffect) -> Void)?
    /// 마지막으로 목록을 읽은 검색어. 검색어가 바뀐 뒤에는 이전 선택 항목을 따라가지 않는다
    @ObservationIgnored private var loadedQuery: String?

    init(store: ClipStore, settings: PasterSettings) {
        self.store = store
        self.settings = settings
    }

    /// 패널을 열 때: 검색어 · 포커스 초기화.
    func resetForOpen() {
        state = PanelState()
        message = nil
        syncSearchField()
        reload(keepingSelection: false)
    }

    /// 두 목록을 다시 읽는다. `keepingSelection` 이면 칼럼마다 선택했던 항목을 id 로 찾아 그 위치를 계속 선택하고,
    /// 사라졌으면 선택 위치를 범위 안으로 맞춘다. 새 복사가 맨 위에 들어와도 선택이 다른 항목으로 밀리지 않는다.
    func reload(keepingSelection: Bool = true) {
        let keep = keepingSelection && loadedQuery == state.query
        let selectedClipboardID = keep ? item(.clipboard, state.clipboardIndex)?.id : nil
        let selectedPinnedID = keep ? item(.pinned, state.pinnedIndex)?.id : nil
        do {
            clipboardItems = try store.fetchUnpinned(matching: state.query, settings: settings.retention, now: Date())
            pinnedItems = try store.fetchPinned(matching: state.query)
            missingFileIDs = Set((clipboardItems + pinnedItems).compactMap { item in
                item.kind == .files && !item.missingFilePaths().isEmpty ? item.id : nil
            })
        } catch {
            Log.app.error("목록 읽기 실패: \(String(describing: error), privacy: .public)")
        }
        loadedQuery = state.query
        state.updateCounts(clipboard: clipboardItems.count, pinned: pinnedItems.count)
        state.reselect(
            clipboardIndex: selectedClipboardID.flatMap { id in clipboardItems.firstIndex { $0.id == id } },
            pinnedIndex: selectedPinnedID.flatMap { id in pinnedItems.firstIndex { $0.id == id } }
        )
    }

    func queryChanged(_ query: String) {
        guard query != state.query else { return }
        state.setQuery(query)
        message = nil
        reload(keepingSelection: false)
    }

    /// 키 · 클릭을 리듀서에 넣고 effect 를 넘긴다. 반환값은 키 이벤트를 흘려보낼지 판단하는 데 쓴다.
    @discardableResult
    func send(_ key: PanelKey) -> PanelEffect? {
        let (next, effect) = PanelReducer.reduce(state, key)
        let queryChanged = next.query != state.query
        state = next
        if queryChanged {
            // Esc 로 검색어를 지운 경우 등: 검색창이 상태를 따라가게 한다
            syncSearchField()
            message = nil
            reload(keepingSelection: false)
        }
        if let effect, effect != .passThrough { effectHandler?(effect) }
        return effect
    }

    /// 검색창 글자를 state.query 에 맞춘다. IME 조합 중에는 건드리지 않는다.
    func syncSearchField() {
        guard let field = searchField else { return }
        if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() { return }
        if field.stringValue != state.query { field.stringValue = state.query }
    }

    func item(_ column: PanelColumn, _ index: Int) -> ClipItem? {
        let items = column == .clipboard ? clipboardItems : pinnedItems
        return items.indices.contains(index) ? items[index] : nil
    }

    /// rtf · html · 전체 본문까지 담은 항목. 붙여넣기 직전에 읽는다.
    func fullItem(id: Int64) throws -> ClipItem? {
        try store.item(id: id)
    }

    func hasMissingFiles(_ id: Int64) -> Bool {
        missingFileIDs.contains(id)
    }

    func items(in column: PanelColumn) -> [ClipItem] {
        column == .clipboard ? clipboardItems : pinnedItems
    }

    var previewItem: ClipItem? {
        state.activeIndex.flatMap { item(state.activeColumn, $0) }
    }

    func blobURL(for item: ClipItem) -> URL? {
        item.imageBlob.map { store.blobs.url(for: $0) }
    }
}
