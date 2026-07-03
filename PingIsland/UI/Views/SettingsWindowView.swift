import SwiftUI

struct SettingsWindowView: View {
    var onClose: (() -> Void)? = nil

    var body: some View {
        AppLocalizedRootView {
            SettingsRootView(onClose: onClose)
                .accessibilityIdentifier("settings.root")
        }
    }
}
