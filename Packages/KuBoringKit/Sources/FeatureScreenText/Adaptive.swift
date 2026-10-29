import SwiftUI

/// Масштаб содержимого вкладки от доступной области (дублируется в каждом модуле, модули независимы).
/// Базовая область контента при размере шторки по умолчанию (640×190) — примерно 600×150.
struct AdaptiveMetrics {
    let size: CGSize

    init(size: CGSize) { self.size = size }

    /// 1.0 на базовой области, 0.7...1.8 при изменении размера шторки.
    var scale: CGFloat {
        let w = max(1, size.width), h = max(1, size.height)
        return min(max(min(w / 600, h / 150), 0.7), 1.8)
    }

    /// Масштабирует базовое значение.
    func s(_ value: CGFloat) -> CGFloat { value * scale }
}

/// Ограничивает значение диапазоном.
func adaptiveClamp(_ value: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat {
    min(max(value, lo), hi)
}
