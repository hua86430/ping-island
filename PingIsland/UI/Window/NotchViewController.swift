//
//  NotchViewController.swift
//  PingIsland
//
//  Hosts the SwiftUI NotchView in AppKit with click-through support
//

import AppKit
import SwiftUI

/// Custom NSHostingView that only accepts mouse events within the panel bounds.
/// Clicks outside the panel pass through to windows behind.
class PassThroughHostingView<Content: View>: NSHostingView<Content> {
    var hitTestRect: () -> CGRect = { .zero }

    override var isOpaque: Bool { false }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        configureTransparency()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Only accept hits within the panel rect
        guard hitTestRect().contains(point) else {
            return nil  // Pass through to windows behind
        }
        return super.hitTest(point)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureTransparency()
    }

    private func configureTransparency() {
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }
}

class NotchViewController: NSViewController {
    private let viewModel: NotchViewModel
    private let sessionMonitor: SessionMonitor
    private var hostingView: PassThroughHostingView<AppLocalizedRootView<NotchView>>!

    init(viewModel: NotchViewModel, sessionMonitor: SessionMonitor) {
        self.viewModel = viewModel
        self.sessionMonitor = sessionMonitor
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        hostingView = PassThroughHostingView(
            rootView: AppLocalizedRootView {
                NotchView(
                    viewModel: viewModel,
                    sessionMonitor: sessionMonitor
                )
            }
        )

        // Calculate the hit-test rect based on panel state. Read the LIVE window
        // height (the window frame now scales with status) instead of the fixed
        // geometry.windowHeight, so hit-testing tracks whatever frame is current.
        hostingView.hitTestRect = { [weak self] in
            guard let self = self else { return .zero }
            let vm = self.viewModel
            let geometry = vm.geometry
            let windowFrame = self.view.window?.frame
            let windowWidth = windowFrame?.width ?? geometry.screenRect.width
            let windowHeight = windowFrame?.height ?? geometry.windowHeight
            return Self.panelHitRect(
                status: vm.status,
                openedSize: vm.openedSize,
                closedSize: vm.closedSize,
                windowWidth: windowWidth,
                windowHeight: windowHeight
            )
        }

        self.view = hostingView
    }

    /// Panel hit rect in window coordinates (origin bottom-left, panel pinned to the
    /// window top). Pure so the height source can be unit-tested. `windowHeight` is
    /// the live window height; `.opened` fills a centered panel, `.closed`/`.popping`
    /// a padded pill.
    static func panelHitRect(
        status: NotchStatus,
        openedSize: CGSize,
        closedSize: CGSize,
        windowWidth: CGFloat,
        windowHeight: CGFloat
    ) -> CGRect {
        // Panels are centered horizontally within the WINDOW (the window is itself
        // centered on screen), so center on windowWidth, not screen width.
        switch status {
        case .opened:
            let panelWidth = openedSize.width + 52  // Account for corner radius padding
            let panelHeight = openedSize.height
            return CGRect(
                x: (windowWidth - panelWidth) / 2,
                y: windowHeight - panelHeight,
                width: panelWidth,
                height: panelHeight
            )
        case .closed, .popping:
            // Add some padding for easier interaction
            return CGRect(
                x: (windowWidth - closedSize.width) / 2 - 10,
                y: windowHeight - closedSize.height - 5,
                width: closedSize.width + 20,
                height: closedSize.height + 10
            )
        }
    }
}
