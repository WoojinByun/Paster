import PasterCore
import SwiftUI

/// Clipboard 또는 Pinned 칼럼.
struct ClipColumnView: View {
    let model: PanelModel
    let column: PanelColumn
    let title: String

    private var items: [ClipItem] { model.items(in: column) }
    private var selectedIndex: Int { model.state.selectedIndex(in: column) }
    private var isFocused: Bool { model.state.activeColumn == column }

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
                            isFocused: isFocused,
                            hint: isFocused && index < 9 ? "⌘\(index + 1)" : nil
                        )
                        .id(index)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { model.send(.doubleClick(column, index)) }
                        .onTapGesture { model.send(.click(column, index)) }
                    }
                }
            }
            .onChange(of: selectedIndex) { _, newValue in
                proxy.scrollTo(newValue)
            }
        }
    }
}
