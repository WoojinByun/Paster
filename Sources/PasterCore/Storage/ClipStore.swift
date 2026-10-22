import Foundation
import GRDB

/// SQLite(GRDB) 기반 클립 저장소. blob 파일도 함께 관리한다.
public final class ClipStore: Sendable {
    public static let databaseFileName = "paster.sqlite"
    public static let blobDirectoryName = "blobs"

    public let dbQueue: DatabaseQueue
    public let blobs: BlobStore

    public init(dbQueue: DatabaseQueue, blobs: BlobStore) throws {
        self.dbQueue = dbQueue
        self.blobs = blobs
        // 지운 내용을 0 으로 덮어써 파일에 남지 않게 한다. 연결 단위 설정이라 열 때마다 켠다.
        // DatabaseQueue 는 연결이 하나라 여기서 한 번 켜면 계속 유지된다.
        try dbQueue.writeWithoutTransaction { try $0.execute(sql: "PRAGMA secure_delete = ON") }
        try Self.migrator.migrate(dbQueue)
    }

    /// FTS5 `secure-delete` 옵션은 SQLite 3.44 부터 있다.
    static func supportsFTSSecureDelete(_ db: Database) throws -> Bool {
        let version = try String.fetchOne(db, sql: "SELECT sqlite_version()") ?? ""
        let parts = version.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2 else { return false }
        return (parts[0], parts[1]) >= (3, 44)
    }

    /// 테스트용 메모리 DB.
    public static func inMemory(blobDirectory: URL) throws -> ClipStore {
        try ClipStore(dbQueue: DatabaseQueue(), blobs: BlobStore(directory: blobDirectory))
    }

    public func item(id: Int64) throws -> ClipItem? {
        try dbQueue.read { try ClipItem.fetchOne($0, key: id) }
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE clip_items (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    kind TEXT NOT NULL,
                    plain_text TEXT NOT NULL DEFAULT '',
                    rtf BLOB,
                    html BLOB,
                    image_blob TEXT,
                    image_width INTEGER,
                    image_height INTEGER,
                    byte_size INTEGER NOT NULL DEFAULT 0,
                    file_paths TEXT NOT NULL DEFAULT '[]',
                    source_bundle_id TEXT,
                    source_app_name TEXT,
                    content_hash TEXT NOT NULL UNIQUE,
                    created_at DATETIME NOT NULL,
                    last_copied_at DATETIME NOT NULL,
                    pinned_at DATETIME,
                    pin_order INTEGER
                );
                CREATE INDEX clip_items_last_copied_at ON clip_items(last_copied_at);
                CREATE INDEX clip_items_pin_order ON clip_items(pin_order) WHERE pinned_at IS NOT NULL;

                CREATE VIRTUAL TABLE clip_fts USING fts5(
                    plain_text, source_app_name,
                    content='clip_items', content_rowid='id', tokenize='trigram'
                );
                CREATE TRIGGER clip_items_ai AFTER INSERT ON clip_items BEGIN
                    INSERT INTO clip_fts(rowid, plain_text, source_app_name)
                    VALUES (new.id, new.plain_text, new.source_app_name);
                END;
                CREATE TRIGGER clip_items_ad AFTER DELETE ON clip_items BEGIN
                    INSERT INTO clip_fts(clip_fts, rowid, plain_text, source_app_name)
                    VALUES ('delete', old.id, old.plain_text, old.source_app_name);
                END;
                CREATE TRIGGER clip_items_au AFTER UPDATE OF plain_text, source_app_name ON clip_items BEGIN
                    INSERT INTO clip_fts(clip_fts, rowid, plain_text, source_app_name)
                    VALUES ('delete', old.id, old.plain_text, old.source_app_name);
                    INSERT INTO clip_fts(rowid, plain_text, source_app_name)
                    VALUES (new.id, new.plain_text, new.source_app_name);
                END;
                """)
        }
        migrator.registerMigration("v2-fts-secure-delete") { db in
            // FTS 인덱스에서도 지운 항목의 흔적을 남기지 않는다. 설정은 clip_fts_config 에 영구 저장된다.
            guard try supportsFTSSecureDelete(db) else { return }
            try db.execute(sql: "INSERT INTO clip_fts(clip_fts, rank) VALUES('secure-delete', 1)")
        }
        return migrator
    }
}
