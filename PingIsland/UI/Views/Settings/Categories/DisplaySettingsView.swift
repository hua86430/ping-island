import AppKit
import SwiftUI

struct DisplaySettingsView: View {
    @ObservedObject var viewModel: SettingsPanelViewModel
    var onClose: (() -> Void)?
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var screenSelector = ScreenSelector.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSectionCard(title: "显示器") {
                SettingsInfoLine(
                    title: "当前显示器",
                    subtitle: "切换后会重新挂载 Island 窗口位置"
                ) {
                    SettingsScreenPicker()
                }
                SettingsLineDivider()

                if let selectedScreen = screenSelector.selectedScreen {
                    SettingsValueLine(
                        title: "当前输出",
                        value: selectedScreen.localizedName
                    )
                }
            }

            SettingsSectionCard(title: "选单栏图标") {
                MenuBarIconStylePicker(style: $settings.menuBarIconStyle)
            }

            SettingsSectionCard(title: "面板") {
                IslandSurfaceModeSelector(mode: $settings.surfaceMode)
                SettingsLineDivider()

                SettingsInfoLine(
                    title: "默认宠物形象",
                    subtitle: "設定展示模式示意圖，以及沒有活躍或待處理工作階段時瀏海/懸浮寵物使用的預設造型。"
                ) {
                    DisplayPreviewMascotPicker(kind: $settings.previewMascotKind)
                }

                if settings.surfaceMode == .notch {
                    SettingsLineDivider()
                    SettingsInfoLine(
                        title: "刘海拖拽引导",
                        subtitle: "重新演示老用户首次打开新版本时看到的刘海拖拽提示。"
                    ) {
                        HookManagementButton(
                            title: "重新演示",
                            tint: SettingsCategory.display.tint,
                            action: replayNotchDetachmentHint
                        )
                    }
                    SettingsLineDivider()
                    NotchDisplayModeSelector(mode: $settings.notchDisplayMode)
                    SettingsLineDivider()
                    SettingsSliderLine(
                        title: "静默状态宽度",
                        subtitle: "调整无展开面板时的刘海宽度；较窄时会降级为单图标显示，不影响点击或 hover 后的展开面板宽度。",
                        value: $settings.notchModuleWidth,
                        range: AppSettings.notchModuleWidthRange,
                        step: 4,
                        format: { "\($0.formatted(.number.precision(.fractionLength(0)))) pt" }
                    )
                    SettingsLineDivider()
                    SettingsSliderLine(
                        title: "悬停展开延迟",
                        subtitle: "鼠标悬停到岛展开的等待时间（秒）。默认 0.24。",
                        value: $settings.notchHoverActivationDelay,
                        range: 0.0...1.0,
                        step: 0.02,
                        format: { "\($0.formatted(.number.precision(.fractionLength(2)))) s" }
                    )
                    SettingsLineDivider()
                    SettingsSliderLine(
                        title: "展开动画时长",
                        subtitle: "岛展开动画的速度（秒，越小越快）。默认 0.42。",
                        value: $settings.notchOpenAnimationDuration,
                        range: 0.15...0.8,
                        step: 0.01,
                        format: { "\($0.formatted(.number.precision(.fractionLength(2)))) s" }
                    )
                    SettingsLineDivider()
                    SettingsInfoLine(
                        title: "右侧展示内容",
                        subtitle: "默认显示会话数量；检测到 Claude Code 或 Codex 的 7d 用量后，可改为展示其中一个客户端的 Token 剩余额度。"
                    ) {
                        ClosedNotchTrailingContentPicker(
                            mode: Binding(
                                get: { settings.closedNotchTrailingContentMode },
                                set: { settings.closedNotchTrailingContentMode = $0 }
                            ),
                            availability: viewModel.closedNotchUsageAvailability
                        )
                    }
                } else {
                    SettingsLineDivider()
                    FloatingPetPlacementInfoCard()
                    SettingsLineDivider()
                    SettingsInfoLine(
                        title: "寵物大小",
                        subtitle: "自動模式會根據目前顯示器解析度調整；也可以固定為標準尺寸或始終放大。"
                    ) {
                        FloatingPetSizeModePicker(mode: $settings.floatingPetSizeMode)
                    }
                }
                SettingsLineDivider()

                SettingsToggleLine(
                    title: "显示代理活动详情",
                    subtitle: "在会话列表和 hover 预览里展示工具调用、思考与更细的状态描述",
                    isOn: $settings.showAgentDetail
                )
                SettingsLineDivider()

                SettingsToggleLine(
                    title: "显示用量",
                    subtitle: "在展开面板顶部显示 Claude 与 Codex 的限额占用率和重置时间",
                    isOn: $settings.showUsage
                )
                SettingsLineDivider()

                SettingsInfoLine(
                    title: "用量显示方式",
                    subtitle: "切换显示已用量或剩余量；Claude 与 Codex 共用这组设置"
                ) {
                    UsageValueModePicker(
                        mode: Binding(
                            get: { settings.usageValueMode },
                            set: { settings.usageValueMode = $0 }
                        )
                    )
                    .disabled(!settings.showUsage)
                }
                SettingsLineDivider()

                SettingsInfoLine(
                    title: "子 Agent 显示",
                    subtitle: "控制主列表里是否在主 Agent 下展示明确的子 Agent；当前会影响 Codex、Qoder 等带子会话的客户端"
                ) {
                    SubagentVisibilityPicker(
                        mode: Binding(
                            get: { settings.subagentVisibilityMode },
                            set: { settings.subagentVisibilityMode = $0 }
                        )
                    )
                }
                SettingsLineDivider()

                SettingsSliderLine(
                    title: "内容字号",
                    subtitle: "调整会话列表、hover 预览和结果视图的文字大小",
                    value: $settings.contentFontSize,
                    range: 11...17,
                    step: 1,
                    format: { "\($0.formatted(.number.precision(.fractionLength(0)))) pt" }
                )
                SettingsLineDivider()

                SettingsSliderLine(
                    title: "最大面板高度",
                    subtitle: "控制聊天面板和 hover 预览的最大展开高度",
                    value: $settings.maxPanelHeight,
                    range: 480...700,
                    step: 10,
                    format: { "\($0.formatted(.number.precision(.fractionLength(0)))) pt" }
                )
                SettingsLineDivider()

                SettingsInfoLine(
                    title: "设置面板大小",
                    subtitle: "将设置面板恢复到默认宽高，适合窗口被拉大或缩小时快速回到推荐布局。"
                ) {
                    HookManagementButton(
                        title: "重設",
                        tint: SettingsCategory.display.tint,
                        action: resetSettingsPanelSize
                    )
                }
            }
        }
    }

    private var currentWindow: NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow
    }

    private func resetSettingsPanelSize() {
        SettingsWindowLayout.resetContentSize(of: currentWindow)
    }

    private func replayNotchDetachmentHint() {
        AppSettings.notchDetachmentHintPending = true
        AppSettings.floatingPetSettingsHintPending = true
        onClose?()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NotificationCenter.default.post(name: .pingIslandPresentNotchDetachmentHint, object: nil)
        }
    }
}

