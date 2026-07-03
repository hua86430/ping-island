import AppKit
import Carbon.HIToolbox
import SwiftUI

struct ShortcutsSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSectionCard(title: "全局快捷键") {
                ShortcutSettingsLine(
                    action: .openActiveSession,
                    shortcut: shortcutBinding(for: .openActiveSession)
                )
                SettingsLineDivider()
                ShortcutSettingsLine(
                    action: .openSessionList,
                    shortcut: shortcutBinding(for: .openSessionList)
                )
            }

            SettingsSectionCard(title: "说明") {
                SettingsInfoLine(
                    title: "默认键位",
                    subtitle: "默认使用 Option + J 打开活跃会话，Option + L 展开会话列表。"
                ) {
                    EmptyView()
                }
                SettingsLineDivider()

                SettingsInfoLine(
                    title: "录制规则",
                    subtitle: "录制状态下直接按新组合键即可；清空会关闭对应全局快捷键，重置按钮才会恢复默认。"
                ) {
                    EmptyView()
                }
                SettingsLineDivider()

                SettingsInfoLine(
                    title: "列表键盘操作",
                    subtitle: "呼出会话列表后，可用 ↑ / ↓ 选中会话，按 Enter 打开对应窗口。"
                ) {
                    EmptyView()
                }
            }
        }
    }

    private func shortcutBinding(for action: GlobalShortcutAction) -> Binding<GlobalShortcut?> {
        Binding(
            get: { settings.shortcut(for: action) },
            set: { settings.setShortcut($0, for: action) }
        )
    }
}

struct ShortcutSettingsLine: View {
    let action: GlobalShortcutAction
    @Binding var shortcut: GlobalShortcut?

    var body: some View {
        ShortcutRecorderControl(
            action: action,
            shortcut: $shortcut,
            defaultShortcut: action.defaultShortcut
        )
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ShortcutRecorderControl: View {
    let action: GlobalShortcutAction
    @Binding var shortcut: GlobalShortcut?
    let defaultShortcut: GlobalShortcut?

    @State private var isRecording = false
    @State private var helperTextKey: String?
    @State private var eventMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(appLocalized: action.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)

                    Text(appLocalized: action.subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                recordButton
            }

            HStack(alignment: .center, spacing: 8) {
                Text(appLocalized: "当前键位")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.40))

                if let shortcut {
                    ShortcutVisualLabel(
                        shortcut: shortcut,
                        fontSize: 11,
                        foregroundColor: .white.opacity(0.92),
                        keyBackground: Color.black.opacity(0.28),
                        keyBorder: Color.white.opacity(0.08),
                        keyMinWidth: 24,
                        keyHorizontalPadding: 7,
                        keyVerticalPadding: 5,
                        keyCornerRadius: 10
                    )
                } else {
                    Text(appLocalized: "未设置")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.42))
                }

                Spacer(minLength: 12)

                if shortcut != nil {
                    Button {
                        shortcut = nil
                        helperTextKey = nil
                        stopRecording()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(ShortcutIconButtonStyle())
                    .help(AppLocalization.string("清空快捷键"))
                    .accessibilityLabel(Text(appLocalized: "清空快捷键"))
                }

                if defaultShortcut != nil {
                    Button {
                        shortcut = defaultShortcut
                        helperTextKey = nil
                        stopRecording()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(ShortcutIconButtonStyle())
                    .help(AppLocalization.string("恢复默认快捷键"))
                    .accessibilityLabel(Text(appLocalized: "恢复默认快捷键"))
                }
            }

            Text(appLocalized: helperTextKey ?? (isRecording ? "录制中，按 Esc 取消，Delete 清空" : "需要同时按下至少一个修饰键"))
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(isRecording ? TerminalColors.green.opacity(0.90) : .white.opacity(0.42))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onDisappear {
            stopRecording()
        }
    }

    private var recordButton: some View {
        Button {
            toggleRecording()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isRecording ? "record.circle.fill" : "keyboard")
                    .font(.system(size: 11, weight: .bold))

                Text(appLocalized: isRecording ? "按下新快捷键" : "点击录制")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(isRecording ? .black : .white.opacity(0.88))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isRecording ? TerminalColors.green.opacity(0.96) : Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isRecording ? TerminalColors.green.opacity(0.9) : Color.white.opacity(0.10),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .help(AppLocalization.string(isRecording ? "停止录制快捷键" : "开始录制快捷键"))
        .accessibilityLabel(Text(appLocalized: isRecording ? "停止录制快捷键" : "开始录制快捷键"))
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        helperTextKey = nil
        isRecording = true

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handleRecording(event)
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false

        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    private func handleRecording(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            helperTextKey = nil
            stopRecording()
            return
        }

        if event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete) {
            shortcut = nil
            helperTextKey = nil
            stopRecording()
            return
        }

        guard let recordedShortcut = GlobalShortcut(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags
        ) else {
            helperTextKey = "需要同时按下至少一个修饰键"
            return
        }

        shortcut = recordedShortcut
        helperTextKey = nil
        stopRecording()
    }
}

struct ShortcutIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.white.opacity(configuration.isPressed ? 0.76 : 0.88))
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.11 : 0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.09), lineWidth: 1)
            )
    }
}
