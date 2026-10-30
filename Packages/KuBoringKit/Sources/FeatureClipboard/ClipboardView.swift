import AppKit
import SwiftUI
import KuBoringCore

struct ClipboardView: View {
    @Bindable var model: ClipboardModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        GeometryReader { geo in
            content(k: AdaptiveMetrics(size: geo.size).scale)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .onAppear { if model.keyboardMode { searchFocused = true } }
        .onChange(of: model.keyboardMode) { _, on in if on { searchFocused = true } }
        .onDisappear {
            model.notch?.hold("clipboard.search", false)
            model.notchClosed()
        }
    }

    private func content(k: CGFloat) -> some View {
        let list = model.visibleItems
        return VStack(spacing: 8 * k) {
            HStack(spacing: 8 * k) {
                HStack(spacing: 6 * k) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12 * k, weight: .semibold))
                        .foregroundStyle(Palette.tertiary)
                    TextField("Поиск в истории", text: $model.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13 * k))
                        .foregroundStyle(Color.white)
                        .focused($searchFocused)
                        .onChange(of: model.query) { _, _ in
                            if model.keyboardMode { model.selectedID = model.visibleItems.first?.id }
                        }
                }
                .padding(.horizontal, 12 * k)
                .frame(height: 30 * k)
                .background(Capsule().fill(Palette.surface))
                .contentShape(Capsule())
                .onTapGesture { searchFocused = true }
                .onChange(of: searchFocused) { _, focused in
                    model.notch?.hold("clipboard.search", focused)
                }

                if model.keyboardMode {
                    Text("↑↓  ⏎ вставить  esc")
                        .font(.system(size: 10 * k, weight: .medium).monospaced())
                        .foregroundStyle(Palette.tertiary)
                        .lineLimit(1)
                        .fixedSize()
                } else if model.items.contains(where: { !$0.pinned }) {
                    PillButton(title: "Очистить", scale: k) { withAnimation(.smooth) { model.clear() } }
                        .help("Закреплённые записи останутся")
                }
            }

            if model.items.isEmpty {
                EmptyHint(
                    symbol: "list.clipboard", title: "Пока пусто",
                    subtitle:
                        "Скопируй текст или картинку — они появятся здесь.\nПароли из менеджеров паролей не сохраняются."
                )
            } else if list.isEmpty {
                EmptyHint(symbol: "magnifyingglass", title: "Ничего не найдено")
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 2 * k) {
                            ForEach(list) { item in
                                ClipRow(
                                    item: item, model: model, k: k,
                                    copied: model.justCopiedID == item.id,
                                    selected: model.keyboardMode && model.selectedID == item.id
                                )
                                .id(item.id)
                            }
                        }
                    }
                    .onChange(of: model.selectedID) { _, id in
                        guard let id else { return }
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct ClipRow: View {
    let item: ClipItem
    let model: ClipboardModel
    let k: CGFloat
    let copied: Bool
    let selected: Bool

    @State private var hover = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                withAnimation(.smooth) {
                    if model.keyboardMode { model.choose(item) } else { model.copy(item) }
                }
            } label: {
                label
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(model.keyboardMode ? "Вставить" : "Нажми, чтобы скопировать снова")

            trailing
        }
        .padding(.horizontal, 12 * k)
        .frame(height: (item.isImage ? 44 : 32) * k)
        .background(
            RoundedRectangle(cornerRadius: 10 * k, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.35) : (hover ? Palette.surfaceHover : Color.clear))
        )
        .onHover { hover = $0 }
        .contextMenu {
            Button(item.pinned ? "Открепить" : "Закрепить") { withAnimation(.smooth) { model.togglePin(item) } }
            Button("Удалить из истории") { withAnimation(.smooth) { model.remove(item) } }
        }
    }

    @ViewBuilder private var label: some View {
        HStack(spacing: 8 * k) {
            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9 * k, weight: .semibold))
                    .foregroundStyle(Color.yellow.opacity(0.9))
            }
            if let image = model.thumbnail(for: item) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52 * k, height: 34 * k)
                    .clipShape(RoundedRectangle(cornerRadius: 6 * k, style: .continuous))
                Text(imageSize(image))
                    .font(.system(size: 11 * k))
                    .foregroundStyle(Palette.tertiary)
            } else {
                Text(
                    item.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "\n", with: " ")
                )
                .font(.system(size: 13 * k))
                .foregroundStyle(Color.white.opacity(0.92))
                .lineLimit(1)
            }
        }
    }

    private func imageSize(_ image: NSImage) -> String {
        let rep = image.representations.first
        let w = rep?.pixelsWide ?? Int(image.size.width)
        let h = rep?.pixelsHigh ?? Int(image.size.height)
        return "Картинка \(w)×\(h)"
    }

    @ViewBuilder private var trailing: some View {
        if copied {
            Label("Скопировано", systemImage: "checkmark")
                .font(.system(size: 11 * k, weight: .semibold))
                .foregroundStyle(Color.green)
        } else if hover {
            HStack(spacing: 2) {
                rowButton(item.pinned ? "pin.slash" : "pin", help: item.pinned ? "Открепить" : "Закрепить") {
                    model.togglePin(item)
                }
                rowButton("xmark", help: "Удалить из истории") { model.remove(item) }
            }
        }
    }

    private func rowButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.smooth) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10 * k, weight: .bold))
                .foregroundStyle(Palette.tertiary)
                .frame(width: 20 * k, height: 20 * k)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
