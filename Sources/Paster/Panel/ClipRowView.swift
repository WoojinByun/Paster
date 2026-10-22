import PasterCore
import SwiftUI

/// 행: 출처 앱 아이콘 + 제목 (+ ⚠, ⌘숫자 힌트).
struct ClipRowView: View {
    let item: ClipItem
    let isPinned: Bool
    let isSelected: Bool
    let isFocused: Bool
    let hasMissingFiles: Bool
    let hint: String?

    var body: some View {
        HStack(spacing: 8) {
            if let icon = AppIconCache.icon(for: item.sourceBundleID) {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            } else {
                Image(systemName: "doc.on.clipboard").frame(width: 16, height: 16)
            }
            if isPinned { Text("📌") }
            Text(item.title)
                .lineLimit(1)
                .truncationMode(.tail)
            if hasMissingFiles {
                Text("⚠").help("원본 파일이 없습니다")
            }
            Spacer(minLength: 4)
            if let hint {
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(selectionBackground)
    }

    @ViewBuilder
    private var selectionBackground: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 5)
                .fill(isFocused ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.15))
                .padding(.horizontal, 4)
        }
    }
}
