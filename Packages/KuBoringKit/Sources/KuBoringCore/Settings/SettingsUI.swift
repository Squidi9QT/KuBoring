import SwiftUI

private struct SettingsLabel: View {
    let title: String
    let hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

public struct SettingsSection<Content: View>: View {
    private let title: String
    private let footer: String?
    private let content: Content

    public init(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    public var body: some View {
        Section {
            content
        } header: {
            Text(title)
        } footer: {
            if let footer {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

public struct SettingsToggle: View {
    private let title: String
    private let hint: String?
    private let isOn: Binding<Bool>

    public init(_ title: String, hint: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.hint = hint
        self.isOn = isOn
    }

    public var body: some View {
        Toggle(isOn: isOn) {
            SettingsLabel(title: title, hint: hint)
        }
        .toggleStyle(.switch)
    }
}

public struct SettingsSlider: View {
    private let title: String
    private let hint: String?
    private let value: Binding<Double>
    private let range: ClosedRange<Double>
    private let step: Double
    private let unit: String

    public init(
        _ title: String, hint: String? = nil, value: Binding<Double>,
        in range: ClosedRange<Double>, step: Double = 1, unit: String = ""
    ) {
        self.title = title
        self.hint = hint
        self.value = value
        self.range = range
        self.step = step
        self.unit = unit
    }

    private var formatted: String {
        let v = value.wrappedValue
        let text = step >= 1 ? String(Int(v.rounded())) : String(format: "%.2f", v)
        return unit.isEmpty ? text : "\(text) \(unit)"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(formatted)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }
}

public struct SettingsPicker<T: Hashable>: View {
    private let title: String
    private let hint: String?
    private let selection: Binding<T>
    private let options: [(T, String)]

    public init(_ title: String, hint: String? = nil, selection: Binding<T>, options: [(T, String)]) {
        self.title = title
        self.hint = hint
        self.selection = selection
        self.options = options
    }

    public var body: some View {
        Picker(selection: selection) {
            ForEach(options.indices, id: \.self) { i in
                Text(options[i].1).tag(options[i].0)
            }
        } label: {
            SettingsLabel(title: title, hint: hint)
        }
    }
}

public struct SettingsResetButton: View {
    private let title: String
    private let action: () -> Void

    public init(_ title: String = "Сбросить раздел", action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        HStack {
            Spacer()
            Button(role: .destructive, action: action) {
                Label(title, systemImage: "arrow.counterclockwise")
            }
        }
    }
}
