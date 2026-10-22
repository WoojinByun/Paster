import Foundation
import GRDB

/// `clip_items` 테이블의 한 행.
public struct ClipItem: Codable, Equatable, Identifiable, Sendable {
    public var id: Int64?
    public var kind: ClipKind
    /// 텍스트 본문. 파일이면 파일명 목록 (줄바꿈 구분).
    public var plainText: String
    public var rtf: Data?
    public var html: Data?
    /// `blobs/` 안의 파일 이름 (`<uuid>.png`).
    public var imageBlob: String?
    public var imageWidth: Int?
    public var imageHeight: Int?
    public var byteSize: Int
    public var filePaths: [String]
    public var sourceBundleID: String?
    public var sourceAppName: String?
    public var contentHash: String
    public var createdAt: Date
    public var lastCopiedAt: Date
    public var pinnedAt: Date?
    public var pinOrder: Int?

    public init(
        id: Int64? = nil,
        kind: ClipKind,
        plainText: String,
        rtf: Data? = nil,
        html: Data? = nil,
        imageBlob: String? = nil,
        imageWidth: Int? = nil,
        imageHeight: Int? = nil,
        byteSize: Int,
        filePaths: [String] = [],
        sourceBundleID: String? = nil,
        sourceAppName: String? = nil,
        contentHash: String,
        createdAt: Date,
        lastCopiedAt: Date,
        pinnedAt: Date? = nil,
        pinOrder: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.plainText = plainText
        self.rtf = rtf
        self.html = html
        self.imageBlob = imageBlob
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.byteSize = byteSize
        self.filePaths = filePaths
        self.sourceBundleID = sourceBundleID
        self.sourceAppName = sourceAppName
        self.contentHash = contentHash
        self.createdAt = createdAt
        self.lastCopiedAt = lastCopiedAt
        self.pinnedAt = pinnedAt
        self.pinOrder = pinOrder
    }

    public var isPinned: Bool { pinnedAt != nil }

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case plainText = "plain_text"
        case rtf
        case html
        case imageBlob = "image_blob"
        case imageWidth = "image_width"
        case imageHeight = "image_height"
        case byteSize = "byte_size"
        case filePaths = "file_paths"
        case sourceBundleID = "source_bundle_id"
        case sourceAppName = "source_app_name"
        case contentHash = "content_hash"
        case createdAt = "created_at"
        case lastCopiedAt = "last_copied_at"
        case pinnedAt = "pinned_at"
        case pinOrder = "pin_order"
    }
}

extension ClipItem: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "clip_items"

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

extension ClipItem {
    /// 패널 행 제목.
    public var title: String {
        switch kind {
        case .text:
            let firstLine = plainText
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .first { !$0.isEmpty }
            return firstLine ?? ""
        case .image:
            return "Image: \(imageWidth ?? 0)x\(imageHeight ?? 0) (\(ByteSize.format(byteSize)))"
        case .files:
            let names = filePaths.map { URL(fileURLWithPath: $0).lastPathComponent }
            guard let first = names.first else { return "파일" }
            return names.count == 1 ? "파일: \(first)" : "파일: \(first) 외 \(names.count - 1)개"
        }
    }

    /// 원본이 사라진 파일 경로들.
    public func missingFilePaths(fileManager: FileManager = .default) -> [String] {
        filePaths.filter { !fileManager.fileExists(atPath: $0) }
    }
}
