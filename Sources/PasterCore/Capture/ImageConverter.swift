import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// PNG 로 변환된 이미지와 픽셀 크기.
public struct PNGImage: Equatable, Sendable {
    public var data: Data
    public var width: Int
    public var height: Int

    public init(data: Data, width: Int, height: Int) {
        self.data = data
        self.width = width
        self.height = height
    }
}

/// ImageIO 기반 변환. AppKit 없이 동작하므로 테스트에서 window server 가 필요 없다.
public enum ImageConverter {
    /// 임의 형식(PNG, TIFF 등) 이미지 데이터를 PNG 로 바꾼다. 이미 PNG 면 원본 데이터를 그대로 쓴다.
    public static func png(from data: Data) -> PNGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        if let type = CGImageSourceGetType(source), (type as String) == UTType.png.identifier {
            return PNGImage(data: data, width: image.width, height: image.height)
        }
        guard let encoded = encode(image, as: .png) else { return nil }
        return PNGImage(data: encoded, width: image.width, height: image.height)
    }

    /// 이미지 데이터를 지정한 형식으로 다시 인코딩한다. 붙여넣기 때 PNG → TIFF 용.
    public static func convert(_ data: Data, to type: UTType) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        return encode(image, as: type)
    }

    static func encode(_ image: CGImage, as type: UTType) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
