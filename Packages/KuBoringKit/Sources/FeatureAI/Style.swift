import SwiftUI

// Мелкие общие вьюхи (дублируются в каждом модуле, модули независимы).
enum Palette {
    static let surface = Color.white.opacity(0.08)
    static let surfaceHover = Color.white.opacity(0.14)
    static let stroke = Color.white.opacity(0.10)
    static let secondary = Color.gray
}

struct IconButton: View {
    let symbol: String
    var size: CGFloat = 28
    var help: String = ""
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
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
