import AppKit
import SwiftUI

struct RemoteSettingsView: View {
    @ObservedObject private var remoteManager = RemoteConnectorManager.shared
    @State private var showingRemoteHostSheet = false
    @State private var remotePasswordPromptRequest: RemotePasswordPromptRequest?

    var body: some View {
        content
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

    private var content: some View {
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

struct RemoteHostManagementLine: View {
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

        let attachDisconnectPrefix = "SSH attach 已斷線: "
        if lastError.hasPrefix(attachDisconnectPrefix) {
            let detail = String(lastError.dropFirst(attachDisconnectPrefix.count))
            return AppLocalization.format("SSH attach 已断开: %@", detail)
        }

        return AppLocalization.string(lastError)
    }
}

struct AddRemoteHostSheet: View {
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

enum RemotePasswordPromptAction: String {
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

struct RemotePasswordPromptRequest: Identifiable {
    let endpoint: RemoteEndpoint
    let action: RemotePasswordPromptAction

    var id: String {
        "\(endpoint.id.uuidString)-\(action.rawValue)"
    }
}

struct RemotePasswordPromptSheet: View {
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
