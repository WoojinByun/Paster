import Darwin
import Foundation

/// 데이터 디렉터리의 잠금 파일로 Paster 가 하나만 돌게 한다.
/// fd 는 프로세스가 끝날 때까지 열어 두고, 종료·크래시 시 커널이 잠금을 푼다.
final class InstanceLock {
    enum Failure: Error {
        /// 다른 Paster 가 잠금을 잡고 있다
        case alreadyRunning
        /// 잠금 파일을 만들거나 잠글 수 없다
        case unavailable(any Error)
    }

    static let fileName = "paster.lock"

    private let fd: Int32

    init(directory: URL) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw Failure.unavailable(error)
        }
        let path = directory.appendingPathComponent(Self.fileName).path
        var fd = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        let openError = errno
        // 쓰기 권한 없는 잠금 파일이 남아 있어도 flock 은 읽기 전용 fd 로 된다
        if fd < 0, openError == EACCES {
            fd = open(path, O_RDONLY | O_CLOEXEC)
        }
        // 다시 열기도 실패하면 처음 오류(EACCES)를 알린다
        guard fd >= 0 else { throw Failure.unavailable(Self.posixError(openError)) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            close(fd)
            throw code == EWOULDBLOCK ? Failure.alreadyRunning : Failure.unavailable(Self.posixError(code))
        }
        self.fd = fd
    }

    private static func posixError(_ code: Int32) -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }

    deinit {
        close(fd)
    }
}
