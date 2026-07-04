import AppKit
import SwiftUI

struct AboutSettingsView: View {
    @ObservedObject var viewModel: SettingsPanelViewModel
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var updateManager = UpdateManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSectionCard(title: "应用信息") {
                SettingsValueLine(title: "版本", value: appVersion)
                SettingsLineDivider()
                SettingsValueLine(title: "构建", value: appBuild)
                SettingsLineDivider()
                SettingsValueLine(title: "安装时间", value: versionMetadata)
                SettingsLineDivider()
                SettingsValueLine(title: "之前版本", value: previousVersion)
            }

            SettingsSectionCard(title: "隱私與分析") {
                SettingsToggleLine(
                    title: "匿名使用統計",
                    subtitle: "匿名统计启动、功能使用、Hook 安装和会话状态；不包含内容、代码、路径或主机信息。",
                    isOn: $settings.analyticsEnabled
                )
                SettingsLineDivider()
                SettingsInfoLine(
                    title: "蒐集範圍",
                    subtitle: "未同意前不上传；开启后有每日上限，可随时关闭。"
                ) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                }
            }

            SettingsSectionCard(title: "更新") {
                SettingsToggleLine(
                    title: "自动检查更新",
                    subtitle: "启动时和空闲时自动检查、下载并安装更新；关闭后仅在手动检查时更新",
                    isOn: $settings.automaticUpdateChecksEnabled
                )
                SettingsLineDivider()

                SettingsActionLine(
                    title: updateTitle,
                    subtitle: updateSubtitle
                ) {
                    handleUpdateAction()
                } accessory: {
                    updateAccessory
                }

                if updateManager.canInstallPendingUpdateNow {
                    SettingsLineDivider()

                    SettingsActionLine(
                        title: "立即重啟安裝",
                        subtitle: "不等待空閒，立即結束 Ping Island 並完成已下載的更新"
                    ) {
                        updateManager.installAndRelaunch()
                    } accessory: {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(TerminalColors.green)
                    }
                }

                if updateManager.canShowReleaseNotes {
                    SettingsLineDivider()

                    SettingsActionLine(
                        title: updateManager.releaseNotesActionTitle,
                        subtitle: updateManager.releaseNotesActionSubtitle
                    ) {
                        updateManager.showReleaseNotes()
                    } accessory: {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }

            SettingsSectionCard(title: "链接") {
                SettingsActionLine(title: "GitHub", subtitle: "打开 Issues 页面反馈问题") {
                    if let url = URL(string: "https://github.com/hua86430/ping-island/issues") {
                        NSWorkspace.shared.open(url)
                    }
                } accessory: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                }

                SettingsLineDivider()

                SettingsActionLine(
                    title: "导出诊断日志",
                    subtitle: viewModel.logExportStatus
                ) {
                    viewModel.exportLogs()
                } accessory: {
                    if viewModel.isExportingLogs {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white.opacity(0.8))
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private var versionMetadata: String {
        guard let metadata = HookInstaller.getVersionMetadata(),
              let installedAt = metadata["installedAt"] as? String else {
            return AppLocalization.string("首次安装")
        }

        // Format the date
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: installedAt) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .medium
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }

        return installedAt
    }

    private var previousVersion: String {
        guard let metadata = HookInstaller.getVersionMetadata(),
              let previous = metadata["previousVersion"] as? String,
              !previous.isEmpty else {
            return AppLocalization.string("无")
        }
        return previous
    }

    private var updateTitle: String {
        switch updateManager.state {
        case .idle, .upToDate:
            return AppLocalization.string("检查更新")
        case .checking:
            return AppLocalization.string("检查中...")
        case .found, .downloading, .extracting:
            return AppLocalization.string("静默更新中")
        case .readyToInstall:
            return AppLocalization.string("等待重启安装")
        case .installing:
            return AppLocalization.string("正在安装更新")
        case .error:
            return AppLocalization.string("重试更新")
        }
    }

    private var updateSubtitle: String {
        switch updateManager.state {
        case .idle:
            return updateManager.isConfigured
                ? AppLocalization.string(
                    settings.automaticUpdateChecksEnabled
                        ? "启动时和空闲时自动检查、下载并安装更新"
                        : "自动更新已关闭，可随时手动检查"
                )
                : updateManager.configurationStatus.message
        case .upToDate:
            return AppLocalization.string("当前已经是最新版本")
        case .checking:
            return AppLocalization.string("正在后台检查更新")
        case .found(let version, _):
            return AppLocalization.format("发现新版本 v%@，将静默下载并安装", version)
        case .downloading:
            return AppLocalization.string("正在后台下载更新")
        case .extracting:
            return AppLocalization.string("正在准备安装更新")
        case .readyToInstall(let version):
            return AppLocalization.format("v%@ 已就绪，可立即重启安装，或等空闲时自动安装", version)
        case .installing:
            return AppLocalization.string("正在静默安装并重启")
        case .error:
            return AppLocalization.string("后台更新失败，点击后重新检查")
        }
    }

    @ViewBuilder
    private var updateAccessory: some View {
        switch updateManager.state {
        case .checking, .downloading, .extracting, .installing:
            ProgressView()
                .controlSize(.small)
        case .upToDate:
            Text(appLocalized: "最新")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(TerminalColors.green)
        case .found(let version, _), .readyToInstall(let version):
            Text("v\(version)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(TerminalColors.green)
        case .idle, .error:
            Image(systemName: "arrow.right.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(.white.opacity(0.55))
        }
    }

    private func handleUpdateAction() {
        switch updateManager.state {
        case .idle, .upToDate, .error:
            updateManager.checkForUpdates()
        case .checking, .found, .downloading, .extracting, .readyToInstall, .installing:
            break
        }
    }
}
