import Foundation
import Testing
@testable import PasterCore

struct ClipStoreSearchTests {
    let store: ClipStore
    let later = Fixtures.now.addingTimeInterval(60)

    init() throws {
        store = try Fixtures.makeStore()
        try Fixtures.save(Fixtures.textClip("배포 체크리스트 정리"), in: store)
        try Fixtures.save(Fixtures.textClip("https://example.com/Deploy?id=1"), in: store)
        try Fixtures.save(Fixtures.textClip("100% 완료_v2"), in: store)
        try Fixtures.save(Fixtures.filesClip(["/Users/me/Documents/분기 보고서.pdf"]), in: store)
        try Fixtures.save(Fixtures.textClip("plain", source: SourceApp(bundleID: "com.apple.TextEdit", name: "TextEdit")), in: store)
    }

    func search(_ query: String) throws -> [String] {
        try store.fetchUnpinned(matching: query, settings: .default, now: later).map(\.plainText).sorted()
    }

    @Test func emptyQueryReturnsEverything() throws {
        #expect(try search("").count == 5)
        #expect(try search("   ").count == 5)
    }

    @Test func koreanSubstringViaTrigram() throws {
        #expect(try search("체크리") == ["배포 체크리스트 정리"])
        #expect(try search("크리스트") == ["배포 체크리스트 정리"])
    }

    @Test func trigramIsCaseInsensitive() throws {
        #expect(try search("deploy") == ["https://example.com/Deploy?id=1"])
    }

    @Test func fileNamesAreSearchable() throws {
        #expect(try search("보고서") == ["분기 보고서.pdf"])
    }

    @Test func sourceAppNameIsSearchable() throws {
        #expect(try search("TextEdit") == ["plain"])
    }

    @Test func oneOrTwoCharactersUseLike() throws {
        #expect(try search("배") == ["배포 체크리스트 정리"])
        #expect(try search("보고") == ["분기 보고서.pdf"])
        #expect(try search("Te") == ["plain"])
    }

    @Test func likeWildcardsAreEscaped() throws {
        #expect(try search("%") == ["100% 완료_v2"])
        #expect(try search("_v") == ["100% 완료_v2"])
    }

    @Test func quotesDoNotBreakFTS() throws {
        #expect(try search("\"배포\" OR") == [])
    }

    @Test func pinnedColumnIsFilteredToo() throws {
        let id = try #require(try store.fetchUnpinned(matching: "체크리", settings: .default, now: later).first?.id)
        try store.dbQueue.write { db in
            try db.execute(sql: "UPDATE clip_items SET pinned_at = ?, pin_order = 0 WHERE id = ?", arguments: [Fixtures.now, id])
        }
        #expect(try store.fetchPinned(matching: "체크리").count == 1)
        #expect(try store.fetchPinned(matching: "보고서").isEmpty)
    }

    @Test func filterParsing() {
        #expect(SearchFilter(query: "  ") == .none)
        #expect(SearchFilter(query: "ab") == .like(pattern: "%ab%"))
        #expect(SearchFilter(query: "abc") == .fullText(pattern: "\"abc\""))
        #expect(SearchFilter(query: "a\"b") == .fullText(pattern: "\"a\"\"b\""))
    }
}