struct ClosedNotchTrailingContentPicker: View {
    @Binding var mode: ClosedNotchTrailingContentMode
    let availability: ClosedNotchUsageAvailability

    var body: some View {
        Picker("", selection: $mode) {
            ForEach(ClosedNotchTrailingContentMode.allCases) { candidate in
                Text(appLocalized: candidate.title)
                    .tag(candidate)
                    .disabled(!availability.supports(candidate))
            }
        }
        .labelsHidden()
        .accessibilityLabel(Text(appLocalized: "右侧展示内容"))
        .settingsMenuPicker(width: 190)
    }
}

struct FloatingPetSizeModePicker: View {
    @Binding var mode: FloatingPetSizeMode

    var body: some View {
        Picker("", selection: $mode) {
            ForEach(FloatingPetSizeMode.allCases) { candidate in
                Text(appLocalized: candidate.title).tag(candidate)
            }
        }
        .labelsHidden()
        .accessibilityLabel(Text(appLocalized: "寵物大小"))
        .settingsMenuPicker(width: 132)
        .help(AppLocalization.string(mode.subtitle))
    }
}

struct MenuBarIconStylePicker: View {
    @Binding var style: MenuBarIconStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(appLocalized: "常驻在选单栏，点一下就能打开设置")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                ForEach(MenuBarIconStyle.allCases) { candidate in
                    Button {
                        style = candidate
                    } label: {
                        Image(nsImage: candidate.templateImage(pointSize: 22))
                            .renderingMode(.template)
                            .resizable()
                            .frame(width: 20, height: 20)
                            .foregroundColor(.white)
                            .frame(width: 46, height: 46)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.white.opacity(style == candidate ? 0.14 : 0.05))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(
                                        style == candidate ? SettingsCategory.display.tint : Color.white.opacity(0.12),
                                        lineWidth: style == candidate ? 2 : 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .help(AppLocalization.string(candidate.titleKey))
                }
            }

