import Testing
@testable import PasterCore

struct RecentAppsWindowTests {
    let vault = "com.1password.1password"
    let safari = "com.apple.Safari"
    var excluded: Set<String> { [vault] }

    @Test func excludedAppThatLeftBeforeAnUnchangedPollDoesNotAffectLaterCopy() {
        var window = RecentAppsWindow(frontmost: vault)
        window.activated(safari)
        // 변화 없는 폴링: 지금 앞의 Safari 만 남긴다
        window.reset(frontmost: safari)
        // Safari 에서 복사 → 다음 폴링
        #expect(window.excludedApp(frontmost: safari, excluded: excluded) == nil)
    }

    @Test func excludedAppFrontmostAtCopyTimeIsExcluded() {
        let window = RecentAppsWindow(frontmost: safari)
        #expect(window.excludedApp(frontmost: vault, excluded: excluded) == vault)
    }

    @Test func excludedAppFrontmostAtPreviousPollIsExcludedAfterSwitchingAway() {
        // 직전 폴링 때 1Password 가 앞 → 복사 후 폴링 전에 Safari 로 전환
        var window = RecentAppsWindow(frontmost: vault)
        window.activated(safari)
        #expect(window.excludedApp(frontmost: safari, excluded: excluded) == vault)
    }

    @Test func excludedAppActivatedBetweenPollsIsExcluded() {
        // 직전 폴링 이후 1Password 로 갔다가 복사 후 Safari 로 돌아옴
        var window = RecentAppsWindow(frontmost: safari)
        window.activated(vault)
        window.activated(safari)
        #expect(window.excludedApp(frontmost: safari, excluded: excluded) == vault)
    }

    @Test func resetSeedsOnlyCurrentFrontmost() {
        var window = RecentAppsWindow(frontmost: vault)
        window.activated(safari)
        window.reset(frontmost: nil)
        #expect(window.bundleIDs.isEmpty)
        #expect(window.excludedApp(frontmost: nil, excluded: excluded) == nil)
    }
}
