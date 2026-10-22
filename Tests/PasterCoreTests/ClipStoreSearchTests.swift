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

    @Test func nfdTextClipIsFoundByNFCTrigramQuery() throws {
        try Fixtures.save(Fixtures.textClip("/Users/me/분기 보고서.pdf".decomposedStringWithCanonicalMapping), in: store)
        #expect(try search("보고서".precomposedStringWithCanonicalMapping).count == 2)
    }

    @Test func nfdTextClipIsFoundByNFCLikeQuery() throws {
        try Fixtures.save(Fixtures.textClip("/Users/me/분기 보고서.pdf".decomposedStringWithCanonicalMapping), in: store)
        #expect(try search("보고".precomposedStringWithCanonicalMapping).count == 2)
    }

    @Test func nfcClipIsFoundByNFDQuery() throws {
        #expect(try search("체크리".decomposedStringWithCanonicalMapping) == ["배포 체크리스트 정리"])
        #expect(try search("배".decomposedStringWithCanonicalMapping) == ["배포 체크리스트 정리"])
    }

    @Test func storedNFDTextIsNotAltered() throws {
        let nfd = "분기 보고서".decomposedStringWithCanonicalMapping
        try Fixtures.save(Fixtures.textClip(nfd), in: store)
        let found = try store.fetchUnpinned(matching: "보고서", settings: .default, now: later).map(\.plainText)
        #expect(found.contains { $0.unicodeScalars.elementsEqual(nfd.unicodeScalars) })
    }

    @Test func allTermsMustMatch() throws {
        #expect(try search("배포 정리") == ["배포 체크리스트 정리"])
        #expect(try search("정리   배포") == ["배포 체크리스트 정리"])
        #expect(try search("배포 없는말") == [])
    }

    @Test func shortTermsCombineWithAnd() throws {
        #expect(try search("정 배포") == ["배포 체크리스트 정리"])
    }

    @Test func termsMixTrigramAndLike() throws {
        #expect(try search("체크리 정") == ["배포 체크리스트 정리"])
        #expect(try search("체크리 없") == [])
    }

    @Test func operatorsInsideQuotedTermsAreLiteral() throws {
        try Fixtures.save(Fixtures.textClip("a*b c-d"), in: store)
        #expect(try search("a*b") == ["a*b c-d"])
        #expect(try search("NEAR OR") == [])
    }

    @Test func filterParsing() {
        #expect(SearchFilter(query: "  ").terms.isEmpty)
        #expect(SearchFilter(query: "ab").terms == [.like(patterns: ["%ab%"])])
        #expect(SearchFilter(query: "abc").terms == [.fullText(patterns: ["\"abc\""])])
        #expect(SearchFilter(query: "a\"b").terms == [.fullText(patterns: ["\"a\"\"b\""])])
        #expect(SearchFilter(query: "ab  abc").terms == [.like(patterns: ["%ab%"]), .fullText(patterns: ["\"abc\""])])
    }

    @Test func filterParsingKeepsNFCAndNFDVariants() {
        let nfc = "보고서".precomposedStringWithCanonicalMapping
        let nfd = "보고서".decomposedStringWithCanonicalMapping
        guard case let .fullText(patterns) = SearchFilter(query: nfd).terms.first else {
            Issue.record("fullText 단어가 아님")
            return
        }
        // String == 는 정규 동등이라 스칼라로 비교한다
        #expect(patterns.count == 2)
        #expect(patterns[0].unicodeScalars.elementsEqual("\"\(nfc)\"".unicodeScalars))
        #expect(patterns[1].unicodeScalars.elementsEqual("\"\(nfd)\"".unicodeScalars))
    }

    @Test func filterKeepsOnlyTheFirst32Terms() throws {
        let words = (1...100).map { "word\($0)" }
        let filter = SearchFilter(query: words.joined(separator: " "))
        #expect(filter.terms.count == 32)
        #expect(filter.terms.first == .fullText(patterns: ["\"word1\""]))
        #expect(filter.terms.last == .fullText(patterns: ["\"word32\""]))
        #expect(try search(words.joined(separator: " ")).isEmpty)
    }
}
