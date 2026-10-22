import Testing
@testable import PasterCore

@Test func logSubsystemIsBundleID() {
    #expect(Log.subsystem == "com.wjbyun.Paster")
}
