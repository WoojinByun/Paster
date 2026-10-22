import PasterCore
import SwiftUI

/// Clipboard 또는 Pinned 칼럼.
struct ClipColumnView: View {
    let model: PanelModel
    let column: PanelColumn
    let title: String

    private var items: [ClipItem] { model.items(in: column) }
    private var selectedIndex: Int { model.state.selectedIndex(in: column) }
    /// ⌘숫자 힌트 대상 (검색창 포커스면 Clipboard)
    private var isActive: Bool { model.state.activeColumn == column }
    /// 실제 키보드 포커스. 강조 색은 이때만 쓴다
    private var hasFocus: Bool { model.state.focus == (column == .clipboard ? .clipboard : .pinned) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            if items.isEmpty {
                emptyHint
            } else {
                list
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var emptyHint: some View {
        Text(column == .pinned ? "⌘P로 고정" : "복사한 항목이 여기에 표시됩니다")
            .font(.callout)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ClipRowView(
                            item: item,
                            isPinned: column == .pinned,
                            isSelected: index == selectedIndex,
                            isFocused: hasFocus,
                            hasMissingFiles: item.id.map(model.hasMissingFiles) ?? false,
                            hint: isActive && index < 9 ? "⌘\(index + 1)" : nil
                        )
                        .id(item.id)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { model.send(.doubleClick(column, index)) }
                        .onTapGesture { model.send(.click(column, index)) }
                    }
                }
            }
            .onChange(of: selectedIndex) { _, newValue in
                if items.indices.contains(newValue) { proxy.scrollTo(items[newValue].id) }
            }
        }
    }
}
