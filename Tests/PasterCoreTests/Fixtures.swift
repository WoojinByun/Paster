import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import PasterCore

/// 테스트 공용 도우미.
enum Fixtures {
    /// 단색 이미지를 지정 형식으로 인코딩한다.
    static func image(width: Int, height: Int, type: UTType) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return output as Data
    }

    private static var preferencesDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences", isDirectory: true)
    }

    /// 테스트용 UserDefaults 스위트를 만든다. 첫 호출 때 이전 실행이 남긴 plist 도 치운다.
    static func makeDefaultsSuite(prefix: String) -> (name: String, defaults: UserDefaults) {
        _ = sweepStaleSuites
        let name = "\(prefix)-\(UUID().uuidString)"
        return (name, UserDefaults(suiteName: name)!)
    }

    /// 스위트의 도메인과 plist 파일을 지운다.
    /// cfprefsd 가 프로세스 종료 뒤에 파일을 다시 쓰는 경우가 있어서, 남은 것은 다음 실행의 sweepStaleSuites 가 치운다.
    static func removeDefaultsSuite(_ defaults: UserDefaults, named suite: String) {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: preferencesDirectory.appendingPathComponent("\(suite).plist"))
    }

    private static let sweepStaleSuites: Void = {
        let pattern = #/^(RetentionServiceTests|PasterSettingsTests)-[0-9A-Fa-f-]+\.plist$/#
        let names = (try? FileManager.default.contentsOfDirectory(atPath: preferencesDirectory.path)) ?? []
        for name in names where name.wholeMatch(of: pattern) != nil {
            try? FileManager.default.removeItem(at: preferencesDirectory.appendingPathComponent(name))
        }
    }()

    static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 2027-01-15 08:00:00 UTC. 초 단위로 떨어지는 고정 시각.
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
}
