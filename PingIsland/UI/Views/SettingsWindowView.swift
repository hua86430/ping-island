import AppKit
import Carbon.HIToolbox
import Combine
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers



private struct SettingsCategoryLoadingView: View {
    let category: SettingsCategory

    var body: some View {
        SettingsSectionCard(title: category.title) {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                    .tint(.white.opacity(0.82))

                Text(verbatim: loadingTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white.opacity(0.88))

                Text(verbatim: loadingSubtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.54))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
        }
    }

    private var loadingTitle: String {
        AppLocalization.format("正在加载%@设置…", AppLocalization.string(category.title))
    }

    private var loadingSubtitle: String {
        switch category {
        case .display:
            return AppLocalization.string("正在刷新显示器与用量展示状态")
        case .sound:
            return AppLocalization.string("正在扫描可用声音主题包")
        case .integration:
            return AppLocalization.string("正在检查 Hooks、IDE 扩展与客户端安装状态")
        case .general, .shortcuts, .mascot, .analytics, .remote, .labs, .about:
            return AppLocalization.string("马上就好")
        }
    }
}


private enum SettingsPanelMetrics {
    static let windowSize = AppSettings.defaultSettingsWindowSize
    static let windowMinSize = AppSettings.minimumSettingsWindowSize
    static let windowMaxSize = AppSettings.maximumSettingsWindowSize
    static let windowSidebarWidth: CGFloat = 236
}

private struct SettingsPanelContentView: View {
    var onClose: (() -> Void)? = nil

