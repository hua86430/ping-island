import AppKit
import SwiftUI

enum SettingsPanelMetrics {
    static let windowSize = AppSettings.defaultSettingsWindowSize
    static let windowMinSize = AppSettings.minimumSettingsWindowSize
    static let windowMaxSize = AppSettings.maximumSettingsWindowSize
    static let windowSidebarWidth: CGFloat = 236
}

struct SettingsRootView: View {
    var onClose: (() -> Void)? = nil

    @StateObject private var viewModel = SettingsPanelViewModel()
    @ObservedObject private var settings = AppSettings.shared
    @State private var selectedCategory: SettingsCategory? = .general
    @State private var showingAnalyticsConsentPrompt = false
    @State private var consecutiveGeneralTapCount = 0
    @State private var isAccessibilityPollingActive = false
    @State private var arePreviewAnimationsActive = false
    @State private var loadingCategory: SettingsCategory?
    @State private var categoryRefreshTask: Task<Void, Never>?

    var body: some View {
        NavigationSplitView {
            SettingsSidebarView(
                selectedCategory: $selectedCategory,
                labsUnlocked: settings.labsSettingsUnlocked,
                hasIntegrationNotice: viewModel.hasIntegrationNotice,
                onTap: selectSidebarCategory
            )
            .navigationSplitViewColumnWidth(
                min: SettingsPanelMetrics.windowSidebarWidth,
                ideal: SettingsPanelMetrics.windowSidebarWidth,
                max: SettingsPanelMetrics.windowSidebarWidth + 60
            )
        } detail: {
            SettingsDetailRouter(
                currentCategory: currentCategory,
                loadingCategory: loadingCategory,
                viewModel: viewModel,
                onClose: onClose
            )
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
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
}
