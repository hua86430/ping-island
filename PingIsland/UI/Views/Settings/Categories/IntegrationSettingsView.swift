import AppKit
import SwiftUI

struct IntegrationSettingsView: View {
    @ObservedObject var viewModel: SettingsPanelViewModel
    @ObservedObject private var settings = AppSettings.shared
    @State private var pendingHookReinstallProfile: ManagedHookClientProfile?
    @State private var pendingHookOptionsRequest: HookInstallOptionsRequest?
    @State private var showingUninstallAllHooksConfirmation = false
    @State private var showingCustomHookInstallSheet = false

    var body: some View {
        content
        .alert(
            "重新安装 Hooks？",
            isPresented: Binding(
                get: { pendingHookReinstallProfile != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingHookReinstallProfile = nil
                    }
                }
            ),
            presenting: pendingHookReinstallProfile
        ) { profile in
            Button("取消", role: .cancel) {}
            Button("重新安装") {
                viewModel.reinstallHooks(for: profile)
                pendingHookReinstallProfile = nil
            }
        } message: { profile in
            Text(verbatim: AppLocalization.format(profile.reinstallDescriptionFormat, profile.title))
        }
        .alert(
            AppLocalization.string("一键卸载所有 Hooks 配置文件？"),
            isPresented: $showingUninstallAllHooksConfirmation
        ) {
            Button(AppLocalization.string("取消"), role: .cancel) {}
            Button(AppLocalization.string("一键卸载所有 Hooks 配置文件"), role: .destructive) {
                viewModel.uninstallAllHooks()
            }
        } message: {
            Text(appLocalized: "这会移除 Island 为所有本机集成写入的托管 Hooks 配置文件，包括自定义配置记录。")
        }
        .sheet(isPresented: $showingCustomHookInstallSheet) {
            CustomHookInstallSheet(viewModel: viewModel) {
                showingCustomHookInstallSheet = false
            }
        }
        .sheet(item: $pendingHookOptionsRequest) { request in
            HookInstallOptionsSheet(
                profile: request.profile,
                mode: request.mode,
                initialSelection: viewModel.currentHookSelection(for: request.profile),
                onConfirm: { selection in
                    switch request.mode {
                    case .install:
                        viewModel.installHooks(for: request.profile, selection: selection)
                    case .edit:
                        viewModel.reinstallHooks(for: request.profile, selection: selection)
                    }
                    pendingHookOptionsRequest = nil
                },
                onDismiss: {
                    pendingHookOptionsRequest = nil
                }
            )
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSectionCard(title: "审批与提问") {
                SettingsToggleLine(
                    title: "保留终端中的提问与审批",
                    subtitle: "开启后终端中的 Claude / Codex 审批仍会保留；如果 Island 有可回写的审批请求，也可以直接在 Island 里批准或拒绝。",
                    isOn: $settings.routePromptsToTerminal
                )
                SettingsLineDivider()

                SettingsToggleLine(
                    title: "让终端处理 Claude 的提问",
                    subtitle: "开启后 Claude 的 AskUserQuestion 改由终端原生菜单处理，灵动岛不再显示该提问；下一个 Claude session 生效。",
                    isOn: $settings.terminalHandlesAskUserQuestion
                )
                SettingsLineDivider()

                SettingsToggleLine(
                    title: "空閒時自動保留到終端機",
                    subtitle: "鍵盤和滑鼠閒置達到設定時間後暫時開啟上方策略；恢復活躍後回到手動設定。",
                    isOn: $settings.autoRoutePromptsToTerminalWhenIdleEnabled
                )
                SettingsLineDivider()

                SettingsInfoLine(
                    title: "閒置時間",
                    subtitle: settings.idleAutoRoutePromptsToTerminalActive
                        ? "目前已進入空閒保護，後續新核准和提問會保留在終端機。"
                        : "達到該時長後自動進入空閒保護。"
                ) {
                    AutoRoutePromptsIdleDelayPicker(delay: $settings.autoRoutePromptsIdleDelay)
                        .disabled(!settings.autoRoutePromptsToTerminalWhenIdleEnabled)
                        .opacity(settings.autoRoutePromptsToTerminalWhenIdleEnabled ? 1 : 0.45)
                }
                SettingsLineDivider()

                SettingsToggleLine(
                    title: "通知中心模式",
                    subtitle: "开启后展开的岛只显示有新动态的 session（未读），点一下跳到终端并清除该通知；右上角可清除全部。关闭则显示全部 session。",
                    isOn: $settings.notificationFeedMode
                )
            }

            SettingsSectionCard(title: "Hook 调试日志") {
                SettingsToggleLine(
                    title: "记录 Hook 调试日志",
                    subtitle: "关闭后 bridge 不再追加 ~/.ping-island-debug 下的 hook 调试记录，并在下次 hook 触发时清理既有日志。",
                    isOn: $settings.hookDebugLoggingEnabled
                )
                SettingsLineDivider()

                SettingsSliderLine(
                    title: "日志保留天数",
                    subtitle: "超过该天数的 hook 调试日志会被自动删除。",
                    value: Binding(
                        get: { Double(settings.hookDebugLogRetentionDays) },
                        set: { settings.hookDebugLogRetentionDays = Int($0.rounded()) }
                    ),
                    range: Double(BridgeRuntimeConfigSnapshot.minimumDebugLogRetentionDays)...Double(BridgeRuntimeConfigSnapshot.maximumDebugLogRetentionDays),
                    step: 1,
                    format: { "\(Int($0.rounded())) 天" }
                )
                .disabled(!settings.hookDebugLoggingEnabled)
                .opacity(settings.hookDebugLoggingEnabled ? 1 : 0.45)
                SettingsLineDivider()

                SettingsSliderLine(
                    title: "最大日志占用",
                    subtitle: "当 ~/.ping-island-debug 超过该大小时，会优先删除最旧的 hook 调试日志。",
                    value: Binding(
                        get: { Double(settings.hookDebugLogMaxDirectoryMegabytes) },
                        set: { settings.hookDebugLogMaxDirectoryMegabytes = Int($0.rounded()) }
                    ),
                    range: Double(BridgeRuntimeConfigSnapshot.minimumDebugLogMaxDirectoryMegabytes)...Double(BridgeRuntimeConfigSnapshot.maximumDebugLogMaxDirectoryMegabytes),
                    step: 16,
                    format: { "\(Int($0.rounded())) MB" }
                )
                .disabled(!settings.hookDebugLoggingEnabled)
                .opacity(settings.hookDebugLoggingEnabled ? 1 : 0.45)
            }

#if APP_STORE
            SettingsSectionCard(title: "App Store 沙箱") {
                SettingsInfoLine(
                    title: "需要手动授权目录",
                    subtitle: "App Store 版本不会默认写入 ~/.claude、~/.codex 等配置。安装或重装 Hooks 时，请在系统弹窗中授权用户主目录。"
                ) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(TerminalColors.amber)
                }

                SettingsLineDivider()

                SettingsInfoLine(
                    title: "Bridge 链路自检",
                    subtitle: viewModel.bridgeHealthStatus.message
                ) {
                    HStack(spacing: 10) {
                        Text(appLocalized: viewModel.bridgeHealthStatus.isHealthy ? "正常" : "异常")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(viewModel.bridgeHealthStatus.isHealthy ? TerminalColors.green : TerminalColors.amber)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule(style: .continuous)
                                    .fill((viewModel.bridgeHealthStatus.isHealthy ? TerminalColors.green : TerminalColors.amber).opacity(0.16))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder((viewModel.bridgeHealthStatus.isHealthy ? TerminalColors.green : TerminalColors.amber).opacity(0.28), lineWidth: 1)
                            )

                        HookManagementButton(
                            title: "重新检测",
                            tint: TerminalColors.blue,
                            action: {
                                viewModel.refreshBridgeHealthStatus()
                            }
                        )
                    }
                }
            }
