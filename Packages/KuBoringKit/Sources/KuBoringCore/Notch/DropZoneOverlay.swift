import SwiftUI

public struct DropZoneOverlay: View {
    public let label: String
    public let hovering: Bool
    public let outerRadius: Double
    public let outerInset: Double
    public let inset: Double
    public let showsLabel: Bool

    public init(
        label: String, hovering: Bool,
        outerRadius: Double = 24, outerInset: Double = 0, inset: Double = 10,
        showsLabel: Bool = true
    ) {
        self.showsLabel = showsLabel
        self.label = label
        self.hovering = hovering
        self.outerRadius = outerRadius
        self.outerInset = outerInset
        self.inset = inset
    }

    public var body: some View {
        let ins = CGFloat(inset.rounded())
        let radius = CGFloat(max(8, (outerRadius - outerInset - inset).rounded()))
        GeometryReader { geo in
            let w = max(0, (geo.size.width - 2 * ins).rounded())
            let h = max(0, (geo.size.height - 2 * ins).rounded())
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            ZStack {
                shape.fill(hovering ? Color.accentColor.opacity(0.10) : Color.white.opacity(0.04))
                if hovering {
                    shape.strokeBorder(Color.accentColor.opacity(0.9), lineWidth: 1.5)
                } else {
                    shape.strokeBorder(
                        Color.white.opacity(0.5),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [7, 5]))
                }
                if showsLabel {
                    VStack(spacing: 8) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 26, weight: .medium))
                        Text(label)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.horizontal, 12)
                    .foregroundStyle(hovering ? Color.white : Color.white.opacity(0.8))
                }
            }
            .frame(width: w, height: h)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .allowsHitTesting(false)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}