            Text(appLocalized: style.titleKey)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

struct IslandSurfaceModeSelector: View {
    @Binding var mode: IslandSurfaceMode
    var title: String? = "展示模式"
    var subtitle: String? = "选择 Ping Island 的主显示方式。你随时可以在设置里切换，并立即看到新的渲染效果。"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(appLocalized: title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }

            if let subtitle {
                Text(appLocalized: subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.58))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                ForEach(IslandSurfaceMode.allCases) { candidate in
                    IslandSurfaceModeCard(
                        mode: candidate,
                        isSelected: mode == candidate
                    ) {
                        mode = candidate
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

struct IslandSurfaceModeCard: View {
    let mode: IslandSurfaceMode
    let isSelected: Bool
    let action: () -> Void
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(previewBackground)
                        .aspectRatio(7.0 / 3.0, contentMode: .fit)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(previewBorder, lineWidth: 1)
                        )
                        .overlay {
                            IslandSurfaceModePreviewScene(
                                surfaceMode: mode,
                                notchDisplayMode: settings.notchDisplayMode,
                                floatingPetSizeMode: settings.floatingPetSizeMode
                            )
                            .padding(12)
                        }
                }

                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appLocalized: mode.title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)

                        Text(appLocalized: mode.subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.62))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isSelected ? accentColor : .white.opacity(0.26))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.09 : 0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? accentColor.opacity(0.56) : Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: isSelected ? accentColor.opacity(0.18) : .clear, radius: 16, y: 8)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var accentColor: Color {
        switch mode {
        case .notch:
            return Color(red: 0.24, green: 0.72, blue: 0.98)
        case .floatingPet:
            return Color(red: 0.98, green: 0.64, blue: 0.26)
        }
    }

    private var previewBackground: LinearGradient {
        switch mode {
        case .notch:
            return LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.18, blue: 0.30),
                    Color(red: 0.05, green: 0.09, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .floatingPet:
            return LinearGradient(
                colors: [
                    Color(red: 0.27, green: 0.17, blue: 0.08),
                    Color(red: 0.10, green: 0.08, blue: 0.06)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var previewBorder: Color {
        isSelected ? accentColor.opacity(0.42) : Color.white.opacity(0.10)
    }
}

struct IslandSurfaceModePreviewScene: View {
    let surfaceMode: IslandSurfaceMode
    let notchDisplayMode: NotchDisplayMode
    let floatingPetSizeMode: FloatingPetSizeMode
    @ObservedObject private var settings = AppSettings.shared
    @State private var isHovered = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.035))

                switch surfaceMode {
                case .notch:
                    notchPreview(in: proxy.size)
                case .floatingPet:
                    floatingPreview(in: proxy.size)
                }
            }
        }
        .environment(\.mascotAnimationsEnabled, isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private func notchPreview(in size: CGSize) -> some View {
        let notchWidth = min(max(size.width * 0.9, 112), 168)
        let notchHeight = min(max(size.height * 0.28, 22), 28)

        return VStack(spacing: 0) {
            NotchDisplayPreviewMock(
                mode: notchDisplayMode,
                mascotKind: settings.previewMascotKind,
                width: notchWidth,
                height: notchHeight
            )
            .padding(.top, 10)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Text(appLocalized: "顶部 Island")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.42))
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
    }

    private func floatingPreview(in size: CGSize) -> some View {
        let mascotSize = 34 * previewScale
        let numberSize = 12 * min(previewScale, 1.14)

        return ZStack(alignment: .bottomTrailing) {
            VStack {
                HStack {
                    Text(appLocalized: "右下角悬浮")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white.opacity(0.46))
                    Spacer()
                }
                Spacer()
            }
            .padding(10)

            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color.white.opacity(0.16))
                        .frame(width: min(24, size.width * 0.10), height: 2)

                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(Color.white.opacity(0.10))
                        .frame(width: min(12, size.width * 0.05), height: 2)
                }

                HStack(alignment: .bottom, spacing: 3) {
                    MascotView(
                        kind: settings.previewMascotKind,
                        status: .idle,
                        size: mascotSize
                    )

                    Text("2")
                        .font(.system(size: numberSize, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 1.0, green: 0.55, blue: 0.26))
                        .offset(y: -1)
                }
            }
            .padding(.trailing, 16)
            .padding(.bottom, 12)
        }
    }

    private var previewScale: CGFloat {
        switch floatingPetSizeMode {
        case .automatic:
            return 1.08
        case .standard:
            return 1
        case .large:
            return 1.16
        }
    }
}