    @StateObject private var viewModel = SettingsPanelViewModel()
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var screenSelector = ScreenSelector.shared
    @ObservedObject private var updateManager = UpdateManager.shared
    @ObservedObject private var remoteManager = RemoteConnectorManager.shared
    @State private var selectedCategory: SettingsCategory? = .general
    @State private var showingRemoteHostSheet = false
    @State private var remotePasswordPromptRequest: RemotePasswordPromptRequest?
    @State private var showingAnalyticsConsentPrompt = false
    @State private var consecutiveGeneralTapCount = 0
    @State private var isAccessibilityPollingActive = false
    @State private var arePreviewAnimationsActive = false
    @State private var loadingCategory: SettingsCategory?
    @State private var categoryRefreshTask: Task<Void, Never>?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(
                    min: SettingsPanelMetrics.windowSidebarWidth,
                    ideal: SettingsPanelMetrics.windowSidebarWidth,
                    max: SettingsPanelMetrics.windowSidebarWidth + 60
                )
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .ignoresSafeArea(.container, edges: .top)
        .frame(
            minWidth: SettingsPanelMetrics.windowMinSize.width,
            idealWidth: SettingsPanelMetrics.windowSize.width,
            maxWidth: SettingsPanelMetrics.windowMaxSize.width,
            minHeight: SettingsPanelMetrics.windowMinSize.height,
            idealHeight: SettingsPanelMetrics.windowSize.height,
            maxHeight: SettingsPanelMetrics.windowMaxSize.height
        )
        .preferredColorScheme(.dark)
        .environment(\.mascotAnimationsEnabled, arePreviewAnimationsActive)
        .onAppear {
            viewModel.refreshInitialState()
            let isVisible = currentWindow?.isVisible == true
            isAccessibilityPollingActive = isVisible
            arePreviewAnimationsActive = isVisible

            scheduleCategoryRefresh(for: currentCategory, showLoading: false)
            showAnalyticsConsentPromptIfNeeded()
        }
        .onDisappear {
            isAccessibilityPollingActive = false
            arePreviewAnimationsActive = false
            categoryRefreshTask?.cancel()
            categoryRefreshTask = nil
            loadingCategory = nil
        }
        .task(id: isAccessibilityPollingActive) {
            guard isAccessibilityPollingActive else { return }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                viewModel.refreshAccessibilityStatus()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsWindowVisibilityDidChange)) { notification in
            guard let isVisible = notification.userInfo?[SettingsWindowVisibilityNotification.isVisibleKey] as? Bool else {
                return
            }

            isAccessibilityPollingActive = isVisible
            arePreviewAnimationsActive = isVisible
            if isVisible {
                scheduleCategoryRefresh(for: currentCategory, showLoading: false)
                showAnalyticsConsentPromptIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .settingsWindowCategorySelectionRequested)) { notification in
            guard let rawCategory = notification.userInfo?[SettingsWindowCategorySelectionRequest.categoryKey] as? String,
                  let category = SettingsCategory(rawValue: rawCategory) else {
                return
            }

            selectSidebarCategory(category)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            scheduleCategoryRefresh(for: currentCategory, showLoading: false)
        }
        .onChange(of: settings.appLanguage) { _, _ in
            viewModel.refreshLocalizedState()
        }
        .alert(
            AppLocalization.string("帮助提升 Ping Island 体验？"),
            isPresented: $showingAnalyticsConsentPrompt
        ) {
            Button(AppLocalization.string("暂不开启"), role: .cancel) {
                settings.analyticsConsentPromptCompleted = true
            }
            Button(AppLocalization.string("同意开启")) {
                settings.analyticsEnabled = true
                settings.analyticsConsentPromptCompleted = true
            }
        } message: {
            Text(appLocalized: "仅发送匿名统计，用于了解启动、功能使用和 Hook 安装成功率。不会包含会话内容、代码、路径或主机信息。")
        }
        .sheet(isPresented: $showingRemoteHostSheet) {
            AddRemoteHostSheet(remoteManager: remoteManager) {
                showingRemoteHostSheet = false
            }
        }
        .sheet(item: $remotePasswordPromptRequest) { request in
            RemotePasswordPromptSheet(request: request) { password in
                remotePasswordPromptRequest = nil
                switch request.action {
                case .connect:
                    remoteManager.connect(endpointID: request.endpoint.id, password: password)
                case .uninstallBridge:
                    remoteManager.uninstallBridge(endpointID: request.endpoint.id, password: password)
                }
            } onDismiss: {
                remotePasswordPromptRequest = nil
            }
        }
    }

    private var sidebar: some View {
        List(selection: $selectedCategory) {
            ForEach(SettingsCategory.visibleCategories(labsUnlocked: settings.labsSettingsUnlocked)) { category in
                SidebarItemView(
                    category: category,
                    isSelected: selectedCategory == category,
                    showsNoticeDot: category == .integration && viewModel.hasIntegrationNotice
                )
                .tag(category)
                .listRowBackground(Color.clear)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        selectSidebarCategory(category)
                    }
                )
                .accessibilityIdentifier("settings.sidebar.\(category.rawValue)")
            }
        }
        .listStyle(.sidebar)
        .padding(.top, 28)
    }

    @ViewBuilder
    private var detail: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                if loadingCategory == currentCategory {
                    SettingsCategoryLoadingView(category: currentCategory)
                } else {
                    switch currentCategory {
                    case .general:
                        GeneralSettingsView(viewModel: viewModel)
                    case .shortcuts:
                        ShortcutsSettingsView()
                    case .display:
                        DisplaySettingsView(viewModel: viewModel, onClose: onClose)
                    case .mascot:
                        mascotContent
                    case .sound:
                        SoundSettingsContent()
                    case .analytics:
                        AgentUsageAnalyticsContent()
                    case .integration:
                        IntegrationSettingsView(viewModel: viewModel)
                    case .remote:
                        remoteContent
                    case .labs:
                        LabsSettingsView()
                    case .about:
                        AboutSettingsView(viewModel: viewModel)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 0)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(currentCategory)
        .accessibilityIdentifier("settings.detail.\(currentCategory.rawValue)")
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            SettingsGlassSurface(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
    }

    private var currentCategory: SettingsCategory {
        let category = selectedCategory ?? .general
        guard category != .labs || settings.labsSettingsUnlocked else {
            return .general
        }
        return category
    }

    private var currentWindow: NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow
    }

    private func selectSidebarCategory(_ category: SettingsCategory) {
        selectedCategory = category

        if !settings.labsSettingsUnlocked, category != .general {
            consecutiveGeneralTapCount = 0
        } else if !settings.labsSettingsUnlocked, category == .general {
            consecutiveGeneralTapCount += 1
        }

        if !settings.labsSettingsUnlocked, consecutiveGeneralTapCount >= 6 {
            settings.labsSettingsUnlocked = true
            // List's selection binding may write back .general after this handler;
            // defer the jump to .labs one runloop turn so it sticks.
            DispatchQueue.main.async {
                selectedCategory = .labs
                scheduleCategoryRefresh(for: .labs, showLoading: shouldShowLoading(for: .labs))
            }
            return
        }

        let categoryToRefresh = currentCategory
        scheduleCategoryRefresh(
            for: categoryToRefresh,
            showLoading: shouldShowLoading(for: categoryToRefresh)
        )
    }

    private func showAnalyticsConsentPromptIfNeeded() {
        guard !settings.analyticsConsentPromptCompleted,
              !settings.analyticsEnabled,
              !showingAnalyticsConsentPrompt else {
            return
        }
        showingAnalyticsConsentPrompt = true
    }

    private func shouldShowLoading(for category: SettingsCategory) -> Bool {
        switch category {
        case .display, .sound, .integration:
            return true
        case .general, .shortcuts, .mascot, .analytics, .remote, .labs, .about:
            return false
        }
    }

    private func scheduleCategoryRefresh(for category: SettingsCategory, showLoading: Bool) {
        categoryRefreshTask?.cancel()
        categoryRefreshTask = nil

        if showLoading {
            loadingCategory = category
        } else if loadingCategory == category {
            loadingCategory = nil
        }

        categoryRefreshTask = Task { @MainActor in
            if showLoading {
                try? await Task.sleep(nanoseconds: 80_000_000)
            } else {
                await Task.yield()
            }

            guard !Task.isCancelled else { return }
            viewModel.refresh(for: category)

            guard !Task.isCancelled else { return }
            if loadingCategory == category {
                loadingCategory = nil
            }
        }
    }






    private var mascotContent: some View {
        MascotSettingsView()
    }






    private var remoteContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSectionCard(title: "远程主机") {
                if remoteManager.endpoints.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(appLocalized: "还没有添加任何远程主机")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        Text(appLocalized: "添加后，Island 会通过 SSH 安装远程 bridge、改写远程 hooks，并建立一个双向转发通道。")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.58))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 8)
                } else {
                    let endpoints = remoteManager.endpoints
                    ForEach(Array(endpoints.enumerated()), id: \.element.id) { index, endpoint in
                        RemoteHostManagementLine(
                            endpoint: endpoint,
                            runtimeState: remoteManager.runtimeStates[endpoint.id] ?? RemoteEndpointRuntimeState(),
                            hasReusablePassword: remoteManager.hasReusablePassword(for: endpoint.id),
                            connectAction: { password in
                                remoteManager.connect(endpointID: endpoint.id, password: password)
                            },
                            requestConnectPasswordAction: {
                                remotePasswordPromptRequest = RemotePasswordPromptRequest(
                                    endpoint: endpoint,
                                    action: .connect
                                )
                            },
                            disconnectAction: { remoteManager.disconnect(endpointID: endpoint.id) },
                            uninstallAction: { password in
                                remoteManager.uninstallBridge(endpointID: endpoint.id, password: password)
                            },
                            requestUninstallPasswordAction: {
                                remotePasswordPromptRequest = RemotePasswordPromptRequest(
                                    endpoint: endpoint,
                                    action: .uninstallBridge
                                )
                            },
                            removeAction: { remoteManager.removeEndpoint(id: endpoint.id) }
                        )

                        if index < endpoints.count - 1 {
                            SettingsLineDivider()
                        }
                    }
                }

                SettingsLineDivider()

                HStack {
                    Spacer()
                    Button(action: { showingRemoteHostSheet = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                            Text(appLocalized: "添加远程主机")
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

            VStack(alignment: .leading, spacing: 12) {
                Text(appLocalized: "说明")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 10) {
                    Text(appLocalized: "添加远程主机后，Island 会通过 SSH 检查环境、安装远程 bridge，并配置 Hooks。")
                    Text(appLocalized: "连接成功后，远程会话会回传到本机显示；如果密码连接失败，需要重新输入密码。")
                    Text(appLocalized: "如果不再需要远端集成，可在这里直接卸载 bridge；这会删除远端 `~/.ping-island` 并撤回 Island 托管的 hooks。")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.62))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }






}

