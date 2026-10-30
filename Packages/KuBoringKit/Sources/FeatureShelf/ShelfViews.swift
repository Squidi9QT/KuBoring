import SwiftUI
import AppKit
import KuBoringCore

@MainActor
final class ShelfViewHolder {
    weak var view: NSView?
    var picker: NSSharingServicePicker?
}

struct ShelfViewAnchor: NSViewRepresentable {
    let holder: ShelfViewHolder

    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        holder.view = v
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        holder.view = nsView
    }
}

private struct ShelfDropZone: View {
    let notch: NotchController?
    let empty: Bool

    var body: some View {
        if let notch, notch.dragInside || notch.state.phase == .dragging {
            GeometryReader { proxy in
                let hovering = notch.dragLocation.map { proxy.frame(in: .global).contains($0) } ?? false
                DropZoneOverlay(
                    label: "Отпусти, чтобы положить на полку", hovering: hovering,
                    outerRadius: 14, outerInset: 0, inset: 0, showsLabel: empty)
            }
            .padding(.horizontal, 16)
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }
}

struct ShelfTabView: View {
    let model: ShelfModel
    @State private var holder = ShelfViewHolder()
    @State private var selecting = false
    @State private var selected: Set<UUID> = []
    @State private var confirmClear = false
    @State private var renaming: ShelfItem?
    @State private var renameText = ""
    @FocusState private var renameFocused: Bool

    private var isDragging: Bool {
        guard let notch = model.notch else { return false }
        return notch.dragInside || notch.state.phase == .dragging
    }

    private var selectedCount: Int {
        model.items.reduce(0) { $0 + (selected.contains($1.id) ? 1 : 0) }
    }

