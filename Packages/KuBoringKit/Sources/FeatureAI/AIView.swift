import AppKit
import SwiftUI
import WebKit
import KuBoringCore

struct AIView: View {
    let model: AIModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                servicePicker
                    .frame(maxWidth: .infinity, alignment: .leading)
                if model.isLoading {
                    ProgressView().controlSize(.small)
                }
                if model.current != .browser {
                    IconButton(symbol: "chevron.left", help: "Назад") { model.goBack() }
                        .disabled(!model.canGoBack)
                        .opacity(model.canGoBack ? 1 : 0.35)
                    IconButton(symbol: "house", help: "На главную") { model.goHome() }
                    IconButton(symbol: "arrow.clockwise", help: "Обновить") { model.reload() }
                    IconButton(symbol: "safari", help: "Открыть в браузере") { model.openInBrowser() }
                }
            }

            if model.current == .browser {
                BrowserBar(model: model)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(white: 0.08))
                WebContainer(webView: model.webView(for: model.current))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Palette.stroke, lineWidth: 1)
            )
            .overlay {
                if model.notch?.dropHover == true {
                    DropZoneOverlay(
                        label: "Отпусти, чтобы отправить в чат", hovering: true,
                        outerRadius: 16, outerInset: 0)
                }
            }
            .animation(.easeOut(duration: 0.15), value: model.notch?.dropHover)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            model.ensureCurrentVisible()
            model.setViewShown(true)
        }
        .onDisappear {
            model.setTyping(false)
            model.setViewShown(false)
        }
        .onChange(of: model.notch?.state.phase) { _, phase in
            if phase != .open { model.setTyping(false) }
            model.updateIdleTimer()
        }
    }

    private var servicePicker: some View {
        ViewThatFits(in: .horizontal) {
            chips(showNames: true)
            chips(showNames: false)
            ScrollView(.horizontal, showsIndicators: false) {
                chips(showNames: false)
            }
        }
    }

    private func chips(showNames: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(model.visibleServices) { service in
                ServiceChip(service: service, selected: model.current == service, showName: showNames) {
                    model.select(service)
                }
            }
        }
        .padding(2)
        .background(Capsule().fill(Palette.surface))
    }
}

private struct ServiceChip: View {
    let service: AIService
    let selected: Bool
    let showName: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: service.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(service.tint)
                if showName {
                    Text(service.name)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .foregroundStyle(selected ? Color.white : Palette.secondary)
            .padding(.horizontal, showName ? 12 : 10)
            .frame(height: 28)
            .background(Capsule().fill(selected ? Palette.surfaceHover : Color.clear))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(showName ? service.subtitle : service.name)
    }
}

private struct BrowserBar: View {
    @Bindable var model: AIModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            IconButton(symbol: "chevron.left", help: "Назад") { model.goBack() }
                .disabled(!model.canGoBack)
                .opacity(model.canGoBack ? 1 : 0.35)
            IconButton(symbol: "chevron.right", help: "Вперёд") { model.goForward() }
                .disabled(!model.canGoForward)
                .opacity(model.canGoForward ? 1 : 0.35)
            IconButton(symbol: "arrow.clockwise", help: "Обновить") { model.reload() }

            TextField("Адрес или поисковый запрос", text: $model.addressText)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(Color.white)
                .autocorrectionDisabled()
                .focused($focused)
                .onSubmit {
                    model.submitAddress(model.addressText)
                    focused = false
                }
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule().fill(Palette.surface))
                .overlay(Capsule().strokeBorder(focused ? Palette.surfaceHover : Palette.stroke, lineWidth: 1))
                .onChange(of: focused) { _, isFocused in
                    model.addressFocusChanged(isFocused)
                }

            IconButton(symbol: "house", help: "Домашняя страница") { model.goHome() }
            IconButton(symbol: "safari", help: "Открыть в браузере по умолчанию") { model.openInBrowser() }
        }
    }
}

private struct WebContainer: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if container.subviews.first !== webView { attach(to: container) }
    }

    private func attach(to container: NSView) {
        container.subviews.forEach { $0.removeFromSuperview() }
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
    }
}
