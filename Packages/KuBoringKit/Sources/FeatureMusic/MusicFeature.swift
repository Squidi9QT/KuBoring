import SwiftUI
import AppKit
import Observation
import KuBoringCore

@MainActor
public final class MusicFeature: NotchFeature {
    public let id = "music"
    public let title = "Музыка"
    public let symbol = "music.note"
    public let summary = "Что сейчас играет в любом плеере: обложка, прогресс и управление"
    public var kind: FeatureKind { .tab }
    public var enabledByDefault: Bool { true }

    private let adapterScriptURL: URL?
    private let frameworkURL: URL?
    private let model = MusicModel()
    private var context: FeatureContext?
    private var activityPosted = false
    private var quitObserver: NSObjectProtocol?

    public init(adapterScriptURL: URL?, frameworkURL: URL?) {
        self.adapterScriptURL = adapterScriptURL
        self.frameworkURL = frameworkURL
    }

    public convenience init() {
        self.init(adapterScriptURL: nil, frameworkURL: nil)
    }

    public func start(_ context: FeatureContext) {
        self.context = context
        model.settings = context.settings
        let script = adapterScriptURL
            ?? Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl")
        let framework = frameworkURL
            ?? Bundle.main.privateFrameworksURL?.appendingPathComponent("MediaRemoteAdapter.framework")
        model.onChange = { [weak self] in self?.refreshActivity() }
        model.start(script: script, framework: framework)
        // Системное уведомление AppKit: при выходе гасим perl-адаптер, чтобы он не остался сиротой.
        quitObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.stop() }
        }
    }

    public func stop() {
        if let obs = quitObserver {
            NotificationCenter.default.removeObserver(obs)
            quitObserver = nil
        }
        model.onChange = nil
        model.stop()
        context?.activities.remove(id: "music")
        activityPosted = false
        model.settings = nil
        context = nil
    }

    public func makeTabView() -> AnyView? {
        AnyView(MusicTabView(model: model))
    }

    public func makeSettingsView() -> AnyView? {
        let settings = context?.settings ?? SettingsStore()
        return AnyView(MusicSettingsView(settings: settings, onChange: { [weak self] in
            self?.refreshActivity()
        }))
    }

    /// Показывать активность только пока играет и включено в настройках.
    private func refreshActivity() {
        guard let context else { return }
        let show = context.settings[MusicKeys.showInClosed] && (model.track?.playing ?? false)
        if show {
            guard !activityPosted else { return }
            activityPosted = true
            let m = model
            let s = context.settings
            context.activities.post(LiveActivity(
                id: "music",
                priority: 50,
                leading: AnyView(MusicMiniCover(model: m)),
                trailing: AnyView(MusicEqualizer(model: m, settings: s))
            ))
        } else if activityPosted {
            activityPosted = false
            context.activities.remove(id: "music")
        }
    }
}

struct MusicSettingsView: View {
    let settings: SettingsStore
    let onChange: () -> Void

    var body: some View {
        Group {
            SettingsSection("Закрытая шторка", footer: "Мини-обложка и полоски появляются рядом с вырезом, пока играет музыка.") {
                SettingsToggle("Показывать в закрытой шторке",
                               hint: "Обложка слева, эквалайзер справа",
                               isOn: settings.binding(MusicKeys.showInClosed))
                SettingsToggle("Анимировать полоски",
                               hint: "Если выключить, полоски будут статичными",
                               isOn: settings.binding(MusicKeys.animateBars))
            }
            SettingsSection("Текст песен", footer: "Тексты берутся с бесплатного сервиса lrclib.net: туда уходят только название, исполнитель и длительность трека.") {
                SettingsToggle("Кнопка «Текст песни»",
                               hint: "Во вкладке музыки появится кнопка: вместо названия трека строчки песни подсвечиваются в такт.",
                               isOn: settings.binding(MusicKeys.lyricsEnabled))
            }
            SettingsSection("Источники") {
                SettingsPicker("Что показывать",
                               hint: "Например, чтобы YouTube в браузере не появлялся в шторке",
                               selection: settings.binding(MusicKeys.sourceMode),
                               options: [(MusicSourceMode.all, "Всё"),
                                         (MusicSourceMode.musicOnly, "Только музыкальные приложения"),
                                         (MusicSourceMode.manual, "Выбрать вручную")])
                if settings[MusicKeys.sourceMode] == MusicSourceMode.manual {
                    MusicSourcesList(settings: settings)
                }
            }
        }
        .onChange(of: settings[MusicKeys.showInClosed]) { _, _ in onChange() }
        .onChange(of: settings[MusicKeys.sourceMode]) { _, _ in onChange() }
        .onChange(of: settings[MusicKeys.blockedSources]) { _, _ in onChange() }
    }
}
