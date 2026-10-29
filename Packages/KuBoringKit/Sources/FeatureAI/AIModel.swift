import AppKit
import SwiftUI
import WebKit
import Observation
import KuBoringCore

enum AIService: String, CaseIterable, Identifiable {
    case claude, chatgpt, perplexity, gemini, qwen, deepseek, browser

    var id: String { rawValue }

    var name: String {
        switch self {
        case .claude: return "Claude"
        case .chatgpt: return "ChatGPT"
        case .perplexity: return "Perplexity"
        case .gemini: return "Gemini"
        case .qwen: return "Qwen"
        case .deepseek: return "DeepSeek"
        case .browser: return "Браузер"
        }
    }

    var subtitle: String {
        switch self {
        case .claude: return "Для серьёзных задач"
        case .chatgpt: return "ИИ от OpenAI"
        case .perplexity: return "Быстрый поиск со ссылками"
        case .gemini: return "ИИ от Google"
        case .qwen: return "ИИ от Alibaba"
        case .deepseek: return "Рассуждающая модель"
        case .browser: return "Любые сайты"
        }
    }

    /// Только SF Symbols, без логотипов.
    var symbol: String {
        switch self {
        case .claude: return "sparkles"
        case .chatgpt: return "bubble.left.and.bubble.right"
        case .perplexity: return "magnifyingglass"
        case .gemini: return "diamond"
        case .qwen: return "cloud"
        case .deepseek: return "water.waves"
        case .browser: return "globe"
        }
    }

    var tint: Color {
        switch self {
        case .claude: return Color(red: 0.85, green: 0.47, blue: 0.34)
        case .chatgpt: return Color(red: 0.25, green: 0.72, blue: 0.58)
        case .perplexity: return Color(red: 0.13, green: 0.71, blue: 0.75)
        case .gemini: return Color(red: 0.42, green: 0.55, blue: 0.95)
        case .qwen: return Color(red: 0.55, green: 0.45, blue: 0.90)
        case .deepseek: return Color(red: 0.30, green: 0.50, blue: 0.95)
        case .browser: return Color(red: 0.55, green: 0.75, blue: 0.55)
        }
    }

    /// Стартовая страница. У «Браузера» своя (из настроек) — см. AIModel.homeURL.
    var url: URL {
        switch self {
        case .claude: return URL(string: "https://claude.ai/new")!
        case .chatgpt: return URL(string: "https://chatgpt.com/")!
        case .perplexity: return URL(string: "https://www.perplexity.ai/")!
        case .gemini: return URL(string: "https://gemini.google.com/app")!
        case .qwen: return URL(string: "https://chat.qwen.ai/")!
        case .deepseek: return URL(string: "https://chat.deepseek.com/")!
        case .browser: return URL(string: "https://www.google.com/")!
        }
    }

    /// Домен для подписи в настройках.
    var domain: String {
        switch self {
        case .browser: return "любые сайты"
        default: return url.host ?? ""
        }
    }

    /// «Свои» домены: переходы по ним остаются внутри окна (вход через Google/почту не выкидывает наружу).
    var ownHosts: [String] {
        switch self {
        case .claude: return ["claude.ai", "anthropic.com"]
        case .chatgpt: return ["chatgpt.com", "openai.com", "auth.openai.com", "oaistatic.com", "oaiusercontent.com"]
        case .perplexity: return ["perplexity.ai", "pplx.ai"]
        case .gemini: return ["gemini.google.com", "accounts.google.com", "google.com", "gstatic.com", "googleusercontent.com"]
        case .qwen: return ["qwen.ai", "aliyun.com", "alibabacloud.com"]
        case .deepseek: return ["deepseek.com"]
        case .browser: return []
        }
    }
}

enum SearchEngine: String, CaseIterable, Identifiable {
    case google, yandex, duckduckgo

    var id: String { rawValue }

    var name: String {
        switch self {
        case .google: return "Google"
        case .yandex: return "Яндекс"
        case .duckduckgo: return "DuckDuckGo"
        }
    }

    var queryPrefix: String {
        switch self {
        case .google: return "https://www.google.com/search?q="
        case .yandex: return "https://yandex.ru/search/?text="
        case .duckduckgo: return "https://duckduckgo.com/?q="
        }
    }
}

