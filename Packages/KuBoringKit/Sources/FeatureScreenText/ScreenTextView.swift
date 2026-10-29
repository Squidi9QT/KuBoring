import SwiftUI
import KuBoringCore

/// Вкладка «Текст с экрана».
struct ScreenTextView: View {
    let model: ScreenTextModel

    var body: some View {
        GeometryReader { geo in
            let k = AdaptiveMetrics(size: geo.size).scale
            // Заглушка «Спросить ИИ» самая широкая — убираем её, когда не хватает ширины.
            let showAI = geo.size.width / k >= 580
            VStack(alignment: .leading, spacing: 10 * k) {
                HStack(spacing: 8 * k) {
                    PillButton(title: model.status == .selecting ? "Выделите область…" : "Выделить область",
                               symbol: "viewfinder", selected: !model.isBusy, scale: k) {
                        model.capture()
                    }
                    .disabled(model.isBusy)

                    if model.status == .recognizing {
                        ProgressView().controlSize(.small)
                        Text("Распознаю…")
                            .font(.system(size: 12 * k))
                            .foregroundStyle(Palette.secondary)
                    }
                    Spacer(minLength: 0)
                    if !model.text.isEmpty {
                        PillButton(title: model.justCopied ? "Скопировано" : "Скопировать",
                                   symbol: model.justCopied ? "checkmark" : "doc.on.doc", scale: k) {
                            model.copyText()
                        }
                    }
                    // Заготовка под локальную ИИ.
                    if showAI {
                        PillButton(title: "Спросить локальную ИИ (скоро)", symbol: "cpu", scale: k) {}
                            .disabled(true)
                            .opacity(0.4)
                    }
                }

                content(k: k)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }

    @ViewBuilder private func content(k: CGFloat) -> some View {
        if case .failed(let message) = model.status {
            EmptyHintView(symbol: "exclamationmark.triangle", title: "Не получилось", subtitle: message)
        } else if model.nothingFound {
            EmptyHintView(symbol: "text.magnifyingglass", title: "Текст не найден",
                          subtitle: "Попробуйте выделить область покрупнее.")
        } else if model.text.isEmpty {
            EmptyHintView(symbol: "text.viewfinder", title: "Нажмите «Выделить область»",
                          subtitle: "Обведите мышью текст на экране — он распознаётся и скопируется.\nНужно разрешение «Запись экрана» в системных настройках.")
        } else {
            ScrollView {
                Text(model.text)
                    .font(.system(size: 13 * k))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10 * k)
            }
            .background(RoundedRectangle(cornerRadius: 12 * k, style: .continuous).fill(Palette.surface))
        }
    }
}

private struct EmptyHintView: View {
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
