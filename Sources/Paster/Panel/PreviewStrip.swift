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
            // 항목이 바뀌면 이전 본문 상태를 버린다
            TextPreviewView(item: item, store: model.store).id(item.id)
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

/// 텍스트 미리보기: 목록 행의 앞부분을 먼저 보여 주고, 메인 밖에서 전체 본문을 읽어 앞 `limit` 글자로 바꾼다.
struct TextPreviewView: View {
    let item: ClipItem
    let store: ClipStore
    @State private var loaded: TextPreview.Result?

    var body: some View {
        let preview = loaded
            ?? item.id.flatMap(TextPreview.cached(for:))
            ?? TextPreview.Result(text: item.plainText, remaining: 0)
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
        .task(id: item.id) {
            guard let id = item.id else { return }
            if let cached = TextPreview.cached(for: id) {
                loaded = cached
                return
            }
            let store = store
            let result = await Task.detached(priority: .userInitiated) { () -> TextPreview.Result? in
                guard let full = try? store.item(id: id) else { return nil }
                return TextPreview.make(full.plainText)
            }.value
            guard !Task.isCancelled, let result else { return }
            TextPreview.store(result, for: id)
            loaded = result
        }
    }
}

/// 텍스트 미리보기 계산 · 마지막 항목 캐시. 항목 본문은 저장 뒤 바뀌지 않으므로 id 로 기억한다.
@MainActor
enum TextPreview {
    struct Result: Sendable {
        var text: String
        var remaining: Int
    }

    nonisolated static let limit = 20_000

    private static var last: (id: Int64, result: Result)?

    static func cached(for id: Int64) -> Result? {
        guard let last, last.id == id else { return nil }
        return last.result
    }

    static func store(_ result: Result, for id: Int64) {
        last = (id, result)
    }

    /// 앞 `limit` 글자와 나머지 글자 수. 긴 본문은 오래 걸리므로 메인 밖에서 부른다.
    nonisolated static func make(_ full: String) -> Result {
        if let cut = full.index(full.startIndex, offsetBy: limit, limitedBy: full.endIndex), cut < full.endIndex {
            return Result(text: String(full[..<cut]), remaining: full[cut...].count)
        }
        return Result(text: full, remaining: 0)
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