#endif

            let hookProfiles = viewModel.visibleHookProfiles
            if !hookProfiles.isEmpty {
                SettingsSectionCard(title: "Hooks 管理") {
                    let profiles = hookProfiles
                    ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                        HookManagementLine(
                            profile: profile,
                            isInstalled: viewModel.isHookInstalled(profile),
                            isReinstalling: viewModel.isReinstallingHooks(for: profile),
                            reinstallFeedback: viewModel.hookReinstallFeedback(for: profile),
                            noticeMessage: viewModel.hookNotice(for: profile),
                            supportsEventSelection: profile.supportsEventSelection,
                            installAction: {
                                if profile.supportsEventSelection {
                                    pendingHookOptionsRequest = HookInstallOptionsRequest(
                                        profile: profile,
                                        mode: .install
                                    )
                                } else {
                                    viewModel.installHooks(for: profile)
                                }
                            },
                            configureAction: {
                                pendingHookOptionsRequest = HookInstallOptionsRequest(
                                    profile: profile,
                                    mode: .edit
                                )
                            },
                            openConfigurationDirectoryAction: {
                                viewModel.openHookConfigurationDirectory(for: profile)
                            },
                            reinstallAction: { pendingHookReinstallProfile = profile },
                            uninstallAction: { viewModel.uninstallHooks(for: profile) }
                        )

                        if index < profiles.count - 1
                            || !viewModel.customHookInstallations.isEmpty {
                            SettingsLineDivider()
                        }
                    }

                    let customInstallations = viewModel.customHookInstallations
                    ForEach(Array(customInstallations.enumerated()), id: \.element.id) { index, installation in
                        CustomHookInstallationLine(
                            installation: installation,
                            uninstallAction: { viewModel.uninstallCustomHook(id: installation.id) }
                        )

                        if index < customInstallations.count - 1 {
                            SettingsLineDivider()
                        }
                    }

                    SettingsLineDivider()

                    HStack {
                        Spacer()
                        Button(action: { showingCustomHookInstallSheet = true }) {
                            HStack(spacing: 6) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                Text(appLocalized: "添加自定义配置")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                }
            }

            let ideProfiles = viewModel.visibleIDEExtensionProfiles
            if !ideProfiles.isEmpty {
                SettingsSectionCard(title: "IDE 扩展") {
                    let profiles = ideProfiles
                    ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                        IDEExtensionManagementLine(
                            profile: profile,
                            isInstalled: viewModel.isIDEExtensionInstalled(profile),
                            installAction: { viewModel.installIDEExtension(for: profile) },
                            reinstallAction: { viewModel.reinstallIDEExtension(for: profile) },
                            authorizeAction: { viewModel.authorizeIDEExtension(for: profile) },
                            uninstallAction: { viewModel.uninstallIDEExtension(for: profile) }
                        )

                        if index < profiles.count - 1 {
                            SettingsLineDivider()
                        }
                    }
                }
            }

            SettingsSectionCard(title: "演示") {
                SettingsActionLine(
                    title: "重新体验首次引导",
                    subtitle: "手动打开形态选择引导；选择刘海屏或独立悬浮宠物后，会继续进入 Hooks 演示。"
                ) {
                    replayFirstRunOnboardingDemo()
                } accessory: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(SettingsCategory.integration.tint.opacity(0.95))
                }
                SettingsLineDivider()

                SettingsActionLine(
                    title: "体验 Hooks 演示",
                    subtitle: "启动一轮可交互案例：干净桌面背景、审批提交、处理完成、完成提醒。顶部 Island 与独立悬浮宠物都支持。"
                ) {
                    SettingsWindowController.shared.dismiss()
                    HookWalkthroughDemoRunner.shared.start()
                } accessory: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(TerminalColors.blue.opacity(0.95))
                }
            }

