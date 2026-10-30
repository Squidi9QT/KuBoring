import SwiftUI

public enum NotchLayout {
    public static func closedBase(_ g: NotchGeometry, physical: CGSize) -> CGSize {
        CGSize(
            width: g.closedWidthAuto ? physical.width : g.closedWidth,
            height: g.closedHeightAuto ? physical.height : g.closedHeight)
    }

    public static func closedSize(_ g: NotchGeometry, physical: CGSize, extraWidth: Double) -> CGSize {
        let base = closedBase(g, physical: physical)
        return CGSize(width: base.width + 2 * extraWidth, height: base.height)
    }

    public static func openSize(_ g: NotchGeometry, preferred: CGSize?) -> CGSize {
        preferred ?? CGSize(width: g.openWidth, height: g.openHeight)
    }

    public static func ear(open: Bool, cornerRadius: Double) -> Double {
        open ? max(6, cornerRadius * 0.45) : 6
    }

    public static func bottomRadius(open: Bool, cornerRadius: Double, height: Double) -> Double {
        open ? cornerRadius : min(10, height / 2)
    }

    public static func maxEar(_ g: NotchGeometry) -> Double {
        max(6, g.cornerRadius * 0.45)
    }
}

public extension NotchGeometry {
    func clamped() -> NotchGeometry {
        var g = self
        g.openWidth = min(max(g.openWidth, 400), 900)
        g.openHeight = min(max(g.openHeight, 120), 600)
        g.animationSpeed = min(max(g.animationSpeed, 0.5), 2.0)
        return g
    }
}
