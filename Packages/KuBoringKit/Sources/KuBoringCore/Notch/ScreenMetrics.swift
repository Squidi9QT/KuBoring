import AppKit

public enum ScreenMetrics {
    @MainActor
    public static func hasNotch(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0
    }

    @MainActor
    public static func notchSize(for screen: NSScreen) -> CGSize {
        var width: CGFloat = 185
        var height: CGFloat

        if screen.safeAreaInsets.top > 0 {
            height = screen.safeAreaInsets.top
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                let w = screen.frame.width - left.width - right.width
                if w > 40 { width = w }
            }
        } else {
            let bar = screen.frame.maxY - screen.visibleFrame.maxY
            height = bar > 0 ? bar : NSStatusBar.system.thickness
        }
        return CGSize(width: width.rounded(), height: max(height.rounded(), 22))
    }
}