struct DisplayPreviewMascotPicker: View {
    private let accessibilityTitleKey = "默认宠物形象"
    @Binding var kind: MascotKind

    var body: some View {
        Picker(selection: $kind) {
            ForEach(MascotKind.allCases) { candidate in
                Text(
                    verbatim: AppLocalization.format(
                        "%@ · %@",
                        AppLocalization.string(candidate.subtitle),
                        AppLocalization.string(candidate.title)
                    )
                )
                .tag(candidate)
            }
        } label: {
            EmptyView()
        }
        .labelsHidden()
        .accessibilityLabel(Text(verbatim: AppLocalization.string(accessibilityTitleKey)))
        .pickerStyle(.menu)
        .frame(minWidth: 180, alignment: .trailing)
    }
}

struct FloatingPetPlacementInfoCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(appLocalized: "独立悬浮宠物")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            Text(appLocalized: "独立悬浮宠物默认贴近当前激活窗口右下角显示。拖动后会记住新位置，右键宠物造型可重新打开设置面板。")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

struct NotchDisplayPreviewMock: View {
    let mode: NotchDisplayMode
    let mascotKind: MascotKind
    let width: CGFloat
    let height: CGFloat

    private let actualClosedWidth: CGFloat = 274
    private let actualSideWidth: CGFloat = 30
    private let actualCenterWidth: CGFloat = 186

    var body: some View {
        let sideSlotWidth = width * (actualSideWidth / actualClosedWidth)
        let centerSlotWidth = width * (actualCenterWidth / actualClosedWidth)

        return HStack(spacing: 0) {
            HStack {
                MascotView(kind: mascotKind, status: .idle, size: 14)
            }
            .frame(width: sideSlotWidth, alignment: .center)

            HStack {
                if mode == .detailed {
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 14)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.white.opacity(0.76))
                                .frame(width: 42, height: 3)
                                .padding(.leading, 8)
                        }
                        .frame(width: centerSlotWidth * 0.92, alignment: .center)
                } else {
                    Color.clear
                        .frame(width: centerSlotWidth * 0.92)
                }
            }
            .frame(width: centerSlotWidth, alignment: .center)

            HStack {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 18, height: 14)
                    .overlay(
                        Text("3")
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white.opacity(0.9))
                    )
            }
            .frame(width: sideSlotWidth, alignment: .center)
        }
        .frame(width: width, height: height)
        .background(
            RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                .fill(Color.black.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 10, y: 5)
    }
}

