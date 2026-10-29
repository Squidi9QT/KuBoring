# KuBoring — архитектура и контракты (ИСТОЧНИК ПРАВДЫ для всех, кто пишет код)

Нативное macOS-приложение-нотч. Swift (toolchain 6, language mode 5), SwiftUI + AppKit, macOS 14+.
Пишется С НУЛЯ. Boring Notch можно смотреть только чтобы понять ПОВЕДЕНИЕ
и какие системные API нужны. Копировать его код (даже куски, даже с переименованием) ЗАПРЕЩЕНО — лицензия GPL.
Код прежних вкладок пользователя (вкладки ИИ, Таймер, Буфер) — авторский код пользователя, его логику переносить можно.
Весь интерфейс на русском. Приложение без sandbox (личное), hardened runtime выключен.

## Структура
```
KuBoring/
  project.yml                 XcodeGen (генерирует KuBoring.xcodeproj)
  setup.command               двойной клик: ставит xcodegen (brew), генерирует проект, открывает Xcode
  App/                        таргет приложения
    KuBoringApp.swift         @main, NSApplicationDelegate-адаптер, LSUIElement
    Composition.swift         ТОЧКА СБОРКИ: создаёт SettingsStore/NotchController/ActivityCenter/FeatureRegistry и регистрирует фичи
    Info.plist, KuBoring.entitlements
    Resources/mediaremote-adapter.pl   (BSD-3, из boringKub/mediaremote-adapter)
    Vendor/MediaRemoteAdapter.framework (BSD-3, встраивается в Contents/Frameworks)
  Packages/KuBoringKit/       Swift Package, один продукт KuBoringKit, модули:
    Sources/KuBoringCore/     каркас (никаких знаний о конкретных фичах!)
    Sources/FeatureMusic/  FeatureShelf/  FeatureClipboard/  FeatureTimer/  FeatureAI/
    Sources/FeatureScreenText/  FeatureSystem/  FeatureCalendar/  FeatureCamera/
    Tests/KuBoringCoreTests/
  LICENSE (MIT, Kurban Idrisov), THIRD_PARTY_LICENSES (MediaRemoteAdapter BSD-3), README.md
```
Правило зависимостей: Feature* зависят ТОЛЬКО от KuBoringCore (и системных фреймворков). Фичи не импортируют друг друга.
Всё, что фича отдаёт наружу, — `public`. Всё UI-состояние — `@MainActor`. Для наблюдаемых объектов — `@Observable` (Observation), НЕ ObservableObject.
Никаких глобальных синглтонов `.shared` в своём коде. Зависимости приходят через FeatureContext.
Никаких `DispatchQueue.main.asyncAfter` для логики состояния — только Task + Task.sleep, с отменой.
Никакого NotificationCenter для связи частей приложения (системные уведомления AppKit слушать можно).

## Контракты KuBoringCore (реализовать ТОЧНО с этими сигнатурами)