enum AIKeys {
    // Устаревшие тумблеры: читаются только для миграции в `services`.
    static let showClaude = SettingKey<Bool>("feature.ai.showClaude", default: true)
    static let showPerplexity = SettingKey<Bool>("feature.ai.showPerplexity", default: true)
    /// Включённые сервисы (id), порядок = порядок в переключателе. Пусто = ещё не мигрировано.
    static let services = SettingKey<[String]>("feature.ai.services", default: [])
    static let defaultService = SettingKey<String>("feature.ai.defaultService", default: "claude")
    static let width = SettingKey<Double>("feature.ai.width", default: 760)
    static let height = SettingKey<Double>("feature.ai.height", default: 580)
    static let browserHome = SettingKey<String>("feature.ai.browserHome", default: "https://www.google.com")
    static let searchEngine = SettingKey<String>("feature.ai.searchEngine", default: "google")
    /// Сколько веб-страниц держать в памяти одновременно (0 = все сервисы).
    static let keepAlive = SettingKey<Int>("feature.ai.keepAlive", default: 2)
    /// Через сколько минут после закрытия шторки выгрузить страницы (0 = никогда).
    static let unloadMinutes = SettingKey<Int>("feature.ai.unloadMinutes", default: 10)
}

/// WKWebView, который сообщает о фокусе ввода (нужен для hold("ai.typing")).
final class FocusWebView: WKWebView {
    var onFocusChange: ((Bool) -> Void)?
    /// Какому сервису принадлежит окно (делегат решает, что открывать внутри).
    var service: AIService?
    /// Файл тащат над страницей / ушли / бросили (для подсветки зоны).
    var onDragHover: ((Bool) -> Void)?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let result = super.draggingEntered(sender)
        onDragHover?(true)
        return result
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        super.draggingExited(sender)
        onDragHover?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let result = super.performDragOperation(sender)
        onDragHover?(false)
        return result
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        super.draggingEnded(sender)
        onDragHover?(false)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result { onFocusChange?(true) }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { onFocusChange?(false) }
        return result
    }

    override func mouseDown(with event: NSEvent) {
        // Клик по странице — человек собирается печатать: окно шторки должно стать key.
        if let window, !window.isKeyWindow { window.makeKey() }
        onFocusChange?(true)
        super.mouseDown(with: event)
    }
}

/// Держит по одному веб-окну на сервис, чтобы вход и переписка не терялись при переключении.
@MainActor @Observable
final class AIModel {
    var current: AIService = .claude
    var isLoading = false
    var canGoBack = false
    var canGoForward = false
    var statusMessage: String?
    /// Текст в адресной строке «Браузера».
    var addressText = ""

    private(set) var settings: SettingsStore?
    @ObservationIgnored private(set) var notch: NotchController?
    @ObservationIgnored private var views: [AIService: FocusWebView] = [:]
    @ObservationIgnored private var urlObservers: [AIService: NSKeyValueObservation] = [:]
    @ObservationIgnored private var typing = false
    @ObservationIgnored private var addressEditing = false
    @ObservationIgnored private let delegate = AIWebDelegate()
    // Политика выгрузки
    @ObservationIgnored private var accessOrder: [AIService] = []   // последний = использован позже всех
    @ObservationIgnored private var idleTask: Task<Void, Never>?
    @ObservationIgnored private var viewShown = false
    @ObservationIgnored private var typingService: AIService?
    @ObservationIgnored private var lastTypedAt: Date?

    /// Сайтам лучше работает обычный Safari.
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    static let typingReason = "ai.typing"

    init() {
        delegate.model = self
    }

    func attach(_ context: FeatureContext) {
        settings = context.settings
        notch = context.notch
        // Миграция: старые тумблеры showClaude/showPerplexity -> список services.
        if let settings, settings[AIKeys.services].isEmpty {
            settings[AIKeys.services] = enabledServices.map { $0.rawValue }
        }
        current = defaultVisibleService
    }