#if !APP_STORE
            SettingsSectionCard(title: "系统权限") {
                SettingsStatusLine(
                    title: "辅助功能",
                    subtitle: viewModel.accessibilityEnabled ? "已授权，可进行窗口聚焦与前台检测" : "未授权，部分自动聚焦能力不可用",
                    status: viewModel.accessibilityEnabled ? "已开启" : "待开启",
                    statusColor: viewModel.accessibilityEnabled ? TerminalColors.green : TerminalColors.amber
                ) {
                    if !viewModel.accessibilityEnabled {
                        viewModel.openAccessibilitySettings()
                    }
                }
            }
#endif

            Button(action: { showingUninstallAllHooksConfirmation = true }) {
                HStack(spacing: 7) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .semibold))
                    Text(appLocalized: "一键卸载所有 Hooks 配置文件")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(TerminalColors.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(appLocalized: "一键卸载所有 Hooks 配置文件"))
        }
        .onChange(of: settings.terminalHandlesAskUserQuestion) { _, _ in
            if let profile = ClientProfileRegistry.managedHookProfile(id: "claude-hooks"),
               HookInstaller.isInstalled(profile) {
                viewModel.reinstallHooks(for: profile)
            }
        }
    }

    private func replayFirstRunOnboardingDemo() {
        SettingsWindowController.shared.dismiss()
        AppSettings.notchDetachmentHintPending = false
        AppSettings.floatingPetSettingsHintPending = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            PresentationModeWelcomeWindowController.shared.present { selectedMode in
                AppSettings.surfaceMode = selectedMode
                AppSettings.presentationModeOnboardingPending = false
                AppSettings.notchDetachmentHintPending = false
                AppSettings.floatingPetSettingsHintPending = false

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    HookWalkthroughDemoRunner.shared.start()
                }
            }
        }
    }
}