```swift
import SwiftUI

// ---------- Настройки ----------
/// Ключ настройки с типом и значением по умолчанию. Хранится в UserDefaults (JSON для Codable).
public struct SettingKey<Value: Codable & Sendable>: Sendable {
    public let name: String
    public let defaultValue: Value
    public init(_ name: String, default defaultValue: Value)
}

@MainActor @Observable
public final class SettingsStore {
    public init(defaults: UserDefaults = .standard)
    public subscript<V>(_ key: SettingKey<V>) -> V { get set }   // чтение/запись, изменения наблюдаемы SwiftUI
    public func binding<V>(_ key: SettingKey<V>) -> Binding<V>
    public func reset<V>(_ key: SettingKey<V>)
    public func reset(prefix: String)                              // сброс раздела, напр. "feature.timer."
}
/// Ключ включённости фичи: "feature.<id>.enabled"
public func featureEnabledKey(_ id: String, default on: Bool = true) -> SettingKey<Bool>

// ---------- Геометрия шторки (редактируется в настройках, с живым превью) ----------
public struct NotchGeometry: Codable, Sendable, Equatable {
    public var openWidth: Double        // 640 (400...900)
    public var openHeight: Double       // 190 (120...600)
    public var closedWidthAuto: Bool    // true = ширина реального выреза
    public var closedWidth: Double      // 185, если не авто
    public var closedHeightAuto: Bool   // true = высота реального выреза/меню-бара
    public var closedHeight: Double     // 32
    public var cornerRadius: Double     // 24 (открытая шторка)
    public var hoverPaddingX: Double    // 20 — насколько шире выреза зона, где курсор открывает шторку
    public var hoverPaddingY: Double    // 8  — насколько ниже
    public var openDelay: Double        // 0.15 с — задержка открытия при наведении
    public var closeDelay: Double       // 0.3 с — задержка закрытия после ухода курсора
    public var animationSpeed: Double   // 1.0 (0.5...2.0)
    public var openOnHover: Bool        // true; false = открывать только кликом
    public static let `default`: NotchGeometry
}
public enum CoreKeys {
    public static let geometry: SettingKey<NotchGeometry>          // "core.geometry"
    public static let tabOrder: SettingKey<[String]>               // "core.tabOrder" (id фич)
    public static let rememberLastTab: SettingKey<Bool>            // "core.rememberLastTab" true
    public static let lastTab: SettingKey<String>                  // "core.lastTab"
    public static let launchAtLogin: SettingKey<Bool>              // "core.launchAtLogin" (SMAppService)
    public static let showOnAllScreens: SettingKey<Bool>           // "core.allScreens" false
    public static let hideInFullscreen: SettingKey<Bool>           // "core.hideInFullscreen" false
}

// ---------- Машина состояний шторки ----------
public enum NotchPhase: Equatable, Sendable { case closed, peeking, open, dragging }
// peeking = курсор в зоне, ждём openDelay; dragging = над шторкой тащат файл

public enum NotchEvent: Equatable, Sendable {
    case pointerEntered, pointerExited
    case openDelayElapsed, closeDelayElapsed
    case clicked, clickedOutside
    case dragEntered, dragExited, dropped
    case requestOpen(tab: String?)       // фича просит открыть (таймер закончился)
    case requestClose
    case selectTab(String)
}

public struct NotchState: Equatable, Sendable {
    public var phase: NotchPhase
    public var selectedTab: String?
    public var holdOpen: Set<String>     // причины не закрываться (напр. "ai.typing"); пока не пусто — уход курсора не закрывает
    public var openedByDrag: Bool
}

public enum NotchEffect: Equatable, Sendable { case scheduleOpen, scheduleClose, cancelTimers }

/// ЧИСТАЯ функция переходов (покрыть тестами). Правила:
/// closed+pointerEntered -> peeking (+scheduleOpen), если openOnHover; peeking+openDelayElapsed -> open; peeking+pointerExited -> closed
/// open+pointerExited -> scheduleClose, если holdOpen пуст; closeDelayElapsed -> closed; pointerEntered при ожидании -> cancelTimers
/// clicked: closed/peeking -> open; clickedOutside: open -> closed (даже если holdOpen не пуст)
/// dragEntered: closed -> dragging (вкладка = dropTab, openedByDrag=true); open -> остаётся open, ВКЛАДКА НЕ МЕНЯЕТСЯ
/// dragExited: dragging -> closed; dropped: dragging -> open (на dropTab)
/// requestOpen(tab) -> open (+selectedTab если задан); requestClose -> closed; selectTab -> selectedTab
public enum NotchReducer {
    public static func reduce(_ state: inout NotchState, _ event: NotchEvent,
                              openOnHover: Bool, dropTab: String?) -> [NotchEffect]
}

@MainActor @Observable
public final class NotchController {
    public private(set) var state: NotchState
    public init(settings: SettingsStore)
    public func send(_ event: NotchEvent)                 // reduce + исполняет эффекты через Task.sleep(openDelay/closeDelay)
    public func hold(_ reason: String, _ on: Bool)        // добавить/убрать причину holdOpen
    public var dropTabID: String?                         // какая вкладка принимает файлы (ставит Shelf)
}

// ---------- Живые активности в закрытой шторке ----------
public struct LiveActivity: Identifiable {
    public let id: String
    public var priority: Int             // больше = важнее. Ориентиры: HUD 100, таймер 80, зарядка 70, музыка 50
    public var expiresAt: Date?          // nil = пока не уберут (музыка), иначе всплывашка (HUD 1.5 c)
    public var leading: AnyView          // слева от выреза
    public var trailing: AnyView         // справа от выреза
    public var extraWidth: Double        // сколько добавить к ширине закрытой шторки (каждая сторона)
    public init(id: String, priority: Int, expiresAt: Date? = nil, extraWidth: Double = 40,
                leading: AnyView, trailing: AnyView)
}

@MainActor @Observable
public final class ActivityCenter {
    public init()
    public func post(_ activity: LiveActivity)   // заменяет по id
    public func remove(id: String)
    public var current: LiveActivity? { get }     // самая приоритетная не истёкшая; истёкшие убираются сами
}

// ---------- Фичи ----------
public enum FeatureKind: Sendable { case tab, background }   // background — без вкладки (HUD, батарея, не спать)

@MainActor
public struct FeatureContext {
    public let settings: SettingsStore
    public let notch: NotchController
    public let activities: ActivityCenter
    public init(settings: SettingsStore, notch: NotchController, activities: ActivityCenter)
}

@MainActor
public protocol NotchFeature: AnyObject {
    var id: String { get }               // "music", "shelf", "clipboard", "timer", "ai", "screentext", "system", "calendar", "camera"
    var title: String { get }            // "Музыка"
    var symbol: String { get }           // SF Symbol
    var summary: String { get }          // одна строка для списка фич в настройках: что делает
    var kind: FeatureKind { get }
    var enabledByDefault: Bool { get }
    func start(_ context: FeatureContext)   // вызывается при включении
    func stop()                              // при выключении: освободить ресурсы, убрать активности
    func makeTabView() -> AnyView?           // nil для background
    func makeSettingsView() -> AnyView?      // свой раздел настроек (используй SettingsUI-компоненты ниже)
}

@MainActor @Observable
public final class FeatureRegistry {
    public init(context: FeatureContext)
    public func register(_ feature: NotchFeature)
    public var all: [NotchFeature] { get }
    public var enabledTabs: [NotchFeature] { get }      // в порядке CoreKeys.tabOrder
    public func setEnabled(_ id: String, _ on: Bool)    // пишет настройку, вызывает start/stop
    public func startEnabled()
}

// ---------- Компоненты дружелюбных настроек (единый стиль всех разделов) ----------
public struct SettingsSection<Content: View>: View { public init(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) }
public struct SettingsToggle: View { public init(_ title: String, hint: String? = nil, isOn: Binding<Bool>) }
public struct SettingsSlider: View { public init(_ title: String, hint: String? = nil, value: Binding<Double>, in range: ClosedRange<Double>, step: Double = 1, unit: String = "") } // показывает значение
public struct SettingsPicker<T: Hashable>: View { public init(_ title: String, hint: String? = nil, selection: Binding<T>, options: [(T, String)]) }
public struct SettingsResetButton: View { public init(_ title: String = "Сбросить раздел", action: @escaping () -> Void) }

// ---------- Окно и вьюхи каркаса (реализует Core, фичи не трогают) ----------
// NotchWindowController: NSPanel без рамки, level .statusBar+, canJoinAllSpaces + fullScreenAuxiliary + stationary,
//   не активирует приложение; окно по размеру открытой шторки, вверху по центру экрана; ignoresMouseEvents вне формы шторки.
//   Отслеживание курсора по зоне hover (вырез + hoverPaddingX/Y) через глобальный+локальный NSEvent monitor mouseMoved -> pointerEntered/Exited.
//   Клик вне шторки -> clickedOutside. Drag файлов -> dragEntered/dragExited/dropped (+ передать URL в Shelf через NotchDropHandler).
// NotchRootView: форма шторки (своя Shape), закрытое состояние = ActivityCenter.current, открытое = панель вкладок + makeTabView выбранной.
// SettingsWindow: боковое меню: «Общие», «Шторка» (геометрия + ЖИВОЕ ПРЕВЬЮ формы), «Вкладки и функции» (список всех фич:
//   иконка, название, summary, переключатель, перетаскивание порядка), затем по пункту на каждую включённую фичу с makeSettingsView, «О программе».
//   У каждого раздела кнопка «Сбросить раздел». Подсказки серым текстом под настройками. Поиск по настройкам — по названиям.
// Меню в строке меню (NSStatusItem): «Настройки…», «Выйти».

/// Фича, принимающая файлы, регистрирует обработчик.
@MainActor public protocol NotchDropHandler: AnyObject { func handleDrop(_ urls: [URL]) }
// NotchController.dropHandler: NotchDropHandler? (weak) — добавить в NotchController.
```

