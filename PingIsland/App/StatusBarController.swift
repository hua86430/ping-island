import AppKit
import Combine

// Always-on menu bar status item. PingIsland runs as an accessory app, so when the
// floating pet is hard to click (or a user does not know right-click opens Settings),
// this is the only reliable way back into Settings. It must never be hideable.

/// What a menu item does when chosen. Pure value type so the menu layout is testable
/// without building any AppKit objects.
enum StatusMenuAction: Equatable {
    case openSettings
    case setSurfaceMode(IslandSurfaceMode)
    case checkForUpdates
    case quit
}

/// One entry in the status menu, resolved from localization keys at render time.
struct StatusMenuItem: Equatable {
    enum Kind: Equatable {
        case action(StatusMenuAction)
        case submenu([StatusMenuItem])
        case separator
        case info // disabled display-only line
    }

    var kind: Kind
    /// Localization key (Simplified identifier); nil for separators and the literal version line.
    var titleKey: String?
    /// Literal title used verbatim (the version line); nil when the title comes from `titleKey`.
    var literalTitle: String?
    var isChecked: Bool

    static func action(_ action: StatusMenuAction, key: String, checked: Bool = false) -> StatusMenuItem {
        StatusMenuItem(kind: .action(action), titleKey: key, literalTitle: nil, isChecked: checked)
    }

    static func submenu(key: String, _ children: [StatusMenuItem]) -> StatusMenuItem {
        StatusMenuItem(kind: .submenu(children), titleKey: key, literalTitle: nil, isChecked: false)
    }

    static let separator = StatusMenuItem(kind: .separator, titleKey: nil, literalTitle: nil, isChecked: false)

    static func info(_ title: String) -> StatusMenuItem {
        StatusMenuItem(kind: .info, titleKey: nil, literalTitle: title, isChecked: false)
    }
}

/// Pure menu-layout builder. No AppKit menu objects, no side effects — unit tested directly.
enum StatusBarMenuBuilder {
    static func versionDisplayString(shortVersion: String, buildNumber: String) -> String {
        "Ping Island v\(shortVersion) (build \(buildNumber))"
    }

