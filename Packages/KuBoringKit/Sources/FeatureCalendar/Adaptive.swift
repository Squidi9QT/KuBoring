import SwiftUI

struct AdaptiveMetrics {
    let size: CGSize

    init(size: CGSize) { self.size = size }

    var scale: CGFloat {
        let w = max(1, size.width), h = max(1, size.height)
        return min(max(min(w / 600, h / 150), 0.7), 1.8)
    }

    func s(_ value: CGFloat) -> CGFloat { value * scale }
}

func adaptiveClamp(_ value: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
    min(max(value, lo), hi)
}
