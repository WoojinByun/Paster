import PasterCore
import SwiftUI

/// 검색창 / Clipboard | Pinned / 미리보기 띠 (스펙 8.2절).
struct PanelView: View {
    let model: PanelModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                SearchField(model: model)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()
            HStack(spacing: 0) {
                ClipColumnView(model: model, column: .clipboard, title: "Clipboard")
                Divider()
                ClipColumnView(model: model, column: .pinned, title: "Pinned")
            }
            Divider()
            PreviewStrip(model: model)
                .frame(height: 150)
        }
        .frame(width: PasterPanel.size.width, height: PasterPanel.size.height)
        .background(.regularMaterial)
    }
}
