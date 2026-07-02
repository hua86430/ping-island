import AppKit

/// Near-transparent, nonactivating panel over the closed-notch trigger rect.
/// Its .activeAlways tracking area fires enter/exit even when the app is a
/// background accessory (verified by spike), so hover works at all energy levels.
/// Hover-only: click-open and drag-detach ride the existing local NSEvent monitor.
final class NotchHoverSensorWindow: NSPanel {
    private let sensorView: SensorView

    init(onEnter: @escaping () -> Void, onExit: @escaping () -> Void) {
        sensorView = SensorView()
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        level = .mainMenu + 3
        sensorView.onEnter = onEnter
        sensorView.onExit = onExit
        contentView = sensorView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Show + frame for `rect`, or order out when nil. Fires onEnter if the
    /// cursor is already inside (AppKit emits no mouseEntered for a cursor
    /// already within a freshly installed/moved tracking area). onEnter is
    /// itself idempotent (guarded by !isHovering in the view model), so a
    /// re-show under a stationary cursor after a close does not reopen.
    func update(rect: CGRect?) {
        guard let rect else {
            if isVisible { orderOut(nil) }
            return
        }
        setFrame(rect, display: false)
        if !isVisible { orderFrontRegardless() }
        if rect.contains(NSEvent.mouseLocation) {
            sensorView.onEnter()
        }
    }

    private final class SensorView: NSView {
        var onEnter: () -> Void = {}
        var onExit: () -> Void = {}

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            // Near-zero alpha keeps the window in hit-testing (spike finding).
            layer?.backgroundColor = NSColor.black.withAlphaComponent(0.01).cgColor
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: nil
            ))
        }

        override func mouseEntered(with event: NSEvent) { onEnter() }
        override func mouseExited(with event: NSEvent) { onExit() }
    }
}