## Фичи (id — модуль — что делает)
- music — FeatureMusic: сейчас играет (любой плеер) через MediaRemoteAdapter: `/usr/bin/perl <Resources>/mediaremote-adapter.pl <Frameworks>/MediaRemoteAdapter.framework stream`, JSON построчно; команды play/pause/next/prev/seek через тот же скрипт (`send <cmd>`). Вкладка: обложка, название, исполнитель, прогресс, кнопки. Активность в закрытой шторке: мини-обложка слева, эквалайзер-полоски справа. Настройки: показывать активность, анимация полосок.
- shelf — FeatureShelf: полка файлов (drag&drop в шторку), хранит закладки на файлы (bookmark), миниатюры QuickLook, перетащить обратно, открыть, удалить, AirDrop (NSSharingService). Является dropHandler. Настройки: макс. файлов, очищать при выходе.
- clipboard — FeatureClipboard: порт KubClipboard (последние N текстов, поиск, клик копирует, пропускать org.nspasteboard.ConcealedType). Настройки: N, хранить между запусками (выкл по умолч.).
- timer — FeatureTimer: порт KubTimer (пресеты, ±1 мин, звук, по окончании requestOpen(tab:"timer")). Активность: отсчёт справа, priority 80. Настройки: пресеты, звук.
- ai — FeatureAI: порт KubAI (Claude claude.ai/new + Perplexity в WKWebView, вход сохраняется, внешние ссылки в браузер, кнопка назад). WebView создаётся лениво при первом открытии вкладки. Пока в WebView фокус ввода — hold("ai.typing"). Настройки: какие сервисы показывать, сервис по умолчанию, размер окна вкладки.
- screentext — FeatureScreenText: выделить область экрана -> распознать текст (Vision, ru+en) -> скопировать. Заготовка-протокол `LocalAIProvider` под будущую локальную ИИ. Выключена по умолчанию.
- system — FeatureSystem (background): HUD громкости (CoreAudio, слушать изменение) и яркости (DisplayServices через dlopen; режим выбирается автоматически, см. «Энергопотребление»), зарядка/батарея (IOKit power sources: подключили зарядку -> всплывашка), «не спать» (IOPMAssertion, переключатель в меню/настройках). Каждая подфункция отдельным тумблером. Выключено по умолчанию.
- calendar — FeatureCalendar: события на сегодня/завтра (EventKit, запрос доступа по кнопке). Выключено по умолчанию.
- camera — FeatureCamera: зеркало с камеры (AVCaptureSession, стартует только при открытой вкладке). Выключено по умолчанию.
- indicators — FeatureIndicators (background): заряд Bluetooth-наушников при подключении (событие смены устройства вывода CoreAudio + `system_profiler SPBluetoothDataType -json`), камера/микрофон заняты (CoreMediaIO/CoreAudio DeviceIsRunningSomewhere, только события), прогресс загрузок браузеров (DispatchSource на «Загрузки», опрос 1 с только пока что-то качается; выключено по умолчанию), анимация подключения зарядки (IOPS-уведомление). Включено по умолчанию.

