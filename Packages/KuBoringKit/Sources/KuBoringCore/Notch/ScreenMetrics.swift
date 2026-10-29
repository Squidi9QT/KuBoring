import AppKit

/// Реальные размеры выреза / меню-бара для экрана.
public enum ScreenMetrics {
    /// Есть ли у экрана физический вырез.
    @MainActor
    public static func hasNotch(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0
    }

    /// Размер выреза. Для экранов без выреза — ширина по умолчанию и высота меню-бара.
    @MainActor
    public static func notchSize(for screen: NSScreen) -> CGSize {
        var width: CGFloat = 185
        var height: CGFloat

        if screen.safeAreaInsets.top > 0 {
            height = screen.safeAreaInsets.top
            // Вырез = полная ширина минус свободные области слева и справа от него.
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
