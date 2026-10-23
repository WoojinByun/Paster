import KeyboardShortcuts
import PasterCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: SettingsModel
    @State private var selectedExcluded: ExcludedApp.ID?

    var body: some View {
        Form {
            Section("보관") {
                retentionRow("텍스트", kind: .text)
                retentionRow("이미지", kind: .image)
                retentionRow("파일", kind: .files)
                Text("꺼진 타입은 새로 저장하지 않으며, 기존 항목은 기간이 끝날 때까지 유지됩니다. 고정한 항목은 만료되지 않습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("단축키") {
                KeyboardShortcuts.Recorder("패널 열기", name: .togglePanel)
            }

            Section("제외할 앱") {
                List(model.excludedApps, selection: $selectedExcluded) { app in
                    HStack(spacing: 6) {
                        if let icon = app.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 16, height: 16)
                        }
                        Text(app.name)
                    }
                    .help(app.bundleID)
                }
                .frame(minHeight: 80)
                HStack {
                    Button("추가…") { model.addExcludedApp() }
                    Button("제거") {
                        if let app = model.excludedApps.first(where: { $0.id == selectedExcluded }) {
                            model.removeExcludedApp(app)
                            selectedExcluded = nil
                        }
                    }
                    .disabled(selectedExcluded == nil)
                }
            }

            Section("일반") {
                Toggle("로그인 시 실행", isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                if model.needsLoginApproval {
                    HStack {
                        Text("시스템 설정 → 일반 → 로그인 항목에서 Paster를 허용해 주세요.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("시스템 설정 열기") { model.openLoginItemsSettings() }
                    }
                }
                Toggle("자동으로 업데이트 확인", isOn: $model.automaticallyChecksForUpdates)
                    .disabled(!model.hasUpdateFeed)
                if !model.hasUpdateFeed {
                    Text("개발용 빌드: 업데이트 피드가 없습니다")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("데이터") {
                Button("Clear All History…", role: .destructive) { model.confirmClearAllHistory() }
                    .disabled(model.isClearing)
                Text("고정하지 않은 항목만 삭제하며 Pinned 는 유지합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = model.errorMessage {
                Text(error).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        // grouped Form 은 스크롤 기반이라 최소 높이가 0 이다. 창을 줄여도 내용이 보이도록 하한을 둔다
        .frame(minHeight: 320)
    }

    private func retentionRow(_ title: String, kind: ClipKind) -> some View {
        HStack {
            Toggle(title, isOn: $model.retention[kind].isEnabled)
            Spacer()
            Picker("", selection: $model.retention[kind].period) {
                ForEach(RetentionPeriod.allCases, id: \.self) { period in
                    Text(period.label).tag(period)
                }
            }
            .labelsHidden()
            .fixedSize()
        }
    }
}