    var body: some View {
        GeometryReader { geo in
            let listH = max(40, geo.size.height - 52)
            let multiRow = listH >= 230
            let k = AdaptiveMetrics(size: geo.size).scale
            let cardH: CGFloat = multiRow ? adaptiveClamp(115 * k, 110, 140) : adaptiveClamp(listH - 4, 36, 140)
            let cardW = adaptiveClamp(cardH * 0.82, 62, 130)

            VStack(spacing: 8) {
                header
                    .padding(.horizontal, 16)

                if model.items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: adaptiveClamp(28 * k, 24, 44)))
                            .foregroundStyle(.white.opacity(0.35))
                        Text("Перетащи файлы сюда")
                            .font(.system(size: adaptiveClamp(13 * k, 12, 20)))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay { ShelfDropZone(notch: model.notch, empty: true) }
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.white.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                            .padding(.horizontal, 16)
                            .opacity(isDragging ? 0 : 1)
                            .animation(.easeOut(duration: 0.15), value: isDragging)
                    )
                } else if multiRow {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: cardW, maximum: cardW), spacing: 10)],
                            alignment: .leading, spacing: 10
                        ) {
                            ForEach(model.items) { item in
                                card(item, height: cardH)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: .infinity)
                    .overlay { ShelfDropZone(notch: model.notch, empty: false) }
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(model.items) { item in
                                card(item, height: cardH)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: .infinity)
                    .overlay { ShelfDropZone(notch: model.notch, empty: false) }
                }
            }
            .padding(.vertical, 8)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(ShelfViewAnchor(holder: holder))
        .onChange(of: model.items.isEmpty) { _, empty in
            if empty { exitSelection() }
        }
        .onDisappear { if renaming != nil { endRename() } }
        .animation(.easeOut(duration: 0.2), value: model.message)
    }

    private func card(_ item: ShelfItem, height: CGFloat) -> some View {
        ShelfCard(
            item: item, model: model, onShare: share, onRename: startRename,
            selecting: selecting,
            isSelected: selected.contains(item.id),
            onToggle: { toggle(item) },
            cardHeight: height)
    }

    @ViewBuilder
    private var header: some View {
        ZStack {
            if renaming != nil {
                renameRow
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else if confirmClear {
                confirmRow
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                normalHeader
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(minHeight: 24)
        .animation(.easeInOut(duration: 0.2), value: confirmClear)
        .animation(.easeInOut(duration: 0.2), value: renaming?.id)
    }

    private var renameRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
            TextField("Новое имя", text: $renameText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.white)
                .focused($renameFocused)
                .onSubmit(commitRename)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(Color.white.opacity(0.1)))
            headerButton("Отмена") { endRename() }
            headerButton("Готово", weight: .semibold) { commitRename() }
        }
    }

    private func startRename(_ item: ShelfItem) {
        exitSelection()
        renameText = (item.name as NSString).deletingPathExtension
        renaming = item
        model.notch?.hold("shelf.rename", true)
        model.notch?.requestKeyboardFocus()
        Task { @MainActor in renameFocused = true }
    }

    private func commitRename() {
        guard let item = renaming else { return }
        if model.rename(item, to: renameText) { endRename() }
    }

    private func endRename() {
        renaming = nil
        renameFocused = false
        model.notch?.hold("shelf.rename", false)
    }

    private var confirmRow: some View {
        HStack(spacing: 10) {
            Text("Очистить всю полку?")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
            Text("Файлы на диске останутся")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.45))
            Spacer()
            headerButton("Отмена") { confirmClear = false }
            Button {
                model.clear()
                exitSelection()
            } label: {
                Text("Очистить всё")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.red.opacity(0.85)))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var normalHeader: some View {
        HStack(spacing: 10) {
            Text(model.items.isEmpty ? "Полка" : "Полка · \(model.items.count)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            if model.busy {
                ProgressView().controlSize(.mini)
            }
            if let message = model.message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .transition(.opacity)
            }
            Spacer()
            if selecting {
                Text("Выбрано: \(selectedCount)")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.6))
                headerButton(selectedCount == model.items.count && !model.items.isEmpty ? "Снять выбор" : "Выбрать все") {
                    if selectedCount == model.items.count {
                        selected = []
                    } else {
                        selected = Set(model.items.map(\.id))
                    }
                }
                Button {
                    model.removeItems(ids: selected)
                    selected = []
                    if model.items.isEmpty { exitSelection() }
                } label: {
                    Text("Удалить (\(selectedCount))")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selectedCount == 0 ? Color.white.opacity(0.3) : Color.red)
                }
                .buttonStyle(.plain)
                .disabled(selectedCount == 0)
                Button {
                    model.perform(.zip, on: model.items.filter { selected.contains($0.id) })
                    exitSelection()
                } label: {
                    Text("В ZIP")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selectedCount == 0 ? Color.white.opacity(0.3) : Color.white.opacity(0.85))
                }
                .buttonStyle(.plain)
                .disabled(selectedCount == 0 || model.busy)
                .help("Упаковать выбранные в один архив")
                headerButton("Очистить всё") { confirmClear = true }
                headerButton("Готово", weight: .semibold) { exitSelection() }
            } else if !model.items.isEmpty {
                Button {
                    selecting = true
                } label: {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Выбрать")
                .accessibilityLabel("Выбрать")
            }
        }
    }

    private func headerButton(
        _ title: String, weight: Font.Weight = .regular,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: weight))
                .foregroundStyle(.white.opacity(0.7))
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ item: ShelfItem) {
        if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
    }

    private func exitSelection() {
        confirmClear = false
        selecting = false
        selected = []
    }

    private func share(_ item: ShelfItem) {
        guard let url = model.url(for: item), let view = holder.view else { return }
        let picker = NSSharingServicePicker(items: [url])
        holder.picker = picker
        model.holdNotch()
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
}

private struct ShelfCardInteraction: ViewModifier {
    let item: ShelfItem
    let model: ShelfModel
    let selecting: Bool
    let onToggle: () -> Void

