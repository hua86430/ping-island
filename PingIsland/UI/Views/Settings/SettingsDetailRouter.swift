import SwiftUI

struct SettingsDetailRouter: View {
    let currentCategory: SettingsCategory
    let loadingCategory: SettingsCategory?
    @ObservedObject var viewModel: SettingsPanelViewModel
    var onClose: (() -> Void)?

    var body: some View {
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
                        MascotSettingsView()
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
        // Opaque dark base + within-window vibrancy. The previous full-panel
        // `.behindWindow` blur sampled and re-blurred the entire desktop behind the
        // (non-opaque) window every frame, so dragging any other window tanked
        // system-wide FPS. The dark fill stops desktop show-through (and gives the
        // vibrancy something in-window to sample) while keeping the frosted look.
        .background(
            ZStack {
                Color(white: 0.11)
                SettingsGlassSurface(material: .hudWindow, blendingMode: .withinWindow)
            }
            .ignoresSafeArea()
        )
    }
}

struct SettingsCategoryLoadingView: View {
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
