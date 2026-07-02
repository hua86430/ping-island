import CoreGraphics

/// Pure selection of the docked notch's hover-sensor frame.
enum NotchHoverSensorFrame {
    static func rect(
        isDetached: Bool,
        isSuppressedHidden: Bool,
        isFullscreenReveal: Bool,
        closedTriggerRect: CGRect,
        fullscreenRevealRect: CGRect
    ) -> CGRect? {
        if isDetached || isSuppressedHidden { return nil }
        return isFullscreenReveal ? fullscreenRevealRect : closedTriggerRect
    }
}
