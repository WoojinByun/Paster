import Darwin
import Foundation

/// 데이터 디렉터리의 잠금 파일로 Paster 가 하나만 돌게 한다.
/// fd 는 프로세스가 끝날 때까지 열어 두고, 종료·크래시 시 커널이 잠금을 푼다.
final class InstanceLock {
    enum Failure: Error {
        /// 다른 Paster 가 잠금을 잡고 있다
        case alreadyRunning
        /// 잠금 파일을 열거나 잠글 수 없다 (errno)
        case system(Int32)
    }

    static let fileName = "paster.lock"

    private let fd: Int32

    init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent(Self.fileName).path
        let fd = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw Failure.system(errno) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(fd)
            throw code == EWOULDBLOCK ? Failure.alreadyRunning : Failure.system(code)
        }
        self.fd = fd
    }

    deinit {
        close(fd)
    }
}
