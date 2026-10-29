import SwiftUI

/// Вычисление итоговых размеров шторки из NotchGeometry. Общее для вьюхи, окна и превью в настройках.
public enum NotchLayout {
    /// Базовый размер закрытой шторки (без активности).
    public static func closedBase(_ g: NotchGeometry, physical: CGSize) -> CGSize {
        CGSize(width: g.closedWidthAuto ? physical.width : g.closedWidth,
               height: g.closedHeightAuto ? physical.height : g.closedHeight)
    }

    /// Размер закрытой шторки с учётом живой активности.
    public static func closedSize(_ g: NotchGeometry, physical: CGSize, extraWidth: Double) -> CGSize {
        let base = closedBase(g, physical: physical)
        return CGSize(width: base.width + 2 * extraWidth, height: base.height)
    }

    /// Размер открытой шторки; preferred — размер, который просит активная вкладка.
    public static func openSize(_ g: NotchGeometry, preferred: CGSize?) -> CGSize {
        preferred ?? CGSize(width: g.openWidth, height: g.openHeight)
    }

    /// Радиус «ушка» сверху.
    public static func ear(open: Bool, cornerRadius: Double) -> Double {
        open ? max(6, cornerRadius * 0.45) : 6
    }

    /// Радиус нижних углов.
    public static func bottomRadius(open: Bool, cornerRadius: Double, height: Double) -> Double {
        open ? cornerRadius : min(10, height / 2)
    }

    /// Максимальный вылет ушка по горизонтали (для хит-тестов).
    public static func maxEar(_ g: NotchGeometry) -> Double {
        max(6, g.cornerRadius * 0.45)
    }
}

public extension NotchGeometry {
    /// Ограничивает значения допустимыми диапазонами из контракта.
    func clamped() -> NotchGeometry {
        var g = self
        g.openWidth = min(max(g.openWidth, 400), 900)
        g.openHeight = min(max(g.openHeight, 120), 600)
        g.animationSpeed = min(max(g.animationSpeed, 0.5), 2.0)
        return g
    }
}
