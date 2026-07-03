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
    @State private var selectedCategory: SettingsCategory? = .general
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
                        RemoteSettingsView()
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















