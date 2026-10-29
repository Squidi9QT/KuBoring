import SwiftUI
import AppKit
import KuBoringCore

/// Режимы фильтра источников (значения хранятся строкой в настройках).
enum MusicSourceMode {
    static let all = "all"
    static let musicOnly = "music"
    static let manual = "manual"
}

enum MusicSources {
    /// Явно музыкальные приложения (режим «Только музыкальные приложения»).
    static let musicApps: Set<String> = [
        "com.apple.Music", "com.apple.iTunes", "com.spotify.client",
        "ru.yandex.desktop.music", "com.yandex.music",
        "com.tidal.desktop", "com.aspiro.TIDAL", "com.deezer.deezer-desktop",
        "com.apple.podcasts", "com.coppertino.Vox", "com.swinsian.Swinsian",
        "com.soundcloud.desktop", "com.amazon.music",
        "com.audirvana.Audirvana", "com.roon.Roon", "org.videolan.vlc.audio",
        "com.sonos.macController", "com.sonos.macController2",
        "com.apple.Podcasts", "fm.last.Last.fm", "com.plexamp.plexamp"
    ]

    static let browsers: [String] = [
        "com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox",
        "ru.yandex.desktop.yandex-browser", "company.thebrowser.Browser",
        "com.microsoft.edgemac", "com.operasoftware.Opera",
        "com.brave.Browser", "com.vivaldi.Vivaldi", "org.chromium.Chromium"
    ]

    static func appURL(_ id: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    }

    static func icon(for id: String) -> NSImage? {
        guard let url = appURL(id) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    static func name(for id: String) -> String {
        guard let url = appURL(id) else { return id }
        if let info = Bundle(url: url)?.infoDictionary {
            if let n = info["CFBundleDisplayName"] as? String, !n.isEmpty { return n }
            if let n = info["CFBundleName"] as? String, !n.isEmpty { return n }
        }
        var n = FileManager.default.displayName(atPath: url.path)
        if n.hasSuffix(".app") { n = String(n.dropLast(4)) }
        return n.isEmpty ? id : n
    }
}

/// Список приложений-источников с тумблерами (режим «Выбрать вручную»).
struct MusicSourcesList: View {
    let settings: SettingsStore

    var body: some View {
        Group {
            Button("Выключить все браузеры") {
                var blocked = settings[MusicKeys.blockedSources]
                for id in MusicSources.browsers where !blocked.contains(id) {
                    blocked.append(id)
                }
                settings[MusicKeys.blockedSources] = blocked
            }
            if settings[MusicKeys.seenSources].isEmpty {
                Text("Включи музыку или видео — приложение появится здесь")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(settings[MusicKeys.seenSources], id: \.self) { id in
                    MusicSourceRow(bundleID: id, isOn: binding(for: id))
                }
            }
        }
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { !settings[MusicKeys.blockedSources].contains(id) },
            set: { on in
                var blocked = settings[MusicKeys.blockedSources]
                blocked.removeAll { $0 == id }
                if !on { blocked.append(id) }
                settings[MusicKeys.blockedSources] = blocked
            }
        )
    }
}

struct MusicSourceRow: View {
    let bundleID: String
    let isOn: Binding<Bool>

    var body: some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 8) {
                iconView
                Text(MusicSources.name(for: bundleID))
            }
        }
        .toggleStyle(.switch)
    }

    @ViewBuilder
    private var iconView: some View {
        if let icon = MusicSources.icon(for: bundleID) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: "app")
                .frame(width: 22, height: 22)
                .foregroundStyle(.secondary)
        }
    }
}
