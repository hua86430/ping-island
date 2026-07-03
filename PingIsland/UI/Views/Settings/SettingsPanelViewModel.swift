import AppKit
import Combine
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct QoderCLIHookRefreshNoticeGate {
    private static let defaultsKey = "SettingsPanel.qoderCLIHookRefreshNoticeShown.v1"

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func consumeShouldShowNotice() -> Bool {
        guard !defaults.bool(forKey: Self.defaultsKey) else {
            return false
        }

        defaults.set(true, forKey: Self.defaultsKey)
        return true
    }
}

struct ClosedNotchUsageAvailability: Equatable {
    var hasClaudeSevenDay = false
    var hasCodexSevenDay = false

    @MainActor
    static func current() -> ClosedNotchUsageAvailability {
        guard AppSettings.showUsage else {
            return ClosedNotchUsageAvailability()
        }

        let cachedClaudeSnapshot = UsageSnapshotCacheStore.loadClaude()
        let cachedCodexSnapshot = UsageSnapshotCacheStore.loadCodex()
        let claudeSnapshot = if cachedClaudeSnapshot?.sevenDay == nil {
            (try? ClaudeUsageLoader.load()) ?? cachedClaudeSnapshot
        } else {
            cachedClaudeSnapshot
        }
        let codexSnapshot = if cachedCodexSnapshot?.windows.contains(where: {
            UsageSummaryPresenter.isSevenDayWindowLabel($0.label)
        }) != true {
            (try? CodexUsageLoader.load()) ?? cachedCodexSnapshot
        } else {
            cachedCodexSnapshot
        }

        return ClosedNotchUsageAvailability(
            hasClaudeSevenDay: claudeSnapshot?.sevenDay != nil,
            hasCodexSevenDay: codexSnapshot?.windows.contains {
                UsageSummaryPresenter.isSevenDayWindowLabel($0.label)
            } == true
        )
    }

    func supports(_ mode: ClosedNotchTrailingContentMode) -> Bool {
        switch mode {
        case .sessionCount:
            return true
        case .claudeSevenDayRemaining:
            return hasClaudeSevenDay
        case .codexSevenDayRemaining:
            return hasCodexSevenDay
        }
    }
}

enum AccessibilityPermissionStatus {
#if APP_STORE
    static let isAvailable = false

    static func isTrusted(prompt: Bool = false) -> Bool {
        false
    }
#else
    static let isAvailable = true

    static func isTrusted(prompt: Bool = false) -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt
        ] as CFDictionary

        return AXIsProcessTrustedWithOptions(options)
    }
#endif
}

@MainActor
final class SettingsPanelViewModel: ObservableObject {
    struct HookReinstallFeedback: Equatable {
        let message: String
        let isError: Bool
    }

    @Published var launchAtLogin = false
    @Published private(set) var hookInstallationStates: [String: Bool] = [:]
    @Published private(set) var ideExtensionInstallationStates: [String: Bool] = [:]
    @Published var accessibilityEnabled = false
    @Published var isExportingLogs = false
    @Published var logExportStatus = AppLocalization.string("导出最近 10 分钟的 Island 诊断日志与配置")
    @Published private(set) var reinstallingHookProfileID: String?
    @Published private(set) var hookReinstallFeedbacks: [String: HookReinstallFeedback] = [:]
    @Published private(set) var customHookInstallations: [HookInstaller.CustomHookInstallation] = []
    @Published private(set) var qoderCLIHookRefreshStatus: HookInstaller.QoderCLIHookRefreshStatus?
    @Published private(set) var qoderCLIHookRefreshNoticeStatus: HookInstaller.QoderCLIHookRefreshStatus?
    @Published private(set) var closedNotchUsageAvailability = ClosedNotchUsageAvailability()
    @Published private(set) var bridgeHealthStatus = HookInstaller.BridgeHealthStatus(
        isHealthy: false,
        message: AppLocalization.string("Bridge 链路尚未检测")
    )

    private var hookFeedbackClearTasks: [String: Task<Void, Never>] = [:]
    private let qoderCLIHookRefreshStatusProvider: @MainActor () -> HookInstaller.QoderCLIHookRefreshStatus?
    private let qoderCLIHookRefreshNoticeGate: QoderCLIHookRefreshNoticeGate
    private let accessibilityStatusProvider: @MainActor (_ prompt: Bool) -> Bool
    private let accessibilitySettingsOpener: @MainActor () -> Void

