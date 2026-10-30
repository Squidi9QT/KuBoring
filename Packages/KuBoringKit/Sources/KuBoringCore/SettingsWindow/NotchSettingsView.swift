import SwiftUI
import AppKit

struct NotchSettingsView: View {
    let settings: SettingsStore
    @State private var previewOpen = true

    private var physical: CGSize {
        if let screen = NSScreen.screens.first { return ScreenMetrics.notchSize(for: screen) }
        return CGSize(width: 185, height: 32)
    }

    private func field<T>(_ keyPath: WritableKeyPath<NotchGeometry, T>) -> Binding<T> {
        Binding(
            get: { settings[CoreKeys.geometry][keyPath: keyPath] },
            set: { newValue in
                var g = settings[CoreKeys.geometry]
                g[keyPath: keyPath] = newValue
                settings[CoreKeys.geometry] = g
            }
        )
    }

    var body: some View {
        let g = settings[CoreKeys.geometry]
        Form {
            Section {
                Picker("Показать", selection: $previewOpen) {
                    Text("Открытая").tag(true)
                    Text("Закрытая").tag(false)
                }
                .pickerStyle(.segmented)
                NotchPreview(geometry: g, physical: physical, open: previewOpen)
                    .frame(height: 230)
            } header: {
                Text("Предпросмотр")
            } footer: {
                Text("Так будет выглядеть шторка. Пунктиром отмечена зона наведения.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            SettingsSection("Открытая шторка") {
                SettingsSlider("Ширина", value: field(\.openWidth), in: 400...900, step: 10, unit: "pt")
                SettingsSlider("Высота", value: field(\.openHeight), in: 120...600, step: 10, unit: "pt")
                SettingsSlider(
                    "Радиус углов", hint: "Скругление нижних углов открытой шторки.",
                    value: field(\.cornerRadius), in: 8...40, step: 1, unit: "pt")
            }

            SettingsSection("Закрытая шторка") {
                SettingsToggle(
                    "Ширина по вырезу",
                    hint: "Реальный вырез на этом экране: \(Int(physical.width)) pt.",
                    isOn: field(\.closedWidthAuto))
                if !g.closedWidthAuto {
                    SettingsSlider("Ширина", value: field(\.closedWidth), in: 100...400, step: 5, unit: "pt")
                }
                SettingsToggle(
                    "Высота по вырезу или меню-бару",
                    hint: "Сейчас: \(Int(physical.height)) pt.",
                    isOn: field(\.closedHeightAuto))
                if !g.closedHeightAuto {
                    SettingsSlider("Высота", value: field(\.closedHeight), in: 20...60, step: 1, unit: "pt")
                }
            }

            SettingsSection("Наведение") {
                SettingsToggle(
                    "Открывать при наведении",
                    hint: "Выключено: шторка открывается только по клику.",
                    isOn: field(\.openOnHover))
                SettingsSlider(
                    "Зона по горизонтали",
                    hint: "На сколько зона наведения шире выреза с каждой стороны.",
                    value: field(\.hoverPaddingX), in: 0...80, step: 1, unit: "pt")
                SettingsSlider(
                    "Зона по вертикали",
                    hint: "На сколько зона наведения ниже выреза.",
                    value: field(\.hoverPaddingY), in: 0...40, step: 1, unit: "pt")
            }

            SettingsSection("Время и анимация") {
                SettingsSlider(
                    "Задержка открытия", hint: "Сколько курсор должен постоять в зоне.",
                    value: field(\.openDelay), in: 0...1, step: 0.05, unit: "с")
                SettingsSlider(
                    "Задержка закрытия", hint: "Сколько ждать после ухода курсора.",
                    value: field(\.closeDelay), in: 0...2, step: 0.05, unit: "с")
                SettingsSlider(
                    "Скорость анимации", hint: "Больше — быстрее.",
                    value: field(\.animationSpeed), in: 0.5...2.0, step: 0.1, unit: "×")
            }

            SettingsSection("Сброс") {
                SettingsResetButton {
                    settings.reset(CoreKeys.geometry)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Шторка")
    }
}

struct NotchPreview: View {
    let geometry: NotchGeometry
    let physical: CGSize
    let open: Bool

    var body: some View {
        let g = geometry.clamped()
        GeometryReader { proxy in
            let closed = NotchLayout.closedBase(g, physical: physical)
            let target = open ? CGSize(width: g.openWidth, height: g.openHeight) : closed
            let ear = NotchLayout.ear(open: open, cornerRadius: g.cornerRadius)
            let bottom = NotchLayout.bottomRadius(open: open, cornerRadius: g.cornerRadius, height: target.height)
            let fullWidth = open ? g.openWidth + 2 * ear : closed.width + 2 * g.hoverPaddingX + 2 * ear
            let fullHeight = open ? g.openHeight : closed.height + g.hoverPaddingY
            let scale = min(proxy.size.width / (fullWidth + 40), proxy.size.height / (fullHeight + 24), 2.5)

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.18))

                VStack(spacing: 0) {
                    Rectangle().fill(Color.gray.opacity(0.18)).frame(height: 4)
                    Spacer()
                }

                if !open {
                    Rectangle()
                        .strokeBorder(
                            Color.accentColor.opacity(0.8),
                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                        )
                        .frame(
                            width: (closed.width + 2 * g.hoverPaddingX) * scale,
                            height: (closed.height + g.hoverPaddingY) * scale)
                }

                NotchShape(topRadius: ear * scale, bottomRadius: bottom * scale)
                    .fill(Color.black)
                    .frame(width: (target.width + 2 * ear) * scale, height: target.height * scale)
                    .overlay(alignment: .center) {
                        Text("\(Int(target.width)) × \(Int(target.height))")
                            .font(.system(size: max(9, 11 * min(scale, 1.4)), design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                    }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: g)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: open)
        }
    }
}