struct SettingsWindowView: View {
    var onClose: (() -> Void)? = nil

    var body: some View {
        AppLocalizedRootView {
            SettingsPanelContentView(onClose: onClose)
                .accessibilityIdentifier("settings.root")
        }
    }
}

private struct SidebarItemView: View {
    let category: SettingsCategory
    let isSelected: Bool
    var showsNoticeDot: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: category.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(isSelected ? 0.95 : 1))
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                isSelected
                                ? LinearGradient(
                                    colors: [
                                        category.tint.opacity(0.95),
                                        category.tint.opacity(0.60)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                                : LinearGradient(
                                    colors: [
                                        category.tint.opacity(0.92),
                                        category.tint.opacity(0.74)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                if showsNoticeDot {
                    Circle()
                        .fill(TerminalColors.amber)
                        .frame(width: 7, height: 7)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.black.opacity(0.42), lineWidth: 1)
                        )
                        .offset(x: 2, y: -2)
                        .accessibilityLabel("有需要注意的集成提示")
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(appLocalized: category.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(isSelected ? 0.94 : 0.80))
                    .lineLimit(1)

                Text(appLocalized: category.subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(isSelected ? 0.60 : 0.42))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.12) : Color.white.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(isSelected ? 0.10 : 0.04), lineWidth: 1)
        )
        .shadow(color: isSelected ? category.tint.opacity(0.18) : .clear, radius: 14, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}