## Дополнения (2026-10)
- Ядро: `NotchController.requestKeyboardFocus()` — фича просит сделать панель key (горячая клавиша буфера, переименование на полке).
  `BatteryMonitor` и `QuickControls` создаёт `NotchWindowManager` (по одному на приложение) и передаёт в окна; клик по проценту батареи в шапке — панель аккумулятора с режимом энергосбережения (pmset; разовое правило sudoers `/etc/sudoers.d/kuboring-lowpower` только для `pmset -b|-c lowpowermode 0|1`) и быстрыми переключателями.
  Жесты трекпада (локальный монитор scrollWheel своего окна): по шапке влево/вправо — вкладки, вверх — закрыть; вниз по закрытой шторке — открыть.
  `OnboardingWindowController` — приветствие при первом запуске (`CoreKeys.onboardingShown`) и из меню строки меню.
- music: текст песен с lrclib.net (`Lyrics.swift`), перемотка Music/Spotify через AppleScript `player position` (MRMediaRemoteSetElapsedTime на macOS 26 не работает).
- clipboard: картинки (только в памяти), закрепление, ⌘⇧V (Carbon RegisterEventHotKey, выключено по умолчанию), вставка через CGEvent ⌘V при «Универсальном доступе».
- calendar: ссылка на созвон в событии (`MeetingLink`), отсчёт в закрытой шторке (Task спит до «за N минут»), кнопка «Войти».
- shelf: `ShelfActions` — сжать, в JPG, ZIP, переименовать.
- timer: режим «помидор», кольцо прогресса в закрытой шторке.
- Тесты фич: `Tests/FeatureTests`.

