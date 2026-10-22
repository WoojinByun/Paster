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
    /// 공백뿐인 텍스트의 제목.
    public static let blankTitle = "(공백)"
    /// 제목 최대 글자 수.
    public static let maxTitleLength = 200
    /// 제목을 찾을 때 보는 앞부분 크기 (유니코드 스칼라 수). 아주 긴 본문도 행마다 전체를 나누지 않는다.
    static let titleScanLimit = 8 * 1024

    /// 패널 행 제목.
    public var title: String {
        switch kind {
        case .text:
            return Self.textTitle(plainText)
        case .image:
            return "Image: \(imageWidth ?? 0)x\(imageHeight ?? 0) (\(ByteSize.format(byteSize)))"
        case .files:
            let names = filePaths.map { URL(fileURLWithPath: $0).lastPathComponent }
            guard let first = names.first else { return "파일" }
            return names.count == 1 ? "파일: \(first)" : "파일: \(first) 외 \(names.count - 1)개"
        }
    }

    /// 앞부분에서 처음으로 비어 있지 않은 줄. CRLF 도 한 줄바꿈으로 본다.
    /// 패널 목록 행은 `plainText` 를 앞 `ClipStore.listTextLimit` 글자만 들고 있으므로,
    /// 첫 번째 비어 있지 않은 줄이 그보다 뒤에서 시작하면 패널에는 `blankTitle`("(공백)") 이 보인다.
    static func textTitle(_ text: String) -> String {
        let head = String(String.UnicodeScalarView(text.unicodeScalars.prefix(titleScanLimit)))
        for line in head.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            return String(trimmed.prefix(maxTitleLength))
        }
        return blankTitle
    }

    /// 원본이 사라진 파일 경로들.
    public func missingFilePaths(fileManager: FileManager = .default) -> [String] {
        filePaths.filter { !fileManager.fileExists(atPath: $0) }
    }
}