struct NotchDisplayModeSelector: View {
    @Binding var mode: NotchDisplayMode

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(appLocalized: "刘海显示模式")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            Text(appLocalized: "直接预览刘海闭合态效果。简约模式只显示宠物和数量，详细模式会额外显示中间过程信息。")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                ForEach(NotchDisplayMode.allCases) { candidate in
                    NotchDisplayModeCard(
                        mode: candidate,
                        isSelected: mode == candidate
                    ) {
                        mode = candidate
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

struct NotchDisplayModeCard: View {
    let mode: NotchDisplayMode
    let isSelected: Bool
    let action: () -> Void
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(previewBackground)
                        .aspectRatio(7.0 / 3.0, contentMode: .fit)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(previewBorder, lineWidth: 1)
                        )
                        .overlay {
                            previewScene
                                .padding(12)
                        }
                }

                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appLocalized: mode.title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)

                        Text(appLocalized: mode.subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.62))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isSelected ? accentColor : .white.opacity(0.26))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 0.09 : 0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isSelected ? accentColor.opacity(0.56) : Color.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: isSelected ? accentColor.opacity(0.18) : .clear, radius: 16, y: 8)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var accentColor: Color {
        switch mode {
        case .compact:
            return Color(red: 0.24, green: 0.72, blue: 0.98)
        case .detailed:
            return Color(red: 0.98, green: 0.68, blue: 0.25)
        }
    }

    private var previewBackground: LinearGradient {
        switch mode {
        case .compact:
            return LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.18, blue: 0.30),
                    Color(red: 0.05, green: 0.09, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .detailed:
            return LinearGradient(
                colors: [
                    Color(red: 0.28, green: 0.17, blue: 0.09),
                    Color(red: 0.11, green: 0.07, blue: 0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var previewBorder: Color {
        isSelected ? accentColor.opacity(0.42) : Color.white.opacity(0.10)
    }

    @ViewBuilder
    private var previewScene: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.02)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                VStack(spacing: 0) {
                    NotchDisplayPreviewMock(
                        mode: mode,
                        mascotKind: settings.previewMascotKind,
                        width: min(max(proxy.size.width * 0.9, 112), 168),
                        height: min(max(proxy.size.height * 0.28, 22), 28)
                    )
                        // Keep this mode-card preview static. The other previews
                        // hover-gate their mascot; this one was missing the gate, so its
                        // idle Canvas + FloatingZOverlay TimelineViews ran at ~12 fps the
                        // whole time the settings window was open, continuously
                        // re-compositing the vibrancy-heavy window.
                        .environment(\.mascotAnimationsEnabled, false)
                        .padding(.top, 10)

                    Spacer(minLength: 0)

                    HStack {
                        Spacer()
                        Text(appLocalized: mode == .compact ? "简约示意" : "详细示意")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white.opacity(0.42))
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
            }
        }
    }
}

struct SubagentVisibilityPicker: View {
    @Binding var mode: SubagentVisibilityMode

    var body: some View {
        Picker("", selection: $mode) {
            ForEach(SubagentVisibilityMode.allCases) { candidate in
                Text(appLocalized: candidate.title).tag(candidate)
            }
        }
        .labelsHidden()
        .accessibilityLabel(Text(appLocalized: "子 Agent 显示"))
        .settingsMenuPicker(width: 168)
    }
}

struct UsageValueModePicker: View {
    @Binding var mode: UsageValueMode

    var body: some View {
        Picker("", selection: $mode) {
            ForEach(UsageValueMode.allCases) { candidate in
                Text(appLocalized: candidate.title).tag(candidate)
            }
        }
        .labelsHidden()
        .accessibilityLabel(Text(appLocalized: "用量显示方式"))
        .settingsMenuPicker(width: 168)
    }
}
