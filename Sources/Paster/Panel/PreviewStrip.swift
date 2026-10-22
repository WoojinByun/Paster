import AppKit
import ImageIO
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
            let preview = TextPreview.make(for: item)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text(preview.text)
                        .font(.system(.body, design: .monospaced))
                    if preview.remaining > 0 {
                        Text("… (\(preview.remaining)자 더 있음)").foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .image:
            if let id = item.id, let url = model.blobURL(for: item) {
                // 항목이 바뀌면 이전 이미지 상태를 버린다
                ImagePreview(id: id, url: url).id(id)
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

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    private func meta(for item: ClipItem) -> String {
        let relative = Self.relativeFormatter.localizedString(for: item.lastCopiedAt, relativeTo: Date())
        let source = item.sourceAppName ?? "알 수 없는 앱"
        return "\(source) · \(relative) · \(ByteSize.format(item.byteSize))"
    }
}

/// 텍스트 미리보기: 앞부분만 그린다. 마지막 항목 결과를 기억해 body 마다 다시 세지 않는다.
@MainActor
enum TextPreview {
    static let limit = 20_000

    private static var last: (id: Int64?, text: String, remaining: Int)?

    static func make(for item: ClipItem) -> (text: String, remaining: Int) {
        if let last, last.id != nil, last.id == item.id { return (last.text, last.remaining) }
        let full = item.plainText
        let result: (text: String, remaining: Int)
        if let cut = full.index(full.startIndex, offsetBy: limit, limitedBy: full.endIndex), cut < full.endIndex {
            result = (String(full[..<cut]), full[cut...].count)
        } else {
            result = (full, 0)
        }
        last = (item.id, result.text, result.remaining)
        return result
    }
}

/// 이미지 미리보기: 메인 밖에서 썸네일을 만들고, 최근 항목은 캐시한다.
struct ImagePreview: View {
    let id: Int64
    let url: URL
    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image = image ?? ThumbnailCache.image(for: id) {
                Image(nsImage: image).resizable().scaledToFit()
            } else if failed {
                Text("이미지 파일을 찾을 수 없습니다").foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: id) {
            image = nil
            failed = false
            if let cached = ThumbnailCache.image(for: id) {
                image = cached
                return
            }
            let url = url
            let thumbnail = await Task.detached(priority: .userInitiated) {
                ThumbnailCache.makeThumbnail(url: url, maxPixelSize: ThumbnailCache.maxPixelSize)
            }.value
            guard !Task.isCancelled else { return }
            if let thumbnail {
                let nsImage = NSImage(cgImage: thumbnail, size: .zero)
                ThumbnailCache.store(nsImage, for: id)
                image = nsImage
            } else {
                failed = true
            }
        }
    }
}

/// 최근 썸네일 캐시 (항목 id 기준, 약 20개).
@MainActor
enum ThumbnailCache {
    /// 미리보기 띠(약 760×130pt) × 화면 배율 정도
    nonisolated static let maxPixelSize = 1200
    private static let capacity = 20
    private static var images: [Int64: NSImage] = [:]
    private static var order: [Int64] = []

    static func image(for id: Int64) -> NSImage? {
        images[id]
    }

    static func store(_ image: NSImage, for id: Int64) {
        if images[id] == nil { order.append(id) }
        images[id] = image
        while order.count > capacity {
            images[order.removeFirst()] = nil
        }
    }

    /// 원본 전체를 디코딩하지 않고 축소본만 만든다.
    nonisolated static func makeThumbnail(url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