    init(
        qoderCLIHookRefreshStatusProvider: @escaping @MainActor () -> HookInstaller.QoderCLIHookRefreshStatus? = {
            HookInstaller.qoderCLIHookRefreshStatus()
        },
        qoderCLIHookRefreshNoticeDefaults: UserDefaults = .standard,
        accessibilityStatusProvider: @escaping @MainActor (_ prompt: Bool) -> Bool = { prompt in
            AccessibilityPermissionStatus.isTrusted(prompt: prompt)
        },
        accessibilitySettingsOpener: @escaping @MainActor () -> Void = {
            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else {
                return
            }
            NSWorkspace.shared.open(url)
        }
    ) {
        self.qoderCLIHookRefreshStatusProvider = qoderCLIHookRefreshStatusProvider
        qoderCLIHookRefreshNoticeGate = QoderCLIHookRefreshNoticeGate(
            defaults: qoderCLIHookRefreshNoticeDefaults
        )
        self.accessibilityStatusProvider = accessibilityStatusProvider
        self.accessibilitySettingsOpener = accessibilitySettingsOpener
    }

    var visibleHookProfiles: [ManagedHookClientProfile] {
        let profiles = ClientProfileRegistry.managedHookProfiles.filter { profile in
            profile.alwaysVisibleInSettings
                || (profile.id == "qoder-cli-hooks" && qoderCLIHookRefreshStatus != nil)
                || ClientAppLocator.isInstalled(bundleIdentifiers: profile.localAppBundleIdentifiers)
        }

        return profiles.filter { $0.id != "gemini-hooks" }
            + profiles.filter { $0.id == "gemini-hooks" }
    }

    var hasIntegrationNotice: Bool {
        qoderCLIHookRefreshNoticeStatus != nil
    }

    var visibleIDEExtensionProfiles: [ManagedIDEExtensionProfile] {
        ClientProfileRegistry.ideExtensionProfiles.filter { profile in
            profile.showsInSettings
                && (
                    profile.alwaysVisibleInSettings
                || ClientAppLocator.isInstalled(bundleIdentifiers: profile.localAppBundleIdentifiers)
                )
        }
    }

