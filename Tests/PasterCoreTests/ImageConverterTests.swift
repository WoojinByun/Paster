import Foundation
import Testing
import UniformTypeIdentifiers
@testable import PasterCore

struct ImageConverterTests {
    @Test func tiffIsConvertedToPNG() throws {
        let tiff = Fixtures.image(width: 40, height: 30, type: .tiff)
        let png = try #require(ImageConverter.png(from: tiff))
        #expect(png.width == 40)
        #expect(png.height == 30)
        // PNG 시그니처 89 50 4E 47
        #expect(Array(png.data.prefix(4)) == [0x89, 0x50, 0x4E, 0x47])
    }

    @Test func pngIsKeptAsIs() throws {
        let original = Fixtures.image(width: 10, height: 20, type: .png)
        let png = try #require(ImageConverter.png(from: original))
        #expect(png.data == original)
        #expect(png.width == 10)
        #expect(png.height == 20)
    }

    @Test func garbageReturnsNil() {
        #expect(ImageConverter.png(from: Data("not an image".utf8)) == nil)
    }

    @Test func pngConvertsToTIFF() throws {
        let png = Fixtures.image(width: 8, height: 8, type: .png)
        let tiff = try #require(ImageConverter.convert(png, to: .tiff))
        // TIFF 시그니처: "II*\0" 또는 "MM\0*"
        let head = Array(tiff.prefix(2))
        #expect(head == [0x49, 0x49] || head == [0x4D, 0x4D])
    }
}