struct HookManagementLine: View {
    let profile: ManagedHookClientProfile
    let isInstalled: Bool
    let isReinstalling: Bool
    let reinstallFeedback: SettingsPanelViewModel.HookReinstallFeedback?
    let noticeMessage: String?
    let supportsEventSelection: Bool
    let installAction: () -> Void
    let configureAction: () -> Void
    let openConfigurationDirectoryAction: () -> Void
    let reinstallAction: () -> Void
    let uninstallAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                HookManagementIcon(profile: profile)

                VStack(alignment: .leading, spacing: 4) {
                    Text(appLocalized: title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)

                    Text(appLocalized: subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)

                    if let noticeMessage {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Circle()
                                .fill(TerminalColors.amber)
                                .frame(width: 6, height: 6)
                                .alignmentGuide(.firstTextBaseline) { context in
                                    context[VerticalAlignment.center]
                                }

                            Text(verbatim: noticeMessage)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(TerminalColors.amber.opacity(0.92))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 2)
                    }
                }

                Spacer(minLength: 12)

                Text(appLocalized: isInstalled ? "已安装" : "未安装")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isInstalled ? tint : .white.opacity(0.65))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill((isInstalled ? tint : .white).opacity(isInstalled ? 0.18 : 0.08))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder((isInstalled ? tint : .white).opacity(isInstalled ? 0.28 : 0.12), lineWidth: 1)
                    )
            }

            HStack(spacing: 10) {
                if isInstalled {
                    if supportsEventSelection {
                        HookManagementButton(
                            title: "配置",
                            tint: tint,
                            isDisabled: isReinstalling,
                            action: configureAction
                        )
                    }
                    HookManagementButton(
                        title: "打开配置目录",
                        tint: TerminalColors.blue,
                        isDisabled: isReinstalling,
                        action: openConfigurationDirectoryAction
                    )
                    HookManagementButton(
                        title: isReinstalling ? "重新安装中..." : "重新安装",
                        tint: tint,
                        isLoading: isReinstalling,
                        isDisabled: isReinstalling,
                        action: reinstallAction
                    )
                    HookManagementButton(
                        title: "卸载",
                        tint: TerminalColors.amber,
                        isDisabled: isReinstalling,
                        action: uninstallAction
                    )
                } else {
                    HookManagementButton(
                        title: "安装",
                        tint: tint,
                        isDisabled: isReinstalling,
                        action: installAction
                    )
                }
            }

            if let reinstallFeedback {
                HStack(spacing: 8) {
                    Image(systemName: reinstallFeedback.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(reinstallFeedback.isError ? TerminalColors.amber : TerminalColors.green)

                    Text(reinstallFeedback.message)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.76))
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var title: String {
        profile.title
    }

    private var subtitle: String {
        profile.subtitle
    }

    private var tint: Color {
        brandTint(profile.brand)
    }
}

