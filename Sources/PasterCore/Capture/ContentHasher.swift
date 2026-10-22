import CryptoKit
import Foundation

/// `content_hash` 계산. 종류를 앞에 붙여 같은 바이트라도 종류가 다르면 다른 해시가 된다.
enum ContentHasher {
    static func hash(kind: ClipKind, payload: Data) -> String {
        var hasher = SHA256()
        hasher.update(data: Data(kind.rawValue.utf8))
        hasher.update(data: Data([0]))
        hasher.update(data: payload)
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
