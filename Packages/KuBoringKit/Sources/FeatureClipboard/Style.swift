import SwiftUI

// Мелкие общие вьюхи (дублируются в каждом модуле, модули независимы).
enum Palette {
    static let surface = Color.white.opacity(0.08)
    static let surfaceHover = Color.white.opacity(0.14)
    static let secondary = Color.gray
    static let tertiary = Color.white.opacity(0.35)
}

struct PillButton: View {
    let title: String
    var selected = false
    var scale: CGFloat = 1
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12 * scale, weight: .semibold, design: .rounded))
                .foregroundStyle(selected ? Color.black : (hover ? Color.white : Palette.secondary))
                .padding(.horizontal, 12 * scale)
                .frame(height: 26 * scale)
                .background(Capsule().fill(selected ? Color.white : (hover ? Palette.surfaceHover : Palette.surface)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct EmptyHint: View {
    let symbol: String
    let title: String
    var subtitle: String = ""

    var body: some View {
        // Если по высоте не влезает с подзаголовком — показываем только заголовок.
        ViewThatFits(in: .vertical) {
            hint(withSubtitle: true)
            hint(withSubtitle: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func hint(withSubtitle: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .foregroundStyle(Palette.tertiary)
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Palette.secondary)
            if withSubtitle && !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
