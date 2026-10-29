import AppKit
import SwiftUI

/// Окно приветствия: показывается при первом запуске (и из меню «Что умеет KuBoring»).
@MainActor
public final class OnboardingWindowController {
    private let settings: SettingsStore
    private let onOpenSettings: () -> Void
    private var window: NSWindow?

    public init(settings: SettingsStore, onOpenSettings: @escaping () -> Void) {
        self.settings = settings
        self.onOpenSettings = onOpenSettings
    }

    /// Показать, если пользователь ещё не видел приветствие.
    public func showIfNeeded() {
        guard !settings[CoreKeys.onboardingShown] else { return }
        show()
    }

    public func show() {
        if window == nil {
            let root = OnboardingView(
                onSettings: { [weak self] in
                    self?.finish()
                    self?.onOpenSettings()
                },
                onDone: { [weak self] in self?.finish() })
            let controller = NSHostingController(rootView: root)
            let w = NSWindow(contentViewController: controller)
            w.title = "Добро пожаловать в KuBoring"
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 560, height: 560))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        settings[CoreKeys.onboardingShown] = true
        window?.close()
    }
}

private struct OnboardingView: View {
    let onSettings: () -> Void
    let onDone: () -> Void

    private let items: [(String, String, String)] = [
        ("cursorarrow.motionlines", "Наведи на вырез", "Шторка раскроется. Свайп двумя пальцами по шапке — соседняя вкладка, вверх — закрыть."),
        ("tray.and.arrow.down", "Перетащи файл на вырез", "Он ляжет на полку. Правый клик по файлу: сжать, в JPG, в ZIP, переименовать."),
        ("doc.on.clipboard", "⌘⇧V — история буфера", "Текст и картинки, закрепление. Включается в настройках «Буфера»."),
        ("quote.bubble", "Текст песен", "Во вкладке «Музыка» строчки подсвечиваются в такт треку."),
        ("video", "Созвоны", "Отсчёт до созвона в шторке и кнопка «Войти» во вкладке календаря."),
        ("battery.75percent", "Батарея и переключатели", "Клик по проценту в шапке: зарядка, энергосбережение, тёмная тема, «не засыпать»."),
    ]

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Image(systemName: "rectangle.topthird.inset.filled")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(.tint)
                Text("KuBoring")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text("Твоя шторка у выреза экрана")
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 24)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(items, id: \.1) { symbol, title, text in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: symbol)
                            .font(.system(size: 18))
                            .foregroundStyle(.tint)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title).font(.system(size: 13, weight: .semibold))
                            Text(text)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(.horizontal, 36)

            Spacer(minLength: 0)

            HStack {
                Button("Открыть настройки", action: onSettings)
                Spacer()
                Button("Начать", action: onDone)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 24)
        }
        .frame(width: 560, height: 560)
    }
}