private struct RemoteHostManagementLine: View {
    let endpoint: RemoteEndpoint
    let runtimeState: RemoteEndpointRuntimeState
    let hasReusablePassword: Bool
    let connectAction: (String?) -> Void
    let requestConnectPasswordAction: () -> Void
    let disconnectAction: () -> Void
    let uninstallAction: (String?) -> Void
    let requestUninstallPasswordAction: () -> Void
    let removeAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "network")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.orange.opacity(0.24))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(endpoint.resolvedTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)

                        Text(appLocalized: runtimeState.phase.titleKey)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(statusTint)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(statusTint.opacity(0.18))
                            )
                    }

                    if let sshURL = endpoint.sshURL {
                        Link(destination: sshURL) {
                            HStack(spacing: 4) {
                                Text(endpoint.sshURL?.absoluteString ?? endpoint.sshTarget)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Image(systemName: "arrow.up.right.square")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.52))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(endpoint.sshTarget)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.52))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Text(detailText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.60))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)
            }

            HStack(spacing: 10) {
                if runtimeState.phase == .connected {
                    HookManagementButton(
                        title: "断开",
                        tint: TerminalColors.amber,
                        isDisabled: isBusy
                    ) {
                        disconnectAction()
                    }
                } else {
                    HookManagementButton(
                        title: connectButtonTitle,
                        tint: TerminalColors.blue,
                        isLoading: isConnecting,
                        isDisabled: isBusy
                    ) {
                        if shouldPromptForPassword {
                            requestConnectPasswordAction()
                        } else {
                            connectAction(nil)
                        }
                    }
                }

                HookManagementButton(
                    title: "卸载",
                    tint: TerminalColors.amber,
                    isLoading: isUninstalling,
                    isDisabled: isBusy
                ) {
                    if shouldPromptForUninstallPassword {
                        requestUninstallPasswordAction()
                    } else {
                        uninstallAction(nil)
                    }
                }

                HookManagementButton(
                    title: "删除",
                    tint: TerminalColors.amber,
                    isDisabled: isBusy
                ) {
                    removeAction()
                }
            }

            if let lastError = localizedLastError {
                Text(verbatim: lastError)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(TerminalColors.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailText: String {
        var parts: [String] = [runtimeState.detail]
        if let detectedHostname = endpoint.detectedHostname, !detectedHostname.isEmpty {
            parts.append(detectedHostname)
        }
        parts.append(AppLocalization.string(authenticationDetail))
        if let agentVersion = runtimeState.agentVersion ?? endpoint.agentVersion {
            parts.append("Agent \(agentVersion)")
        }
        return parts.map { AppLocalization.string($0) }.joined(separator: " · ")
    }

    private var shouldPromptForPassword: Bool {
        runtimeState.requiresPassword || (endpoint.authMode == .passwordSession && !hasReusablePassword)
    }

    private var shouldPromptForUninstallPassword: Bool {
        runtimeState.requiresPassword || (endpoint.authMode == .passwordSession && !hasReusablePassword)
    }

    private var isConnecting: Bool {
        switch runtimeState.phase {
        case .probing, .bootstrapping, .connecting:
            return true
        case .disconnected, .uninstalling, .connected, .degraded, .failed:
            return false
        }
    }

    private var isUninstalling: Bool {
        runtimeState.phase == .uninstalling
    }

    private var isBusy: Bool {
        isConnecting || isUninstalling
    }

    private var connectButtonTitle: String {
        if isConnecting {
            return "连接中"
        }

        return shouldPromptForPassword ? "输入密码并连接" : "连接"
    }

    private var authenticationDetail: String {
        switch endpoint.authMode {
        case .passwordSession:
            return hasReusablePassword ? "密码已保存" : "需要重新输入密码"
        default:
            return endpoint.authMode.titleKey
        }
    }

    private var statusTint: Color {
        switch runtimeState.phase {
        case .connected:
            return TerminalColors.green
        case .failed, .degraded:
            return TerminalColors.amber
        case .connecting, .probing, .bootstrapping:
            return TerminalColors.blue
        case .uninstalling:
            return TerminalColors.amber
        case .disconnected:
            return .white.opacity(0.68)
        }
    }

    private var localizedLastError: String? {
        guard let lastError = runtimeState.lastError, !lastError.isEmpty else {
            return nil
        }

        let attachDisconnectPrefix = "SSH attach 已断开: "
        if lastError.hasPrefix(attachDisconnectPrefix) {
            let detail = String(lastError.dropFirst(attachDisconnectPrefix.count))
            return AppLocalization.format("SSH attach 已断开: %@", detail)
        }

        return AppLocalization.string(lastError)
    }
}

private struct AddRemoteHostSheet: View {
    @ObservedObject var remoteManager: RemoteConnectorManager
    let onDismiss: () -> Void

    @State private var displayName = ""
    @State private var sshTarget = ""
    @State private var sshPort = "\(RemoteSSHLink.defaultPort)"
    @State private var password = ""

    private var parsedPort: Int? {
        guard let port = Int(sshPort.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...65_535).contains(port) else {
            return nil
        }
        return port
    }

    private var canAdd: Bool {
        !sshTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && parsedPort != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(appLocalized: "添加远程主机")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 14) {
                remoteField(title: "显示名称（可选）", placeholder: "例如 GPU Box", text: $displayName)
                remoteField(title: "SSH 目标", placeholder: "例如 dev@10.0.0.8 或 my-server", text: $sshTarget)
                remoteField(title: "端口", placeholder: "22", text: $sshPort)

                VStack(alignment: .leading, spacing: 6) {
                    Text(appLocalized: "密码（可选）")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))

                    SecureField("", text: $password, prompt: Text(appLocalized: "连接成功后后续可直接重连"))
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .submitLabel(.go)
                        .onSubmit {
                            addAndConnect()
                        }
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
                }

                if sshPort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                   parsedPort == nil {
                    Text(appLocalized: "端口需为 1 到 65535")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(TerminalColors.amber)
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

                Button(action: addAndConnect) {
                    Text(appLocalized: "保存并连接")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(canAdd ? .white : .white.opacity(0.4))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(canAdd ? TerminalColors.blue.opacity(0.5) : .white.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(canAdd ? TerminalColors.blue.opacity(0.5) : .white.opacity(0.08), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdd)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func remoteField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(appLocalized: title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))

            TextField("", text: text, prompt: Text(appLocalized: placeholder))
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
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
        }
    }

    private func addAndConnect() {
        guard let port = parsedPort, canAdd else { return }
        let endpoint = remoteManager.addEndpoint(displayName: displayName, sshTarget: sshTarget, sshPort: port)
        remoteManager.connect(
            endpointID: endpoint.id,
            password: password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : password
        )
        onDismiss()
    }
}

