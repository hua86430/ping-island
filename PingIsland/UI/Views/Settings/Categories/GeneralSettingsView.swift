import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var viewModel: SettingsPanelViewModel
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSectionCard(title: "系统") {
                SettingsInfoLine(
                    title: "语言",
                    subtitle: "默认跟随系统语言，也可以单独固定为简体中文或 English。"
                ) {
                    appLanguagePicker
                }
                SettingsLineDivider()

                SettingsToggleLine(
                    title: "登录时打开",
                    subtitle: "启动 macOS 后自动显示 Island",
                    isOn: Binding(
                        get: { viewModel.launchAtLogin },
                        set: { viewModel.setLaunchAtLogin($0) }
                    )
                )
                SettingsLineDivider()

                SettingsInfoLine(title: "显示器", subtitle: "选择 Island 所在显示器") {
                    SettingsScreenPicker()
                }
            }

            SettingsSectionCard(title: "行为") {
                SettingsToggleLine(
                    title: "全屏时隐藏",
                    subtitle: "无刘海屏会在全屏时收起到顶部中央触发区；刘海屏会收缩为空白系统刘海，hover 后再展示 Island 内容",
                    isOn: $settings.hideInFullscreen
                )
                SettingsLineDivider()

                SettingsToggleLine(
                    title: "无活跃会话时自动隐藏",
                    subtitle: "当前没有正在运行或需要处理的会话时，自动隐藏 Island",
                    isOn: $settings.autoHideWhenIdle
                )
                SettingsLineDivider()

                SettingsToggleLine(
                    title: "智能抑制",
                    subtitle: "当前正在看终端时，不自动弹出通知面板",
                    isOn: $settings.smartSuppression
                )
                SettingsLineDivider()

                SettingsToggleLine(
                    title: "完成时自动展开会话",
                    subtitle: "消息完成后自动弹出结果面板；关闭后只保留刘海状态提示和提示音",
                    isOn: $settings.autoOpenCompletionPanel
                )
                SettingsLineDivider()

                SettingsToggleLine(
                    title: "上下文压缩时自动展开提醒",
                    subtitle: "上下文压缩后自动弹出提示；关闭后只保留刘海状态提示和提示音",
                    isOn: $settings.autoOpenCompactedNotificationPanel
                )
                SettingsLineDivider()

                SettingsToggleLine(
                    title: "鼠标离开时自动收起",
                    subtitle: "hover 展开的预览面板会在鼠标离开后自动关闭",
                    isOn: $settings.autoCollapseOnLeave
                )
            }

            SettingsSectionCard(title: "应用") {
                SettingsActionLine(
                    title: "退出应用",
                    subtitle: "立即关闭 Island"
                ) {
                    NSApplication.shared.terminate(nil)
                } accessory: {
                    Image(systemName: "power")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.72))
                }
            }
        }
    }

    private var appLanguagePicker: some View {
        Picker("语言", selection: $settings.appLanguage) {
            ForEach(AppLanguage.allCases) { language in
                Text(appLocalized: language.title).tag(language)
            }
        }
        .labelsHidden()
        .settingsMenuPicker(width: 168)
    }
}