    /// Освободить всё: убрать hold, выбросить веб-окна.
    func shutdown() {
        setTyping(false)
        idleTask?.cancel()
        idleTask = nil
        viewShown = false
        typingService = nil
        lastTypedAt = nil
        for service in Array(views.keys) { unload(service) }
        urlObservers.removeAll()
        views.removeAll()
        accessOrder.removeAll()
        isLoading = false
        canGoBack = false
        canGoForward = false
    }

    // MARK: - Настройки

    /// Включённые сервисы в порядке переключателя.
    var enabledServices: [AIService] {
        guard let settings else { return [.claude, .perplexity] }
        var ids = settings[AIKeys.services]
        if ids.isEmpty {
            // Ключа ещё нет: собираем из старых тумблеров.
            if settings[AIKeys.showClaude] { ids.append(AIService.claude.rawValue) }
            if settings[AIKeys.showPerplexity] { ids.append(AIService.perplexity.rawValue) }
        }
        var list: [AIService] = []
        for id in ids {
            if let service = AIService(rawValue: id), !list.contains(service) { list.append(service) }
        }
        return list.isEmpty ? [.claude] : list
    }

    var visibleServices: [AIService] { enabledServices }

    /// Для списка в настройках: сначала включённые (в своём порядке), потом выключенные.
    var settingsOrderedServices: [AIService] {
        let enabled = enabledServices
        return enabled + AIService.allCases.filter { !enabled.contains($0) }
    }

    var defaultVisibleService: AIService {
        let visible = visibleServices
        if let raw = settings?[AIKeys.defaultService], let service = AIService(rawValue: raw),
           visible.contains(service) {
            return service
        }
        return visible[0]
    }

    var openSize: CGSize {
        CGSize(width: settings?[AIKeys.width] ?? 760, height: settings?[AIKeys.height] ?? 580)
    }

    var searchEngine: SearchEngine {
        SearchEngine(rawValue: settings?[AIKeys.searchEngine] ?? "") ?? .google
    }

    func isEnabled(_ service: AIService) -> Bool { enabledServices.contains(service) }

    /// Нельзя выключить последний включённый сервис.
    func canToggle(_ service: AIService) -> Bool {
        !(isEnabled(service) && enabledServices.count <= 1)
    }

    func setEnabled(_ service: AIService, _ on: Bool) {
        guard let settings else { return }
        var list = enabledServices
        if on {
            if !list.contains(service) { list.append(service) }
        } else {
            guard list.count > 1 else { return }
            list.removeAll { $0 == service }
        }
        settings[AIKeys.services] = list.map { $0.rawValue }
        // Выключили сервис по умолчанию — берём первый включённый.
        let currentDefault = AIService(rawValue: settings[AIKeys.defaultService])
        if currentDefault == nil || !list.contains(currentDefault!) {
            settings[AIKeys.defaultService] = list[0].rawValue
        }
        ensureCurrentVisible()
    }

    /// Сдвинуть включённый сервис вверх (-1) или вниз (+1).
    func move(_ service: AIService, by delta: Int) {
        guard let settings else { return }
        var list = enabledServices
        guard let index = list.firstIndex(of: service) else { return }
        let target = index + delta
        guard target >= 0, target < list.count else { return }
        list.swapAt(index, target)
        settings[AIKeys.services] = list.map { $0.rawValue }
    }

    func canMove(_ service: AIService, by delta: Int) -> Bool {
        let list = enabledServices
        guard let index = list.firstIndex(of: service) else { return false }
        let target = index + delta
        return target >= 0 && target < list.count
    }

    /// Если текущий сервис скрыли в настройках — переключиться на доступный.
    func ensureCurrentVisible() {
        if !visibleServices.contains(current) { select(defaultVisibleService) }
    }

    // MARK: - Адреса

    /// Строка похожа на адрес сайта (есть точка и нет пробелов) или имеет схему http(s).
    private func urlFromInput(_ input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        let lower = text.lowercased()
        let hasScheme = lower.hasPrefix("http://") || lower.hasPrefix("https://")
        guard hasScheme || text.contains(".") else { return nil }
        let full = hasScheme ? text : "https://" + text
        guard let url = URL(string: full), let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    private func searchURL(_ query: String) -> URL? {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=#?/")
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: searchEngine.queryPrefix + encoded)
    }

