import AppKit
import PasterCore
import SwiftUI

/// 하단 미리보기 띠 (스펙 8.6절).
struct PreviewStrip: View {
    let model: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let message = model.message {
                messageBar(message)
            }
            if let item = model.previewItem {
                content(for: item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Text(meta(for: item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Spacer()
            }
        }
        .padding(12)
    }

    private func messageBar(_ message: PanelMessage) -> some View {
        HStack {
            Text(message.text).foregroundStyle(.orange)
            if message == .needsAccessibility {
                Button("시스템 설정 열기") { AccessibilityPermission.openSettings() }
            }
        }
        .font(.callout)
    }

    @ViewBuilder
    private func content(for item: ClipItem) -> some View {
        switch item.kind {
        case .text:
            ScrollView {
                Text(item.plainText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .image:
            if let url = model.blobURL(for: item), let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Text("이미지 파일을 찾을 수 없습니다").foregroundStyle(.secondary)
            }
        case .files:
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(item.filePaths, id: \.self) { path in
                        let exists = FileManager.default.fileExists(atPath: path)
                        Text("\(exists ? "" : "⚠ ")\(path)\(exists ? "" : " (없음)")")
                            .foregroundStyle(exists ? .primary : .secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func meta(for item: ClipItem) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let relative = formatter.localizedString(for: item.lastCopiedAt, relativeTo: Date())
        let source = item.sourceAppName ?? "알 수 없는 앱"
        return "\(source) · \(relative) · \(ByteSize.format(item.byteSize))"
    }
}
