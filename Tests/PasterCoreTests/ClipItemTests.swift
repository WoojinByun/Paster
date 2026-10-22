import Foundation
import Testing
@testable import PasterCore

struct ClipItemTests {
    let date = Date(timeIntervalSince1970: 1_800_000_000)

    func item(_ kind: ClipKind, text: String = "", size: Int = 0, width: Int? = nil, height: Int? = nil, paths: [String] = []) -> ClipItem {
        ClipItem(kind: kind, plainText: text, imageWidth: width, imageHeight: height, byteSize: size,
                 filePaths: paths, contentHash: "h", createdAt: date, lastCopiedAt: date)
    }

    @Test func textTitleIsFirstNonEmptyLine() {
        #expect(item(.text, text: "\n  첫 줄  \n둘째 줄").title == "첫 줄")
        #expect(item(.text, text: "한 줄").title == "한 줄")
    }

    @Test func textTitleSkipsLeadingBlankLines() {
        #expect(item(.text, text: "\n\n   \n\t\n  셋째  \n넷째").title == "셋째")
    }

    @Test func textTitleHandlesCRLF() {
        #expect(item(.text, text: "\r\n\r\n첫 줄\r\n둘째 줄").title == "첫 줄")
        #expect(item(.text, text: "한 줄\r\n").title == "한 줄")
    }

    @Test func whitespaceOnlyTextShowsPlaceholder() {
        #expect(item(.text, text: "   \n\t\n  ").title == ClipItem.blankTitle)
        #expect(item(.text, text: "").title == ClipItem.blankTitle)
    }

    @Test func longFirstLineIsCapped() {
        let title = item(.text, text: String(repeating: "가", count: 5_000) + "\n둘째").title
        #expect(title.count == ClipItem.maxTitleLength)
    }

    @Test func veryLargeTextGivesFirstLine() {
        // 수 MB 짜리 본문도 앞부분만 보고 제목을 만든다 (정확성만 확인)
        let body = "  제목 줄  \n" + String(repeating: "본문 내용 한 줄입니다.\n", count: 400_000)
        #expect(item(.text, text: body).title == "제목 줄")
    }

    @Test func blankPrefixLongerThanScanLimitShowsPlaceholder() {
        let body = String(repeating: " \n", count: 10_000) + "늦은 줄"
        #expect(item(.text, text: body).title == ClipItem.blankTitle)
    }

    @Test func imageTitleShowsSizeAndBytes() {
        #expect(item(.image, size: 1_234_567, width: 1292, height: 878).title == "Image: 1292x878 (1.2 MB)")
    }

    @Test func filesTitleShowsFirstNameAndCount() {
        #expect(item(.files, paths: ["/tmp/report.pdf"]).title == "파일: report.pdf")
        #expect(item(.files, paths: ["/tmp/report.pdf", "/tmp/a.txt", "/tmp/b.txt"]).title == "파일: report.pdf 외 2개")
    }

    @Test func missingFilePathsListsOnlyAbsentFiles() throws {
        let existing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("x".utf8).write(to: existing)
        defer { try? FileManager.default.removeItem(at: existing) }
        let clip = item(.files, paths: [existing.path, "/nonexistent/\(UUID().uuidString)"])
        #expect(clip.missingFilePaths().count == 1)
        #expect(clip.missingFilePaths().first?.hasPrefix("/nonexistent/") == true)
    }

    @Test(arguments: [
        (0, "0 B"), (999, "999 B"), (1000, "1.0 KB"), (1_234_567, "1.2 MB"), (5_000_000_000, "5.0 GB"),
        (999_949, "999.9 KB"), (999_950, "1.0 MB"), (999_999, "1.0 MB"), (999_999_999, "1.0 GB"),
    ])
    func byteSizeFormat(bytes: Int, expected: String) {
        #expect(ByteSize.format(bytes) == expected)
    }
}
