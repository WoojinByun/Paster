import AppKit
import PasterCore
import UniformTypeIdentifiers

/// pasteboard 쓰기 → 직전 앱 활성화 → ⌘V (스펙 9절).
@MainActor
final class PasteService {
    enum WriteResult: Equatable {
        case written
        case missingFiles
        case missingImage
    }

    private let store: ClipStore
    private let pasteboard: NSPasteboard

    init(store: ClipStore, pasteboard: NSPasteboard = .general) {
        self.store = store
        self.pasteboard = pasteboard
    }

    /// pasteboard 에 쓰고 last_copied_at 을 갱신한다. 자체 마커를 붙여 Monitor 가 다시 캡처하지 않게 한다.
    func write(_ item: ClipItem, mode: PasteMode) -> WriteResult {
        let items: [NSPasteboardItem]
        switch item.kind {
        case .text:
            let entry = NSPasteboardItem()
            entry.setString(item.plainText, forType: .string)
            if mode != .plainText {
                if let rtf = item.rtf { entry.setData(rtf, forType: .rtf) }
                if let html = item.html { entry.setData(html, forType: .html) }
            }
            items = [entry]
        case .image:
            guard let name = item.imageBlob, let png = store.blobs.read(name) else { return .missingImage }
            let entry = NSPasteboardItem()
            entry.setData(png, forType: .png)
            if let tiff = ImageConverter.convert(png, to: .tiff) { entry.setData(tiff, forType: .tiff) }
            items = [entry]
        case .files:
            guard item.missingFilePaths().isEmpty else { return .missingFiles }
            if mode == .plainText {
                let entry = NSPasteboardItem()
                entry.setString(item.filePaths.joined(separator: "\n"), forType: .string)
                items = [entry]
            } else {
                items = item.filePaths.map { path in
                    let entry = NSPasteboardItem()
                    entry.setString(URL(fileURLWithPath: path).absoluteString, forType: .fileURL)
                    return entry
                }
            }
        }

        for entry in items {
            entry.setData(Data(), forType: NSPasteboard.PasteboardType(PasteboardType.pasterInternal))
        }
        pasteboard.clearContents()
        pasteboard.writeObjects(items)

        if let id = item.id {
            do {
                try store.touch(id: id, now: Date())
            } catch {
                Log.app.error("last_copied_at 갱신 실패: \(String(describing: error), privacy: .public)")
            }
        }
        return .written
    }

    /// 직전 앱을 활성화하고, 활성화가 끝나면 ⌘V 를 보낸다.
    func activateAndPaste(into target: NSRunningApplication?) async {
        if let target, !target.isTerminated {
            target.activate()
            let deadline = Date().addingTimeInterval(0.5)
            while NSWorkspace.shared.frontmostApplication?.processIdentifier != target.processIdentifier,
                  Date() < deadline {
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        // 활성화 직후 키 입력을 놓치지 않도록 잠깐 기다린다
        try? await Task.sleep(for: .milliseconds(50))
        Self.postCommandV()
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let virtualKeyV: CGKeyCode = 0x09
        let down = CGEvent(keyboardEventSource: source, virtualKey: virtualKeyV, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: virtualKeyV, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