struct CustomHookInstallationLine: View {
    let installation: HookInstaller.CustomHookInstallation
    let uninstallAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                if let profile = ClientProfileRegistry.managedHookProfile(id: installation.profileID) {
                    HookManagementIcon(profile: profile)
                } else {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(appLocalized: installation.profileTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)

                        Text(appLocalized: "自定义")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(TerminalColors.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(TerminalColors.blue.opacity(0.18))
                            )
                    }

                    Text(installation.customPath)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 12)

                Text(appLocalized: "已安装")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(TerminalColors.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(TerminalColors.green.opacity(0.18))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(TerminalColors.green.opacity(0.28), lineWidth: 1)
                    )
            }

            HStack(spacing: 10) {
                HookManagementButton(
                    title: "卸载",
                    tint: TerminalColors.amber,
                    action: uninstallAction
                )
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CustomHookInstallSheet: View {
    @ObservedObject var viewModel: SettingsPanelViewModel
    let onDismiss: () -> Void

    @State private var selectedProfileID: String = ""
    @State private var customPath: String = ""

    private var availableProfiles: [ManagedHookClientProfile] {
        ClientProfileRegistry.managedHookProfiles
    }

    private var canInstall: Bool {
        !selectedProfileID.isEmpty && !customPath.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(appLocalized: "添加自定义 Hook 配置")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(appLocalized: "选择应用")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))

                    Picker("", selection: $selectedProfileID) {
                        Text(appLocalized: "请选择...").tag("")
                        ForEach(availableProfiles) { profile in
                            Text(profile.title).tag(profile.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(appLocalized: "安装目录")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))

                    HStack(spacing: 8) {
                        TextField("", text: $customPath, prompt: Text(verbatim: installPathPlaceholder))
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(.white.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                            )

                        Button(action: selectDirectory) {
                            Text(appLocalized: "选择目录")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(.white.opacity(0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    if let resolvedFileName {
                        Text(resolvedInstallTargetDescription(resolvedFileName: resolvedFileName))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if let installHint {
                        Text(verbatim: installHint)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.45))
                    }
                }
            }

            HStack(spacing: 12) {
                Spacer()

                Button(action: onDismiss) {
                    Text(appLocalized: "取消")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button(action: install) {
                    Text(appLocalized: "安装")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(canInstall ? .white : .white.opacity(0.4))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(canInstall ? TerminalColors.blue.opacity(0.5) : .white.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(canInstall ? TerminalColors.blue.opacity(0.5) : .white.opacity(0.08), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canInstall)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
    }

    private var resolvedFileName: String? {
        guard let profile = ClientProfileRegistry.managedHookProfile(id: selectedProfileID),
              !customPath.isEmpty else {
            return nil
        }
        return profile.primaryConfigurationURL.lastPathComponent
    }

    private var installPathPlaceholder: String {
        guard let profile = ClientProfileRegistry.managedHookProfile(id: selectedProfileID) else {
            return "例如 /path/to/.claude"
        }

        switch profile.installationKind {
        case .jsonHooks, .tomlHooks:
            return "例如 /path/to/.claude"
        case .pluginFile:
            return "例如 /path/to/plugins"
        case .pluginDirectory:
            return "例如 /path/to/.hermes 或 /path/to/plugins"
        case .hookDirectory:
            return "例如 /path/to/.openclaw 或 /path/to/hooks"
        }
    }

    private var installHint: String? {
        guard let profile = ClientProfileRegistry.managedHookProfile(id: selectedProfileID) else {
            return nil
        }
        switch profile.installationKind {
        case .hookDirectory:
            return AppLocalization.string("OpenClaw 可选择 ~/.openclaw 根目录，或已配置到 extraDirs 的 hooks 目录。")
        case .pluginDirectory:
            return AppLocalization.string("Hermes 可选择 ~/.hermes 根目录，或 plugins 目录。")
        case .jsonHooks, .pluginFile, .tomlHooks:
            return nil
        }
    }

    private func resolvedInstallTargetDescription(resolvedFileName: String) -> String {
        guard let profile = ClientProfileRegistry.managedHookProfile(id: selectedProfileID) else {
            return AppLocalization.format("安装后将写入: %@/%@", customPath, resolvedFileName)
        }

        let baseURL = URL(fileURLWithPath: customPath)
        let targetURL: URL
        switch profile.installationKind {
        case .jsonHooks, .pluginFile, .tomlHooks:
            targetURL = baseURL.appendingPathComponent(resolvedFileName)
        case .pluginDirectory:
            if baseURL.lastPathComponent == ".hermes" {
                targetURL = baseURL
                    .appendingPathComponent("plugins", isDirectory: true)
                    .appendingPathComponent(resolvedFileName, isDirectory: true)
            } else if baseURL.lastPathComponent == "plugins" {
                targetURL = baseURL.appendingPathComponent(resolvedFileName, isDirectory: true)
            } else {
                targetURL = baseURL.appendingPathComponent(resolvedFileName, isDirectory: true)
            }
        case .hookDirectory:
            if baseURL.lastPathComponent == ".openclaw" {
                targetURL = baseURL
                    .appendingPathComponent("hooks", isDirectory: true)
                    .appendingPathComponent(resolvedFileName, isDirectory: true)
            } else if baseURL.lastPathComponent == "hooks" {
                targetURL = baseURL.appendingPathComponent(resolvedFileName, isDirectory: true)
            } else {
                targetURL = baseURL.appendingPathComponent(resolvedFileName, isDirectory: true)
            }
        }

        return AppLocalization.format("安装后将写入: %@", targetURL.path)
    }

    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.message = AppLocalization.string("选择 Hook 配置目录")
        panel.prompt = AppLocalization.string("选择")

        if panel.runModal() == .OK, let url = panel.url {
            customPath = url.path
        }
    }

    private func install() {
        guard canInstall else { return }
        viewModel.installCustomHook(profileID: selectedProfileID, directoryPath: customPath)
        onDismiss()
    }
}

enum HookInstallOptionsMode {
    case install
    case edit
}

struct HookInstallOptionsRequest: Identifiable {
    let id = UUID()
    let profile: ManagedHookClientProfile
    let mode: HookInstallOptionsMode
}

struct HookInstallOptionsSheet: View {
    let profile: ManagedHookClientProfile
    let mode: HookInstallOptionsMode
    let initialSelection: HookInstallSelection
    let onConfirm: (HookInstallSelection) -> Void
    let onDismiss: () -> Void

    @State private var enabledEventNames: Set<String>
    @State private var advancedExpanded: Bool

    init(
        profile: ManagedHookClientProfile,
        mode: HookInstallOptionsMode,
        initialSelection: HookInstallSelection,
        onConfirm: @escaping (HookInstallSelection) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.profile = profile
        self.mode = mode
        self.initialSelection = initialSelection
        self.onConfirm = onConfirm
        self.onDismiss = onDismiss
        _enabledEventNames = State(initialValue: initialSelection.enabledEventNames)
        _advancedExpanded = State(initialValue: false)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    categoryToggles
                    advancedSection
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 360)

            footer
        }
        .padding(24)
        .frame(width: 520)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            HookManagementIcon(profile: profile)

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: profile.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)

                Text(appLocalized: headerSubtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)
        }
    }

    private var categoryToggles: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(profile.availableEventCategories) { category in
                CategoryToggleRow(
                    category: category,
                    state: state(for: category),
                    onToggle: { toggleCategory(category) }
                )

                if category != profile.availableEventCategories.last {
                    Divider()
                        .overlay(Color.white.opacity(0.08))
                        .padding(.horizontal, 14)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var advancedSection: some View {
        DisclosureGroup(isExpanded: $advancedExpanded) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(profile.availableEventCategories) { category in
                    let events = profile.events(in: category)
                    if !events.isEmpty {
                        Text(appLocalized: category.title)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.5))
                            .padding(.horizontal, 14)
                            .padding(.top, 12)
                            .padding(.bottom, 4)

                        ForEach(events, id: \.name) { event in
                            EventToggleRow(
                                event: event,
                                isOn: enabledEventNames.contains(event.name),
                                onToggle: { toggleEvent(event.name) }
                            )
                        }
                    }
                }
            }
            .padding(.bottom, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
        } label: {
            Text(appLocalized: "高级 — 按事件单独配置")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.78))
        }
        .tint(.white.opacity(0.6))
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text(appLocalized: footerHint)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button(action: onDismiss) {
                Text(appLocalized: "取消")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button(action: confirm) {
                Text(appLocalized: confirmTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(canConfirm ? .white : .white.opacity(0.4))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(canConfirm ? brandTint(profile.brand).opacity(0.5) : .white.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(canConfirm ? brandTint(profile.brand).opacity(0.55) : .white.opacity(0.08), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canConfirm)
        }
    }

    private var headerSubtitle: String {
        switch mode {
        case .install:
            return "选择需要安装的 Hook 事件类别。可在高级中按单个事件微调。"
        case .edit:
            return "调整已安装的 Hook 事件，保存后会刷新该客户端的 hooks 配置。"
        }
    }

    private var footerHint: String {
        AppLocalization.string("默认全部启用；关闭某些事件后，对应通知或审批将不再触发。")
    }

    private var confirmTitle: String {
        switch mode {
        case .install: return "安装"
        case .edit: return "保存"
        }
    }

    private var canConfirm: Bool {
        !enabledEventNames.isEmpty
    }

    private func confirm() {
        guard canConfirm else { return }
        onConfirm(HookInstallSelection(enabledEventNames: enabledEventNames))
    }

    private func state(for category: HookInstallEventCategory) -> CategoryToggleState {
        let names = profile.events(in: category).map(\.name)
        guard !names.isEmpty else { return .off }
        let enabledCount = names.filter { enabledEventNames.contains($0) }.count
        if enabledCount == 0 { return .off }
        if enabledCount == names.count { return .on }
        return .mixed
    }

    private func toggleCategory(_ category: HookInstallEventCategory) {
        let names = profile.events(in: category).map(\.name)
        let currentState = state(for: category)
        switch currentState {
        case .on:
            for name in names { enabledEventNames.remove(name) }
        case .off, .mixed:
            for name in names { enabledEventNames.insert(name) }
        }
    }

    private func toggleEvent(_ name: String) {
        if enabledEventNames.contains(name) {
            enabledEventNames.remove(name)
        } else {
            enabledEventNames.insert(name)
        }
    }
}

enum CategoryToggleState {
    case on
    case off
    case mixed
}

struct CategoryToggleRow: View {
    let category: HookInstallEventCategory
    let state: CategoryToggleState
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: category.iconSymbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.78))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(0.06))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(appLocalized: category.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text(appLocalized: category.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button(action: onToggle) {
                indicator
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var indicator: some View {
        switch state {
        case .on:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(TerminalColors.green)
        case .mixed:
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(TerminalColors.amber)
        case .off:
            Image(systemName: "circle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white.opacity(0.3))
        }
    }
}

struct EventToggleRow: View {
    let event: HookInstallEventDescriptor
    let isOn: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(verbatim: event.name)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.86))

            if let timeout = event.timeout {
                Text(verbatim: "\(timeout)s")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(.white.opacity(0.05))
                    )
            }

            Spacer(minLength: 12)

            Button(action: onToggle) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(isOn ? TerminalColors.green : .white.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }
}

