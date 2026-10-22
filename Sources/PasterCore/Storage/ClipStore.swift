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
        try Self.migrator.migrate(dbQueue)
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
        return migrator
    }
}
