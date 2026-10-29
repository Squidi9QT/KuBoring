import SwiftUI

/// Форма шторки: сверху «ушки» (вогнутые плавные заходы к краю экрана), снизу скруглённые углы.
/// Ширина фрейма включает ушки по бокам; тело шторки — между ними.
public struct NotchShape: Shape {
    public var topRadius: Double
    public var bottomRadius: Double

    public init(topRadius: Double, bottomRadius: Double) {
        self.topRadius = topRadius
        self.bottomRadius = bottomRadius
    }

    public var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        let w = Double(rect.width)
        let h = Double(rect.height)
        // Ограничиваем радиусы, чтобы форма не выворачивалась.
        let t = max(0, min(topRadius, h / 2, w / 4))
        let b = max(0, min(bottomRadius, h - t, (w - 2 * t) / 2))
        let o = rect.origin
        func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: Double(o.x) + x, y: Double(o.y) + y) }

        // Обход по часовой стрелке; повороты строятся дугами окружности.
        var p = Path()
        p.move(to: pt(0, 0))
        p.addLine(to: pt(w, 0))
        // правое ушко
        p.addArc(tangent1End: pt(w - t, 0), tangent2End: pt(w - t, t), radius: CGFloat(t))
        // правый нижний угол
        p.addArc(tangent1End: pt(w - t, h), tangent2End: pt(w - t - b, h), radius: CGFloat(b))
        // левый нижний угол
        p.addArc(tangent1End: pt(t, h), tangent2End: pt(t, h - b), radius: CGFloat(b))
        // левое ушко
        p.addArc(tangent1End: pt(t, 0), tangent2End: pt(0, 0), radius: CGFloat(t))
        p.closeSubpath()
        return p
    }
}