struct HookManagementIcon: View {
    let profile: ManagedHookClientProfile

    var body: some View {
        SettingsClientIcon(
            logoAssetName: profile.logoAssetName,
            prefersBundledLogoOverAppIcon: profile.prefersBundledLogoOverAppIcon,
            localAppBundleIdentifiers: profile.localAppBundleIdentifiers,
            iconSymbolName: profile.iconSymbolName
        )
    }
}

struct IDEExtensionManagementLine: View {
    let profile: ManagedIDEExtensionProfile
    let isInstalled: Bool
    let installAction: () -> Void
    let reinstallAction: () -> Void
    let authorizeAction: () -> Void
    let uninstallAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                IDEExtensionManagementIcon(profile: profile)

                VStack(alignment: .leading, spacing: 4) {
                    Text(appLocalized: profile.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)

                    Text(appLocalized: profile.subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Text(appLocalized: isInstalled ? "已安装" : "未安装")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(isInstalled ? tint : .white.opacity(0.65))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill((isInstalled ? tint : .white).opacity(isInstalled ? 0.18 : 0.08))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder((isInstalled ? tint : .white).opacity(isInstalled ? 0.28 : 0.12), lineWidth: 1)
                    )
            }

            HStack(spacing: 10) {
                if isInstalled {
                    HookManagementButton(title: "重新安装", tint: tint, action: reinstallAction)
                    HookManagementButton(title: "授权", tint: TerminalColors.blue, action: authorizeAction)
                    HookManagementButton(title: "卸载", tint: TerminalColors.amber, action: uninstallAction)
                } else {
                    HookManagementButton(title: "安装", tint: tint, action: installAction)
                }
            }