private enum RemotePasswordPromptAction: String {
    case connect
    case uninstallBridge

    var titleFormat: String {
        switch self {
        case .connect:
            return "连接 %@"
        case .uninstallBridge:
            return "卸载 %@ 的 bridge"
        }
    }

    var submitTitle: String {
        switch self {
        case .connect:
            return "连接"
        case .uninstallBridge:
            return "卸载"
        }
    }
}

private struct RemotePasswordPromptRequest: Identifiable {
    let endpoint: RemoteEndpoint
    let action: RemotePasswordPromptAction

    var id: String {
        "\(endpoint.id.uuidString)-\(action.rawValue)"
    }
}

private struct RemotePasswordPromptSheet: View {
    let request: RemotePasswordPromptRequest
    let onSubmit: (String) -> Void
    let onDismiss: () -> Void

    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(verbatim: AppLocalization.format(request.action.titleFormat, request.endpoint.resolvedTitle))
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.white)

            if let sshURL = request.endpoint.sshURL {
                Link(destination: sshURL) {
                    HStack(spacing: 4) {
                        Text(request.endpoint.sshURL?.absoluteString ?? request.endpoint.sshTarget)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.56))
                }
                .buttonStyle(.plain)
            } else {
                Text(request.endpoint.sshTarget)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.56))
            }

            SecureField("", text: $password, prompt: Text(appLocalized: "输入 SSH 密码"))
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .submitLabel(.go)
                .onSubmit {
                    submitPassword()
                }
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

                Button(action: submitPassword) {
                    Text(appLocalized: request.action.submitTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(password.isEmpty ? .white.opacity(0.4) : .white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(password.isEmpty ? .white.opacity(0.04) : buttonTint.opacity(0.5))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(password.isEmpty ? .white.opacity(0.08) : buttonTint.opacity(0.5), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .disabled(password.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
    }

    private func submitPassword() {
        guard !password.isEmpty else { return }
        onSubmit(password)
    }

    private var buttonTint: Color {
        switch request.action {
        case .connect:
            return TerminalColors.blue
        case .uninstallBridge:
            return TerminalColors.amber
        }
    }
}











