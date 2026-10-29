import SwiftUI

// Мелкие общие вьюхи (дублируются в каждом модуле, модули независимы).
enum Palette {
    static let surface = Color.white.opacity(0.08)
    static let surfaceHover = Color.white.opacity(0.14)
    static let secondary = Color.gray
    static let timer = Color.orange
    /// Перерыв в «помидоре».
    static let pause = Color.teal
}

struct IconButton: View {
    let symbol: String
    var size: CGFloat = 28
    var help: String = ""
    var iconSize: CGFloat = 12
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(hover ? Color.white : Palette.secondary)
                .frame(width: size, height: size)
                .background(Circle().fill(hover ? Palette.surfaceHover : Palette.surface))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
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