            if !isInstalled {
                Text(appLocalized: "安装完成后，如编辑器尚未识别扩展，请重启对应 IDE 再点击“授权”。")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.44))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tint: Color {
        ideTint(profile.id)
    }
}

struct IDEExtensionManagementIcon: View {
    let profile: ManagedIDEExtensionProfile

    var body: some View {
        SettingsClientIcon(
            logoAssetName: profile.logoAssetName,
            prefersBundledLogoOverAppIcon: profile.prefersBundledLogoOverAppIcon,
            localAppBundleIdentifiers: profile.localAppBundleIdentifiers,
            iconSymbolName: profile.iconSymbolName
        )
    }
}

struct SettingsClientIcon: View {
    let logoAssetName: String?
    let prefersBundledLogoOverAppIcon: Bool
    let localAppBundleIdentifiers: [String]
    let iconSymbolName: String

    var body: some View {
        if let preferredLogoAssetName {
            Image(preferredLogoAssetName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 34, height: 34)
                .shadow(color: Color.black.opacity(0.18), radius: 8, y: 3)
        } else if let resolvedAppIcon {
            Image(nsImage: resolvedAppIcon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 34, height: 34)
                .shadow(color: Color.black.opacity(0.18), radius: 8, y: 3)
        } else {
            Image(systemName: iconSymbolName)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 34, height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
        }
    }

