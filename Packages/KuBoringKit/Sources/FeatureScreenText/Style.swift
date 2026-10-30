import SwiftUI

enum Palette {
    static let surface = Color.white.opacity(0.08)
    static let surfaceHover = Color.white.opacity(0.14)
    static let secondary = Color.gray
    static let tertiary = Color.white.opacity(0.35)
}

struct PillButton: View {
    let title: String
    var symbol: String? = nil
    var selected = false
    var scale: CGFloat = 1
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.system(size: 12 * scale, weight: .semibold, design: .rounded))
            .foregroundStyle(selected ? Color.black : (hover ? Color.white : Palette.secondary))
            .padding(.horizontal, 12 * scale)
            .frame(height: 28 * scale)
            .background(Capsule().fill(selected ? Color.white : (hover ? Palette.surfaceHover : Palette.surface)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