## Дополнения к контрактам
- В `NotchFeature` есть `var preferredOpenSize: CGSize? { get }` с реализацией по умолчанию `nil` (в `extension NotchFeature`).
  Если не nil — пока открыта эта вкладка, шторка принимает этот размер (ИИ: 760×580). Иначе geometry.openWidth/openHeight.
  Также по умолчанию в extension: `summary` = "", `enabledByDefault` = true, `makeSettingsView()` = nil.
- `NotchController` содержит `public weak var dropHandler: NotchDropHandler?`.
- Звук/иконки — только системные (NSSound, SF Symbols). Чужих логотипов не использовать.
- Каждый модуль фичи экспортирует один публичный класс `<Name>Feature: NotchFeature` с `public init()`
  (MusicFeature, ShelfFeature, ClipboardFeature, TimerFeature, AIFeature, ScreenTextFeature, SystemFeature, CalendarFeature, CameraFeature).
  MusicFeature: `public init(adapterScriptURL: URL?, frameworkURL: URL?)` — пути передаёт App из Bundle.main.
- Строки UI — русские. Комментарии в коде — по-русски, коротко.

## Энергопотребление
Правило: никаких покадровых и частых циклов в простое; опрос — только адаптивный, всё снимается в stop()/shutdown().
- Яркость (FeatureSystem/SystemModel): 1) событие `DisplayServicesRegisterForBrightnessChangeNotifications` (dlsym, колбэк = C-функция, observer = unretained модель; страховочный опрос раз в 10 с);
  2) если символа нет — глобальный монитор клавиш яркости (systemDefined, subtype 8, keyCode 2/3): опрос 0.1 с в течение 2 с после нажатия, иначе раз в 2 с;
  3) иначе опрос раз в 1 с. Текущий режим показывается в настройках под тумблером.
- Эквалайзер (FeatureMusic/MusicViews): у каждой полоски своя `repeatForever`-анимация scaleEffect, без TimelineView. Стоит, когда пауза, выключена «Анимировать полоски», экран спит (NSWorkspace.screensDidSleep/Wake) или приложение перекрыто (NSApplication.didChangeOcclusionState). Прогресс-бар: TimelineView `.periodic` 0.5 с, только пока трек играет и экран виден.
- Буфер обмена (FeatureClipboard): один Task; changeCount раз в 0.5 с при активном пользователе (ввод < 60 с назад), иначе раз в 2.5 с; мгновенная проверка на didActivateApplication; настройки кэшируются (обновление раз в 3 с и при новой записи).
- Мышь (KuBoringCore/NotchWindowController.updatePointer): ранний выход, если шторка закрыта, курсор ниже верха экрана более чем на 150 pt (или по X дальше 300 pt от экрана), не внутри и нет перетаскивания; shapeRect/hoverZone считаются один раз за проход.
- ИИ (FeatureAI/AIModel): LRU веб-вью («Держать в памяти»: 1/2/3/все, по умолч. 2) и таймер выгрузки после закрытия шторки или ухода с вкладки (0/5/10/30 мин, по умолч. 10; страница, где печатали <30 мин назад, остаётся). Выгрузка = stopLoading, снять делегаты/KVO, removeFromSuperview, убрать из кэша; данные входа в общем websiteDataStore.
