import os

/// os.Logger 모음. 클립보드 내용은 절대 로그에 남기지 않는다.
public enum Log {
    public static let subsystem = "com.wjbyun.Paster"

    public static let capture = Logger(subsystem: subsystem, category: "capture")
    public static let store = Logger(subsystem: subsystem, category: "store")
    public static let retention = Logger(subsystem: subsystem, category: "retention")
    public static let app = Logger(subsystem: subsystem, category: "app")
}