    static func menu(
        surfaceMode: IslandSurfaceMode,
        shortVersion: String,
        buildNumber: String,
        includeCheckForUpdates: Bool
    ) -> [StatusMenuItem] {
        var items: [StatusMenuItem] = [
            .action(.openSettings, key: "打开设置"),
            .submenu(key: "展示模式", [
                .action(.setSurfaceMode(.notch), key: "刘海屏方式", checked: surfaceMode == .notch),
                .action(.setSurfaceMode(.floatingPet), key: "独立悬浮宠物", checked: surfaceMode == .floatingPet),
            ]),
            .separator,
            .info(versionDisplayString(shortVersion: shortVersion, buildNumber: buildNumber)),
        ]
        if includeCheckForUpdates {
            items.append(.action(.checkForUpdates, key: "检查更新"))
        }
        items.append(.separator)
        items.append(.action(.quit, key: "退出 Ping Island"))
        return items
    }
}

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var updateCheckObserver: AnyCancellable?
    private var iconObserver: AnyCancellable?
    private enum ManualUpdateStage {
        case idle
        case awaitingResult // waiting for the check to say up-to-date / found / error
        case awaitingDownload // user agreed to update; waiting for the auto-download to finish
    }
    private var manualUpdateStage: ManualUpdateStage = .idle

    override init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.button?.toolTip = "Ping Island"
        applyIcon()

        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()

        // Live-update the menu bar icon when the user switches style in Settings.
        iconObserver = AppSettings.shared.$menuBarIconStyle
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyIcon() }
    }

    private func applyIcon() {
        statusItem.button?.image = AppSettings.menuBarIconStyle.templateImage()
    }

    private var includeCheckForUpdates: Bool {
#if APP_STORE
        false
#else
        true
#endif
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let model = StatusBarMenuBuilder.menu(
            surfaceMode: AppSettings.surfaceMode,
            shortVersion: Self.bundleShortVersion,
            buildNumber: Self.bundleBuildNumber,
            includeCheckForUpdates: includeCheckForUpdates
        )
        for item in model {
            menu.addItem(makeMenuItem(item))
        }
    }

    private func makeMenuItem(_ model: StatusMenuItem) -> NSMenuItem {
        switch model.kind {
        case .separator:
            return .separator()
        case .info:
            let item = NSMenuItem(title: model.literalTitle ?? "", action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        case .submenu(let children):
            let item = NSMenuItem(title: title(for: model), action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for child in children {
                submenu.addItem(makeMenuItem(child))
            }
            item.submenu = submenu
            return item
        case .action(let action):
            let item = NSMenuItem(title: title(for: model), action: selector(for: action), keyEquivalent: "")
            item.target = self
            item.state = model.isChecked ? .on : .off
            return item
        }
    }

    private func title(for model: StatusMenuItem) -> String {
        if let literal = model.literalTitle { return literal }
        if let key = model.titleKey { return AppLocalization.string(key) }
        return ""
    }

    private func selector(for action: StatusMenuAction) -> Selector {
        switch action {
        case .openSettings:
            return #selector(handleOpenSettings)
        case .setSurfaceMode(.notch):
            return #selector(handleSelectNotchMode)
        case .setSurfaceMode(.floatingPet):
            return #selector(handleSelectFloatingPetMode)
        case .checkForUpdates:
            return #selector(handleCheckForUpdates)
        case .quit:
            return #selector(handleQuit)
        }
    }

    // Menu writes only AppSettings.surfaceMode; IslandPresentationCoordinator's $surfaceMode
    // sink applies the change (and re-docks a detached pet when switching to notch), so there
    // is a single mutation path.
    @objc private func handleOpenSettings() {
        SettingsWindowController.shared.present()
    }

    @objc private func handleSelectNotchMode() {
        AppSettings.surfaceMode = .notch
    }

    @objc private func handleSelectFloatingPetMode() {
        AppSettings.surfaceMode = .floatingPet
    }

    // Report the check result in a small alert instead of opening Settings: from the menu
    // bar there is no other visible surface (the Island may be detached or closed). Observe
    // the update state, kick a manual check, and show an alert when it settles.
    @objc private func handleCheckForUpdates() {
        guard manualUpdateStage == .idle else { return }
        manualUpdateStage = .awaitingResult
        updateCheckObserver = UpdateManager.shared.$state
            .dropFirst() // skip the replayed current value; only react to the check we start below
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handleManualUpdateState(state)
            }
        UpdateManager.shared.checkForUpdates()
    }

    private func handleManualUpdateState(_ state: UpdateState) {
        switch manualUpdateStage {
        case .idle:
            return
        case .awaitingResult:
            handleAwaitingResult(state)
        case .awaitingDownload:
            handleAwaitingDownload(state)
        }
    }

    private func handleAwaitingResult(_ state: UpdateState) {
        switch state {
        case .idle, .checking, .downloading, .extracting, .installing:
            return // still working; wait for the outcome
        case .upToDate:
            endManualCheck()
            presentUpdateAlert(message: AppLocalization.string("当前已经是最新版本"), confirmKey: "好")
        case .found(let version, _), .readyToInstall(let version):
            let confirmed = presentUpdateAlert(
                message: AppLocalization.format("发现新版本 v%@", version),
                informative: AppLocalization.string("是否立即重启并安装？"),
                confirmKey: "安装",
                cancelKey: "取消"
            )
            guard confirmed else { return endManualCheck() }
            // Sparkle auto-downloads; install immediately if already downloaded, else wait.
            if case .readyToInstall = UpdateManager.shared.state {
                endManualCheck()
                UpdateManager.shared.installAndRelaunch()
            } else {
                manualUpdateStage = .awaitingDownload
            }
        case .error(let message):
            endManualCheck()
            presentUpdateAlert(message: AppLocalization.string("检查更新"), informative: message, confirmKey: "好")
        }
    }

    private func handleAwaitingDownload(_ state: UpdateState) {
        switch state {
        case .readyToInstall:
            endManualCheck()
            UpdateManager.shared.installAndRelaunch()
        case .error(let message):
            endManualCheck()
            presentUpdateAlert(message: AppLocalization.string("检查更新"), informative: message, confirmKey: "好")
        default:
            return // downloading / extracting — keep waiting silently
        }
    }

    private func endManualCheck() {
        updateCheckObserver = nil
        manualUpdateStage = .idle
    }

    /// Shows a modal alert and returns true when the confirm button was chosen.
    @discardableResult
    private func presentUpdateAlert(
        message: String,
        informative: String? = nil,
        confirmKey: String,
        cancelKey: String? = nil
    ) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = message
        if let informative, !informative.isEmpty {
            alert.informativeText = informative
        }
        alert.addButton(withTitle: AppLocalization.string(confirmKey))
        if let cancelKey {
            alert.addButton(withTitle: AppLocalization.string(cancelKey))
        }
        return alert.runModal() == .alertFirstButtonReturn
    }

    @objc private func handleQuit() {
        NSApp.terminate(nil)
    }

    private static var bundleShortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private static var bundleBuildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}

extension StatusBarController: NSMenuDelegate {
    // Refresh checkmarks and the version line each time the menu opens.
    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }
}
