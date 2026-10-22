import Foundation
import GRDB

public enum SaveOutcome: Equatable, Sendable {
    /// 새 행을 만들었다.
    case inserted(ClipItem)
    /// 같은 content_hash 가 있어 last_copied_at 과 출처만 갱신했다.
    case bumped(ClipItem)

    public var item: ClipItem {
        switch self {
        case let .inserted(item), let .bumped(item): item
        }
    }
}

extension ClipStore {
    /// 캡처한 클립을 저장한다. 같은 해시가 있으면 새 행 대신 맨 위로 올린다.
    @discardableResult
    public func save(_ clip: CapturedClip, now: Date) throws -> SaveOutcome {
        try dbQueue.write { db in
            if var existing = try ClipItem.filter(Column("content_hash") == clip.contentHash).fetchOne(db) {
                existing.lastCopiedAt = now
                existing.sourceBundleID = clip.source.bundleID
                existing.sourceAppName = clip.source.name
                try existing.update(db)
                return .bumped(existing)
            }

            let blobName = try clip.pngData.map { try blobs.write($0) }
            var item = ClipItem(
                kind: clip.kind,
                plainText: clip.plainText,
                rtf: clip.rtf,
                html: clip.html,
                imageBlob: blobName,
                imageWidth: clip.imageWidth,
                imageHeight: clip.imageHeight,
                byteSize: clip.byteSize,
                filePaths: clip.filePaths,
                sourceBundleID: clip.source.bundleID,
                sourceAppName: clip.source.name,
                contentHash: clip.contentHash,
                createdAt: now,
                lastCopiedAt: now
            )
            do {
                try item.insert(db)
            } catch {
                if let blobName { blobs.remove(blobName) }
                throw error
            }
            return .inserted(item)
        }
    }

    /// 붙여넣기 / 복사한 항목을 맨 위로 올린다.
    public func touch(id: Int64, now: Date) throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE clip_items SET last_copied_at = ? WHERE id = ?", arguments: [now, id])
        }
    }
}