    private var resolvedAppIcon: NSImage? {
        ClientAppLocator.icon(bundleIdentifiers: localAppBundleIdentifiers)
    }

    private var preferredLogoAssetName: String? {
        guard let logoAssetName else {
            return nil
        }

        return prefersBundledLogoOverAppIcon || resolvedAppIcon == nil
            ? logoAssetName
            : nil
    }
}

struct SettingsStatusLine: View {
    let title: String
    let subtitle: String?
    let status: String
    let statusColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 16) {
                    Text(appLocalized: title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)

                    Spacer(minLength: 12)

                    HStack(spacing: 10) {
                        Text(appLocalized: status)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(statusColor)

                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }

                if let subtitle {
                    Text(appLocalized: subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

func brandTint(_ brand: SessionClientBrand) -> Color {
    brand.tintColor
}

func ideTint(_ profileID: String) -> Color {
    switch profileID {
    case "vscode-extension":
        return Color(red: 0.15, green: 0.55, blue: 0.96)
    case "cursor-extension":
        return Color(red: 0.30, green: 0.72, blue: 0.98)
    case "codebuddy-extension":
        return Color(red: 0.98, green: 0.61, blue: 0.28)
    case "qoder-extension":
        return Color(red: 0.12, green: 0.88, blue: 0.56)
    default:
        return Color.white.opacity(0.72)
    }
}

struct AutoRoutePromptsIdleDelayPicker: View {
    @Binding var delay: AutoRoutePromptsIdleDelay

    var body: some View {
        Picker("", selection: $delay) {
            ForEach(AutoRoutePromptsIdleDelay.allCases) { candidate in
                Text(appLocalized: candidate.title).tag(candidate)
            }
        }
        .labelsHidden()
        .accessibilityLabel(Text(appLocalized: "閒置時間"))
        .settingsMenuPicker(width: 132)
    }
}