    var browserHomeURL: URL {
        urlFromInput(settings?[AIKeys.browserHome] ?? "") ?? AIService.browser.url
    }

    func homeURL(for service: AIService) -> URL {
        service == .browser ? browserHomeURL : service.url
    }

    /// Enter в адресной строке: адрес или поиск.
    func submitAddress(_ input: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let url = urlFromInput(text) ?? searchURL(text) else { return }
        webView(for: .browser).load(URLRequest(url: url))
    }

    /// Фокус адресной строки: держим шторку открытой, пока в ней печатают.
    func addressFocusChanged(_ focused: Bool) {
        addressEditing = focused
        if focused {
            setTyping(true)
        } else {
            // Если фокус ушёл на саму страницу, hold остаётся за ней.
            if let view = views[.browser], let responder = view.window?.firstResponder as? NSView,
               responder === view || responder.isDescendant(of: view) {
                // оставляем как есть
            } else {
                setTyping(false)
            }
            addressText = views[.browser]?.url?.absoluteString ?? addressText
        }
    }

    // MARK: - WebView

    /// Создаётся лениво при первом показе сервиса и кэшируется.
    func webView(for service: AIService) -> FocusWebView {
        touch(service)
        if let existing = views[service] { return existing }

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let view = FocusWebView(frame: .zero, configuration: config)
        view.service = service
        view.customUserAgent = Self.userAgent
        view.uiDelegate = delegate
        view.navigationDelegate = delegate
        view.allowsBackForwardNavigationGestures = true
        view.underPageBackgroundColor = .black
        view.setValue(false, forKey: "drawsBackground")
        view.onFocusChange = { [weak self] focused in
            self?.setTyping(focused)
        }
        view.onDragHover = { [weak self] hovering in
            guard let notch = self?.notch, notch.dropHover != hovering else { return }
            notch.dropHover = hovering
        }
        // Адрес меняется и без загрузки страницы (SPA): следим за url.
        urlObservers[service] = view.observe(\.url, options: []) { [weak self, weak view] _, _ in
            Task { @MainActor in
                guard let self, let view else { return }
                self.sync(view)
            }
        }
        view.load(URLRequest(url: homeURL(for: service)))
        views[service] = view
        enforceLimit(keeping: service)
        return view
    }

    // MARK: - Выгрузка из памяти

    private func touch(_ service: AIService) {
        accessOrder.removeAll { $0 == service }
        accessOrder.append(service)
    }

    /// LRU: живых веб-вью не больше лимита из настроек.
    private func enforceLimit(keeping service: AIService) {
        let limit = settings?[AIKeys.keepAlive] ?? 2
        guard limit > 0 else { return }
        while views.count > limit {
            guard let victim = accessOrder.first(where: { $0 != service && views[$0] != nil }) else { return }
            unload(victim)
        }
    }

    /// Выгрузка: остановить загрузку, снять делегатов и наблюдателей, убрать из кэша. Данные входа остаются в общем хранилище.
    private func unload(_ service: AIService) {
        guard let view = views[service] else { return }
        if typing && typingService == service { setTyping(false) }
        view.stopLoading()
        view.navigationDelegate = nil
        view.uiDelegate = nil
        view.onFocusChange = nil
        view.onDragHover = nil
        urlObservers[service]?.invalidate()
        urlObservers[service] = nil
        view.removeFromSuperview()
        views[service] = nil
        accessOrder.removeAll { $0 == service }
        if service == current {
            isLoading = false
            canGoBack = false
            canGoForward = false
        }
    }

    /// Вкладка показана (вью живёт на экране).
    func setViewShown(_ on: Bool) {
        viewShown = on
        updateIdleTimer()
    }