    func refreshInitialState() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        refreshAccessibilityStatus()
        refreshLocalizedState()
    }

    func refresh(for category: SettingsCategory) {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        refreshAccessibilityStatus()
        refreshLocalizedState()

        switch category {
        case .display:
            ScreenSelector.shared.refreshScreens()
            refreshClosedNotchUsageAvailability()
        case .sound:
            SoundPackCatalog.shared.refresh()
        case .integration:
            refreshHookInstallationStates()
            refreshIDEExtensionInstallationStates()
            refreshCustomHookInstallations()
            refreshQoderCLIHookRefreshStatus()
            refreshBridgeHealthStatus()
        case .general, .shortcuts, .mascot, .analytics, .remote, .labs, .about:
            break
        }
    }

    func refreshAccessibilityStatus() {
        guard AccessibilityPermissionStatus.isAvailable else {
            accessibilityEnabled = false
            return
        }

        accessibilityEnabled = accessibilityStatusProvider(false)
    }

    func refreshLocalizedState() {
        guard !isExportingLogs else { return }
        logExportStatus = AppLocalization.string("导出最近 10 分钟的 Island 诊断日志与配置")
    }

    func refreshQoderCLIHookRefreshStatus() {
        let status = qoderCLIHookRefreshStatusProvider()
        qoderCLIHookRefreshStatus = status

        guard let status else {
            qoderCLIHookRefreshNoticeStatus = nil
            return
        }

        if qoderCLIHookRefreshNoticeStatus != nil {
            return
        }

        guard qoderCLIHookRefreshNoticeGate.consumeShouldShowNotice() else {
            qoderCLIHookRefreshNoticeStatus = nil
            return
        }

        qoderCLIHookRefreshNoticeStatus = status
    }

    func refreshClosedNotchUsageAvailability() {
        closedNotchUsageAvailability = ClosedNotchUsageAvailability.current()
    }

    func refreshBridgeHealthStatus() {
        bridgeHealthStatus = HookInstaller.bridgeHealthStatus()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    func isHookInstalled(_ profile: ManagedHookClientProfile) -> Bool {
        hookInstallationStates[profile.id] ?? false
    }

    func isIDEExtensionInstalled(_ profile: ManagedIDEExtensionProfile) -> Bool {
        ideExtensionInstallationStates[profile.id] ?? false
    }

    func installHooks(for profile: ManagedHookClientProfile) {
#if APP_STORE
        let didInstall = HookInstaller.installWithUserAuthorization(profile)
        if didInstall {
            AppSettings.hookInstallOnboardingPending = false
        }
#else
        HookInstaller.install(profile)
        let didInstall = HookInstaller.isInstalled(profile)
#endif
        Task {
            await TelemetryService.shared.recordHookInstall(
                profileID: profile.id,
                result: didInstall,
                source: AppSettings.hookInstallOnboardingPending ? "first_run" : "settings"
            )
        }
        refreshHookInstallationStates()
        refreshBridgeHealthStatus()
    }

    func installHooks(for profile: ManagedHookClientProfile, selection: HookInstallSelection) {
#if APP_STORE
        let didInstall = HookInstaller.installWithUserAuthorization(profile, selection: selection)
        if didInstall {
            AppSettings.hookInstallOnboardingPending = false
        }
#else
        HookInstaller.install(profile, selection: selection)
        let didInstall = HookInstaller.isInstalled(profile)
#endif
        Task {
            await TelemetryService.shared.recordHookInstall(
                profileID: profile.id,
                result: didInstall,
                source: AppSettings.hookInstallOnboardingPending ? "first_run" : "settings"
            )
        }
        refreshHookInstallationStates()
        refreshBridgeHealthStatus()
    }

    func reinstallHooks(for profile: ManagedHookClientProfile, selection: HookInstallSelection) {
        guard reinstallingHookProfileID == nil else { return }

        HookInstaller.saveSelection(selection, for: profile)

        hookFeedbackClearTasks[profile.id]?.cancel()
        hookFeedbackClearTasks[profile.id] = nil
        hookReinstallFeedbacks[profile.id] = nil
        reinstallingHookProfileID = profile.id

        Task {
            await Task.yield()

#if APP_STORE
            let didInstall = HookInstaller.reinstallWithUserAuthorization(profile, selection: selection)
#else
            HookInstaller.reinstall(profile)
            let didInstall = HookInstaller.isInstalled(profile)
#endif

            try? await Task.sleep(nanoseconds: 450_000_000)

            refreshHookInstallationStates()
            refreshBridgeHealthStatus()
            reinstallingHookProfileID = nil
            Task {
                await TelemetryService.shared.recordHookReinstall(profileID: profile.id, result: didInstall)
            }
            hookReinstallFeedbacks[profile.id] = HookReinstallFeedback(
                message: didInstall
                    ? AppLocalization.string("已更新 Hook 配置")
                    : AppLocalization.string("更新失败，请稍后重试"),
                isError: !didInstall
            )

            hookFeedbackClearTasks[profile.id] = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard !Task.isCancelled else { return }
                hookReinstallFeedbacks[profile.id] = nil
                hookFeedbackClearTasks[profile.id] = nil
            }
        }
    }

    func currentHookSelection(for profile: ManagedHookClientProfile) -> HookInstallSelection {
        HookInstaller.loadSelection(for: profile)
    }

    func reinstallHooks(for profile: ManagedHookClientProfile) {
        guard reinstallingHookProfileID == nil else { return }

        hookFeedbackClearTasks[profile.id]?.cancel()
        hookFeedbackClearTasks[profile.id] = nil
        hookReinstallFeedbacks[profile.id] = nil
        reinstallingHookProfileID = profile.id

        Task {
            await Task.yield()

#if APP_STORE
            let didInstall = HookInstaller.reinstallWithUserAuthorization(profile)
#else
            HookInstaller.reinstall(profile)
            let didInstall = HookInstaller.isInstalled(profile)
#endif

            try? await Task.sleep(nanoseconds: 450_000_000)

            refreshHookInstallationStates()
            refreshBridgeHealthStatus()
            reinstallingHookProfileID = nil
            hookReinstallFeedbacks[profile.id] = HookReinstallFeedback(
                message: didInstall
                    ? AppLocalization.string("重新安装成功")
                    : AppLocalization.string("重新安装失败，请稍后重试"),
                isError: !didInstall
            )

            hookFeedbackClearTasks[profile.id] = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard !Task.isCancelled else { return }
                hookReinstallFeedbacks[profile.id] = nil
                hookFeedbackClearTasks[profile.id] = nil
            }
        }
    }

    func uninstallHooks(for profile: ManagedHookClientProfile) {
#if APP_STORE
        guard HookInstaller.uninstallWithUserAuthorization(profile) else {
            return
        }
#else
        HookInstaller.uninstall(profile)
#endif
        refreshHookInstallationStates()
        refreshBridgeHealthStatus()
    }

    func installCustomHook(profileID: String, directoryPath: String) {
        HookInstaller.installCustom(profileID: profileID, directoryPath: directoryPath)
        refreshCustomHookInstallations()
    }

    func uninstallCustomHook(id: String) {
        HookInstaller.uninstallCustom(id: id)
        refreshCustomHookInstallations()
    }

    func uninstallAllHooks() {
#if APP_STORE
        guard HookInstaller.uninstallAllWithUserAuthorization() else {
            return
        }
#else
        HookInstaller.uninstall()
#endif
        for installation in HookInstaller.customInstallations() {
            HookInstaller.uninstallCustom(id: installation.id)
        }
        refreshHookInstallationStates()
        refreshCustomHookInstallations()
        refreshBridgeHealthStatus()
    }

    func refreshCustomHookInstallations() {
        customHookInstallations = HookInstaller.customInstallations()
    }

    func openHookConfigurationDirectory(for profile: ManagedHookClientProfile) {
        guard let directoryURL = hookConfigurationDirectoryURL(for: profile) else {
            return
        }

        NSWorkspace.shared.open(directoryURL)
    }

    func installIDEExtension(for profile: ManagedIDEExtensionProfile) {
        IDEExtensionInstaller.install(profile)
        refreshIDEExtensionInstallationStates()
    }

    func reinstallIDEExtension(for profile: ManagedIDEExtensionProfile) {
        IDEExtensionInstaller.reinstall(profile)
        refreshIDEExtensionInstallationStates()
    }

    func uninstallIDEExtension(for profile: ManagedIDEExtensionProfile) {
        IDEExtensionInstaller.uninstall(profile)
        refreshIDEExtensionInstallationStates()
    }

    func isReinstallingHooks(for profile: ManagedHookClientProfile) -> Bool {
        reinstallingHookProfileID == profile.id
    }

    func hookReinstallFeedback(for profile: ManagedHookClientProfile) -> HookReinstallFeedback? {
        hookReinstallFeedbacks[profile.id]
    }

    func hookNotice(for profile: ManagedHookClientProfile) -> String? {
        guard profile.id == "qoder-cli-hooks",
              let status = qoderCLIHookRefreshNoticeStatus else {
            return nil
        }

        return AppLocalization.format(
            "检测到 Qoder CLI %@；启动时会刷新 Island 托管的 Qoder CLI hooks，并保留同一 ~/.qoder/settings.json 内的 Qoder IDE hooks 与其他 JSON 配置。",
            status.version
        )
    }

    func authorizeIDEExtension(for profile: ManagedIDEExtensionProfile) {
        _ = IDEExtensionInstaller.authorize(profile)
    }

    func openAccessibilitySettings() {
        guard AccessibilityPermissionStatus.isAvailable else {
            accessibilityEnabled = false
            return
        }

        accessibilityEnabled = accessibilityStatusProvider(true)
        if !accessibilityEnabled {
            accessibilitySettingsOpener()
        }
    }

    func exportLogs() {
        guard !isExportingLogs else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = "PingIsland-Diagnostics-\(Self.archiveTimestamp()).zip"

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        isExportingLogs = true
        logExportStatus = AppLocalization.string("正在导出日志…")

        Task {
            do {
                let result = try await DiagnosticsExporter.shared.exportArchive(to: destinationURL)
                await MainActor.run {
                    if result.warnings.isEmpty {
                        logExportStatus = AppLocalization.format(
                            "已导出到 %@",
                            result.archiveURL.lastPathComponent
                        )
                    } else {
                        logExportStatus = AppLocalization.format(
                            "已导出，附带 %lld 条警告",
                            result.warnings.count
                        )
                    }
                    isExportingLogs = false
                }
            } catch {
                await MainActor.run {
                    logExportStatus = AppLocalization.format(
                        "导出失败：%@",
                        error.localizedDescription
                    )
                    isExportingLogs = false
                }
            }
        }
    }

    private static func archiveTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func refreshHookInstallationStates() {
        hookInstallationStates = ClientProfileRegistry.managedHookProfiles.reduce(into: [:]) { result, profile in
            result[profile.id] = HookInstaller.isInstalled(profile)
        }
    }

    private func refreshIDEExtensionInstallationStates() {
        ideExtensionInstallationStates = ClientProfileRegistry.ideExtensionProfiles.reduce(into: [:]) { result, profile in
            result[profile.id] = IDEExtensionInstaller.isInstalled(profile)
        }
    }

    private func hookConfigurationDirectoryURL(for profile: ManagedHookClientProfile) -> URL? {
        let fileManager = FileManager.default

        for configurationURL in profile.configurationURLs {
            var isDirectory = ObjCBool(false)
            guard fileManager.fileExists(atPath: configurationURL.path, isDirectory: &isDirectory) else {
                continue
            }

            return isDirectory.boolValue ? configurationURL : configurationURL.deletingLastPathComponent()
        }

        if let existingDirectory = profile.configurationURLs
            .map({ $0.deletingLastPathComponent() })
            .first(where: { fileManager.fileExists(atPath: $0.path) }) {
            return existingDirectory
        }

        return profile.primaryConfigurationURL.deletingLastPathComponent()
    }
}
