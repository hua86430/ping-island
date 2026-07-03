import AppKit
import SwiftUI

/// Frosted vibrancy surface that honors the system "Reduce transparency" setting.
///
/// macOS 26 (Tahoe) has a system-wide window-rendering regression where live
/// vibrancy re-composites on every frame while any window is dragged, dropping
/// FPS across the whole machine. When the user turns on Reduce transparency
/// (System Settings > Accessibility > Display), we drop the NSVisualEffectView
/// entirely and paint an opaque dark fill, so the settings window costs the
/// compositor nothing per frame. With the setting off, the glass look is kept.
struct SettingsGlassSurface: View {
    let material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    var state: NSVisualEffectView.State = .followsWindowActiveState

    @State private var reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency

    var body: some View {
        Group {
            if reduceTransparency {
                // Opaque, no vibrancy layer at all.
                Color(white: 0.12)
            } else {
                VibrancyView(material: material, blendingMode: blendingMode, state: state)
            }
        }
        .onReceive(
            NSWorkspace.shared.notificationCenter.publisher(
                for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
            )
        ) { _ in
            reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        }
    }
}

private struct VibrancyView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let state: NSVisualEffectView.State

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}
