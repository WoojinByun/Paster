import AppKit
import Observation
import PasterCore
import ServiceManagement
import UniformTypeIdentifiers

/// 제외 앱 목록의 한 줄.
struct ExcludedApp: Identifiable, Equatable {
    let bundleID: String
    let name: String
    let icon: NSImage?
    var id: String { bundleID }
}

@MainActor
@Observable
final class SettingsModel {
    /// 바로 저장한다. 조회가 만료 항목을 걸러내므로 정리는 따로 돌리지 않는다.
    var retention: RetentionSettings {
        didSet {
            guard retention != oldValue else { return }
            settings.retention = retention
            onDataChanged()
        }
    }
    private(set) var excludedApps: [ExcludedApp] = []
    private(set) var launchAtLogin: Bool
    private(set) var isClearing = false
    var errorMessage: String?
    /// 로그인 항목 승인이 필요한 상태. 안내와 "시스템 설정 열기" 버튼을 보여 준다.
    private(set) var needsLoginApproval = false

    @ObservationIgnored private let settings: PasterSettings
    @ObservationIgnored private let store: ClipStore
    @ObservationIgnored private let onDataChanged: () -> Void
    /// 확인 대화상자를 시트로 붙일 설정 창.
    @ObservationIgnored weak var hostWindow: NSWindow?

    init(environment: AppEnvironment, onDataChanged: @escaping () -> Void) {
        settings = environment.settings
        store = environment.store
        self.onDataChanged = onDataChanged
        retention = environment.settings.retention
        launchAtLogin = SMAppService.mainApp.status == .enabled
        reloadExcludedApps()
    }

    /// 창을 열 때마다 시스템 상태와 다시 맞춘다 (시스템 설정에서 바뀌었을 수 있다).
    func refresh() {
        retention = settings.retention
        errorMessage = nil
        syncLaunchAtLogin()
        reloadExcludedApps()
    }

    // MARK: 로그인 시 실행

    func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            errorMessage = nil
        } catch {
            Log.app.error("로그인 시 실행 설정 실패: \(String(describing: error), privacy: .public)")
            errorMessage = "로그인 시 실행을 설정하지 못했습니다: \(error.localizedDescription)"
        }
        syncLaunchAtLogin()
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func syncLaunchAtLogin() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        needsLoginApproval = status == .requiresApproval
    }

    // MARK: 제외 앱

    func addExcludedApp() {
        let panel = NSOpenPanel()
        panel.title = "제외할 앱 선택"
        panel.prompt = "추가"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if let window = hostWindow, window.isVisible {
            panel.beginSheetModal(for: window) { [weak self] response in
                guard response == .OK else { return }
                MainActor.assumeIsolated { self?.addExcludedApps(at: panel.urls) }
            }
        } else if panel.runModal() == .OK {
            addExcludedApps(at: panel.urls)
        }
    }

    private func addExcludedApps(at urls: [URL]) {
        let ids = urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        if ids.count < urls.count {
            errorMessage = "일부 앱의 번들 ID를 읽지 못해 추가하지 않았습니다."
        } else {
            errorMessage = nil
        }
        // PasterSettings 가 중복을 없애고 정렬해서 저장한다
        settings.excludedBundleIDs += ids
        reloadExcludedApps()
    }

    func removeExcludedApp(_ app: ExcludedApp) {
        settings.excludedBundleIDs = settings.excludedBundleIDs.filter { $0 != app.bundleID }
        reloadExcludedApps()
    }

    private func reloadExcludedApps() {
        excludedApps = settings.excludedBundleIDs.map { bundleID in
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            let name = url.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID
            let icon = url.map { NSWorkspace.shared.icon(forFile: $0.path) }
            return ExcludedApp(bundleID: bundleID, name: name, icon: icon)
        }
    }

    // MARK: 전체 삭제

    /// 확인 대화상자를 띄우고, 승인하면 미고정 항목만 지운다.
    func confirmClearAllHistory() {
        guard !isClearing else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "고정하지 않은 항목을 모두 삭제할까요?"
        alert.informativeText = "Pinned 항목은 유지됩니다. 이 작업은 되돌릴 수 없습니다."
        // 첫 버튼이 Return 기본값이다. Return 으로 삭제되지 않도록 "취소" 를 먼저 둔다
        alert.addButton(withTitle: "취소")
        let delete = alert.addButton(withTitle: "삭제")
        delete.hasDestructiveAction = true
        delete.keyEquivalent = ""
        if let window = hostWindow, window.isVisible {
            alert.beginSheetModal(for: window) { [weak self] response in
                guard response == .alertSecondButtonReturn else { return }
                MainActor.assumeIsolated { self?.clearAllHistory() }
            }
        } else if alert.runModal() == .alertSecondButtonReturn {
            clearAllHistory()
        }
    }

    private func clearAllHistory() {
        isClearing = true
        let store = store
        Task {
            // DB · blob 파일 삭제는 메인 스레드 밖에서
            let result = await Task.detached { () -> Result<Int, any Error> in
                Result { try store.deleteAllUnpinned() }
            }.value
            isClearing = false
            switch result {
            case .success(let count):
                Log.app.info("전체 삭제: \(count, privacy: .public)건")
                errorMessage = nil
            case .failure(let error):
                Log.app.error("전체 삭제 실패: \(String(describing: error), privacy: .public)")
                errorMessage = "삭제하지 못했습니다: \(error.localizedDescription)"
            }
            onDataChanged()
        }
    }
}
