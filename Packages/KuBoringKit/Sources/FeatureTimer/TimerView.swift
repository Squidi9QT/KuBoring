import SwiftUI
import KuBoringCore

/// Вкладка «Таймер».
struct TimerView: View {
    let model: TimerModel

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let k = AdaptiveMetrics(size: geo.size).scale
            let tall = h > w * 0.75
            let showRing = h >= 120
            let ringSize: CGFloat = tall
                ? adaptiveClamp(min(h * 0.5, w * 0.6), 80, 320)
                : adaptiveClamp(min(h - 12, w * 0.38), 64, 320)
            let layout = tall
                ? AnyLayout(VStackLayout(alignment: .center, spacing: 12 * k))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 22 * k))

            layout {
                timeBlock(ringSize: ringSize, showRing: showRing, w: w, h: h)
                controls(k: k, tall: tall)
            }
            .padding(.horizontal, 8 * k)
            .frame(width: w, height: h)
            .animation(.smooth(duration: 0.3), value: tall)
        }
    }

    // MARK: Цифры

    @ViewBuilder
    private func timeBlock(ringSize: CGFloat, showRing: Bool, w: CGFloat, h: CGFloat) -> some View {
        if showRing {
            let line = adaptiveClamp(ringSize * 0.06, 4, 14)
            ZStack {
                Circle().stroke(Palette.surfaceHover, lineWidth: line)
                Circle()
                    .trim(from: 0, to: model.progress)
                    .stroke(model.tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: model.progress)
                Text(TimerModel.format(model.remaining))
                    .font(.system(size: ringSize * 0.2, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.white)
                    .contentTransition(.numericText(countsDown: true))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(width: ringSize * 0.72)
            }
            .padding(line / 2)
            .frame(width: ringSize, height: ringSize)
        } else {
            let blockW = adaptiveClamp(w * 0.28, 90, 260)
            VStack(spacing: 6) {
                Text(TimerModel.format(model.remaining))
                    .font(.system(size: adaptiveClamp(h * 0.42, 28, 80), weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.white)
                    .contentTransition(.numericText(countsDown: true))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                GeometryReader { bar in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Palette.surfaceHover)
                        Capsule().fill(model.tint)
                            .frame(width: bar.size.width * min(1, max(0, model.progress)))
                    }
                }
                .frame(height: 4)
                .animation(.linear(duration: 0.25), value: model.progress)
            }
            .frame(width: blockW)
        }
    }

    // MARK: Управление

    private func presetsRow(k: CGFloat) -> some View {
        HStack(spacing: 6 * k) {
            PillButton(title: "🍅 Помидор", selected: model.pomodoro, scale: k) {
                withAnimation(.smooth) { model.setPomodoro(!model.pomodoro) }
            }
            .help("Работа и перерывы по очереди: 4 × (работа + перерыв), потом длинный перерыв")
            if model.pomodoro {
                Text("\(model.phase.title) · \(model.cycleNumber)/4")
                    .font(.system(size: 12 * k, weight: .semibold, design: .rounded))
                    .foregroundStyle(model.tint)
                    .lineLimit(1)
                    .fixedSize()
            } else {
                ForEach(Array(model.presets.enumerated()), id: \.offset) { _, m in
                    PillButton(title: "\(m) мин",
                               selected: !model.isRunning && Int(model.total) == m * 60,
                               scale: k) {
                        withAnimation(.smooth) { model.set(minutes: m) }
                    }
                }
            }
        }
    }

    private func controls(k: CGFloat, tall: Bool) -> some View {
        let btn = adaptiveClamp(32 * k, 28, 52)
        return VStack(alignment: tall ? .center : .leading, spacing: 12 * k) {
            // Пресеты в ряд; если не влезают по ширине — прокрутка.
            ViewThatFits(in: .horizontal) {
                presetsRow(k: k)
                ScrollView(.horizontal, showsIndicators: false) {
                    presetsRow(k: k)
                }
            }

            HStack(spacing: 10 * k) {
                IconButton(symbol: "minus", size: btn, help: "Минус минута", iconSize: 12 * k) {
                    model.adjust(minutes: -1)
                }
                IconButton(symbol: "plus", size: btn, help: "Плюс минута", iconSize: 12 * k) {
                    model.adjust(minutes: 1)
                }

                Button {
                    withAnimation(.smooth) { model.toggle() }
                } label: {
                    Label(model.isRunning ? "Пауза" : (model.isPaused ? "Продолжить" : "Старт"),
                          systemImage: model.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 13 * k, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.black)
                        .lineLimit(1)
                        .padding(.horizontal, 16 * k)
                        .frame(height: btn)
                        .background(Capsule().fill(model.tint))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)

                IconButton(symbol: "arrow.counterclockwise", size: btn, help: "Сбросить", iconSize: 12 * k) {
                    withAnimation(.smooth) { model.reset() }
                }
            }

            if model.finished {
                Label("Время вышло", systemImage: "bell.fill")
                    .font(.system(size: 12 * k, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.timer)
            }
        }
        .frame(maxWidth: .infinity, alignment: tall ? .center : .leading)
    }
}