    func body(content: Content) -> some View {
        content
            .onDrag {
                guard let url = model.url(for: item) else { return NSItemProvider() }
                let provider = NSItemProvider(object: url as NSURL)
                provider.suggestedName = url.lastPathComponent
                return provider
            }
            .onTapGesture { if selecting { onToggle() } }
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    if !selecting { model.open(item) }
                })
    }
}

struct ShelfCard: View {
    let item: ShelfItem
    let model: ShelfModel
    let onShare: (ShelfItem) -> Void
    var onRename: (ShelfItem) -> Void = { _ in }
    var selecting = false
    var isSelected = false
    var onToggle: () -> Void = {}
    var cardHeight: CGFloat = 122
    @State private var hovering = false

    private var cardFill: Color {
        if selecting && isSelected { return Color.accentColor.opacity(0.25) }
        return Color.white.opacity(hovering ? 0.12 : 0.07)
    }

    var body: some View {
        let pad = adaptiveClamp(cardHeight * 0.07, 5, 10)
        let cardW = adaptiveClamp(cardHeight * 0.82, 62, 130)
        let lines = cardHeight >= 100 ? 2 : 1
        let fontSize = adaptiveClamp(cardHeight * 0.09, 10, 13)
        let nameH = ceil(fontSize * 1.25) * CGFloat(lines)
        let thumb = max(12, cardHeight - 2 * pad - 6 - nameH)
        return VStack(spacing: 6) {
            Group {
                if let img = model.thumbnails[item.id] {
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "doc")
                        .font(.system(size: thumb * 0.42))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .frame(width: cardW - 2 * pad, height: thumb)

            Text(item.name)
                .font(.system(size: fontSize))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(lines)
                .multilineTextAlignment(.center)
                .frame(width: cardW - 2 * pad, height: nameH, alignment: .top)
        }
        .frame(width: cardW, height: cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(cardFill)
        )
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .overlay(alignment: .topTrailing) {
            if selecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.white.opacity(0.5))
                    .padding(5)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .modifier(ShelfCardInteraction(item: item, model: model, selecting: selecting, onToggle: onToggle))
        .contextMenu {
            Button("Открыть") { model.open(item) }
            Button("Показать в Finder") { model.reveal(item) }
            Button("Поделиться…") { onShare(item) }
            Button("AirDrop") { model.airDrop(item) }
            Divider()
            if model.isImage(item) {
                Button("Сжать картинку") { model.perform(.compress, on: [item]) }
                Button("Сохранить как JPG") { model.perform(.jpeg, on: [item]) }
            }
            Button("Упаковать в ZIP") { model.perform(.zip, on: [item]) }
            Button("Переименовать…") { onRename(item) }
            Divider()
            Button("Убрать") { model.remove(item) }
        }
        .task(id: item.id) { await model.loadThumbnail(for: item) }
    }
}

struct ShelfSettingsView: View {
    let settings: SettingsStore
    let model: ShelfModel

    var body: some View {
        Group {
            SettingsSection("Полка", footer: "Файлы не копируются: полка хранит только ссылки на них.") {
                SettingsSlider(
                    "Максимум файлов",
                    hint: "Старые файлы убираются, когда лимит превышен",
                    value: Binding<Double>(
                        get: { Double(settings[ShelfKeys.maxCount]) },
                        set: {
                            settings[ShelfKeys.maxCount] = Int($0); model.trimToMax()
                        }
                    ),
                    in: 5...50, step: 1)
                SettingsToggle(
                    "Помнить файлы после перезапуска",
                    isOn: Binding<Bool>(
                        get: { settings[ShelfKeys.remember] },
                        set: {
                            settings[ShelfKeys.remember] = $0; model.persist()
                        }
                    ))
                SettingsToggle(
                    "Очищать полку при выходе",
                    isOn: settings.binding(ShelfKeys.clearOnQuit))
            }
        }
    }
}