    /// Таймер выгрузки идёт, пока шторка закрыта или вкладка ИИ не показана.
    func updateIdleTimer() {
        let active = viewShown && notch?.state.phase == .open
        if active {
            idleTask?.cancel()
            idleTask = nil
            return
        }
        guard idleTask == nil, !views.isEmpty else { return }
        let minutes = settings?[AIKeys.unloadMinutes] ?? 10
        guard minutes > 0 else { return }
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled, let self else { return }
            self.idleTask = nil
            self.unloadIdle()
        }
    }

    /// Выгрузить всё, кроме страницы, где недавно (меньше 30 мин назад) печатали.
    private func unloadIdle() {
        var keep: AIService?
        if let service = typingService, let at = lastTypedAt, Date().timeIntervalSince(at) < 30 * 60 {
            keep = service
        }
        for service in Array(views.keys) where service != keep { unload(service) }
    }

    func select(_ service: AIService) {
        guard service != current else { return }
        // Уходим со старой страницы: фокус ввода сбрасываем, пока не кликнут в новую.
        setTyping(false)
        current = service
        let view = views[service]
        canGoBack = view?.canGoBack ?? false
        canGoForward = view?.canGoForward ?? false
        isLoading = view?.isLoading ?? false
        if service == .browser, !addressEditing {
            addressText = view?.url?.absoluteString ?? ""
        }
    }

    func reload() { views[current]?.reload() }
    func goBack() { views[current]?.goBack() }
    func goForward() { views[current]?.goForward() }

    func goHome() {
        views[current]?.load(URLRequest(url: homeURL(for: current)))
    }

    func openInBrowser() {
        NSWorkspace.shared.open(views[current]?.url ?? homeURL(for: current))
    }

    /// Фокус ввода в WebView: держим шторку открытой.
    func setTyping(_ on: Bool) {
        guard on != typing else { return }
        typing = on
        if on { typingService = current }
        lastTypedAt = Date()
        notch?.hold(Self.typingReason, on)
    }

    /// Выйти из аккаунтов: очистить данные сайтов и перезагрузить страницы.
    func signOut() async {
        let store = WKWebsiteDataStore.default()
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        for (service, view) in views { view.load(URLRequest(url: homeURL(for: service))) }
        statusMessage = "Вы вышли из всех аккаунтов: данные сайтов очищены."
    }

    // MARK: - События от делегата

    fileprivate func isCurrent(_ webView: WKWebView) -> Bool {
        views[current] === webView
    }

    fileprivate func sync(_ webView: WKWebView, loading: Bool? = nil) {
        guard isCurrent(webView) else { return }
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        if let loading { isLoading = loading }
        if current == .browser, !addressEditing {
            let text = webView.url?.absoluteString ?? ""
            if text != addressText { addressText = text }
        }
    }
}

/// Делегат навигации и окон: у AI-сервисов внешние домены уходят в браузер, во вкладке «Браузер» всё открывается внутри.
@MainActor
final class AIWebDelegate: NSObject, WKUIDelegate, WKNavigationDelegate {
    weak var model: AIModel?

    /// Окна входа, общие для всех AI-сервисов.
    private static let commonHosts = [
        "appleid.apple.com", "login.microsoftonline.com", "challenges.cloudflare.com",
        "accounts.google.com",
    ]

    private func service(of webView: WKWebView) -> AIService? {
        (webView as? FocusWebView)?.service
    }

    private func isInApp(_ url: URL, for service: AIService?) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if service == .browser { return true }
        let hosts = (service?.ownHosts ?? []) + Self.commonHosts
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private func isExternal(_ url: URL, for service: AIService?) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return false }
        return !isInApp(url, for: service)
    }

    // MARK: WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // target=_blank и window.open: в «Браузере» и для своих доменов грузим в текущем окне.
        if let url = navigationAction.request.url, isExternal(url, for: service(of: webView)) {
            NSWorkspace.shared.open(url)
        } else {
            webView.load(navigationAction.request)
        }
        return nil
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Файл, брошенный на окно, не должен заменить переписку.
        if let url = navigationAction.request.url, url.isFileURL {
            decisionHandler(.cancel)
            return
        }
        // Ссылка на чужой сайт открывается в браузере (кроме вкладки «Браузер»).
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url, isExternal(url, for: service(of: webView)) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        model?.sync(webView, loading: true)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        model?.sync(webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        model?.sync(webView, loading: false)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        model?.sync(webView, loading: false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        model?.sync(webView, loading: false)
    }
}
