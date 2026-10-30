import SwiftUI
import Observation

public struct SettingKey<Value: Codable & Sendable>: Sendable {
    public let name: String
    public let defaultValue: Value

    public init(_ name: String, default defaultValue: Value) {
        self.name = name
        self.defaultValue = defaultValue
    }
}

public func featureEnabledKey(_ id: String, default on: Bool = true) -> SettingKey<Bool> {
    SettingKey("feature.\(id).enabled", default: on)
}

@MainActor @Observable
public final class SettingsStore {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var cache: [String: Any] = [:]
    private var revision: Int = 0

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public subscript<V: Codable & Sendable>(_ key: SettingKey<V>) -> V {
        get {
            _ = revision
            if let cached = cache[key.name] as? V { return cached }
            guard let data = defaults.data(forKey: key.name),
                let value = try? JSONDecoder().decode(V.self, from: data)
            else {
                return key.defaultValue
            }
            cache[key.name] = value
            return value
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: key.name)
            }
            cache[key.name] = newValue
            revision &+= 1
        }
    }

    public func binding<V: Codable & Sendable>(_ key: SettingKey<V>) -> Binding<V> {
        Binding(get: { self[key] }, set: { self[key] = $0 })
    }

    public func reset<V: Codable & Sendable>(_ key: SettingKey<V>) {
        defaults.removeObject(forKey: key.name)
        cache[key.name] = nil
        revision &+= 1
    }

    public func reset(prefix: String) {
        for name in defaults.dictionaryRepresentation().keys where name.hasPrefix(prefix) {
            defaults.removeObject(forKey: name)
        }
        for name in Array(cache.keys) where name.hasPrefix(prefix) {
            cache[name] = nil
        }
        revision &+= 1
    }
}
