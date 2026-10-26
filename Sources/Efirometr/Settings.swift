import SwiftUI
import ServiceManagement
import IOKit.ps

enum MenuBarMode: String, CaseIterable, Identifiable {
    case speedSignal, speed, score, icon

    var id: String { rawValue }

    var title: String {
        switch self {
        case .speedSignal: return "Иконка + скорость"
        case .speed: return "Только скорость"
        case .score: return "Иконка + оценка"
        case .icon: return "Только иконка"
        }
    }

    var width: CGFloat {
        switch self {
        case .speedSignal: return 70
        case .speed: return 50
        case .score: return 46
        case .icon: return 26
        }
    }
}

/// User preferences backed by UserDefaults.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    @Published var menuBarMode: MenuBarMode { didSet { d.set(menuBarMode.rawValue, forKey: "menuBarMode") } }
    @Published var coloredIcon: Bool { didSet { d.set(coloredIcon, forKey: "coloredIcon") } }
    @Published var notifySignal: Bool { didSet { d.set(notifySignal, forKey: "notifySignal") } }
    @Published var notifyBand: Bool { didSet { d.set(notifyBand, forKey: "notifyBand") } }
    @Published var notifyDisconnect: Bool { didSet { d.set(notifyDisconnect, forKey: "notifyDisconnect") } }
    @Published var notifyLoss: Bool { didSet { d.set(notifyLoss, forKey: "notifyLoss") } }
    @Published var signalThreshold: Int { didSet { d.set(signalThreshold, forKey: "signalThreshold") } }
    @Published var showWindowOnLaunch: Bool { didSet { d.set(showWindowOnLaunch, forKey: "showWindowOnLaunch") } }
    @Published var hideDockWhenClosed: Bool { didSet { d.set(hideDockWhenClosed, forKey: "hideDockWhenClosed") } }
    @Published var backgroundPing: Bool { didSet { d.set(backgroundPing, forKey: "backgroundPing") } }
    @Published var journalEnabled: Bool { didSet { d.set(journalEnabled, forKey: "journalEnabled") } }
    @Published var journalOnlyOnPower: Bool { didSet { d.set(journalOnlyOnPower, forKey: "journalOnlyOnPower") } }
    @Published private(set) var onBattery = false
    @Published private(set) var launchAtLogin = false
    @Published private(set) var launchStatus = ""

    private init() {
        d.register(defaults: [
            "menuBarMode": MenuBarMode.speedSignal.rawValue, "coloredIcon": true,
            "notifySignal": true, "notifyBand": true, "notifyDisconnect": true, "notifyLoss": true,
            "signalThreshold": -72, "showWindowOnLaunch": true, "hideDockWhenClosed": true, "backgroundPing": true,
            "journalEnabled": false, "journalOnlyOnPower": true,
        ])
        menuBarMode = MenuBarMode(rawValue: d.string(forKey: "menuBarMode") ?? "") ?? .speedSignal
        coloredIcon = d.bool(forKey: "coloredIcon")
        notifySignal = d.bool(forKey: "notifySignal")
        notifyBand = d.bool(forKey: "notifyBand")
        notifyDisconnect = d.bool(forKey: "notifyDisconnect")
        notifyLoss = d.bool(forKey: "notifyLoss")
        signalThreshold = d.integer(forKey: "signalThreshold")
        showWindowOnLaunch = d.bool(forKey: "showWindowOnLaunch")
        hideDockWhenClosed = d.bool(forKey: "hideDockWhenClosed")
        backgroundPing = d.bool(forKey: "backgroundPing")
        journalEnabled = d.bool(forKey: "journalEnabled")
        journalOnlyOnPower = d.bool(forKey: "journalOnlyOnPower")
        refreshPowerSource()
        refreshLaunchStatus()
    }

    /// Journal records only when enabled, and (optionally) only while on AC power.
    var journalActive: Bool { journalEnabled && !(journalOnlyOnPower && onBattery) }

    func refreshPowerSource() {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let type = IOPSGetProvidingPowerSourceType(info).takeUnretainedValue() as String
        let battery = type == kIOPMBatteryPowerKey
        if battery != onBattery { onBattery = battery }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            launchStatus = "Не удалось: \(error.localizedDescription)"
        }
        refreshLaunchStatus()
    }

    func refreshLaunchStatus() {
        let s = SMAppService.mainApp.status
        launchAtLogin = s == .enabled || s == .requiresApproval
        switch s {
        case .enabled: launchStatus = "Приложение запустится при входе в систему, только в строке меню."
        case .requiresApproval: launchStatus = "Нужно разрешение: Системные настройки → Основные → Объекты входа."
        case .notFound: launchStatus = "Установите приложение в папку «Программы», чтобы включить автозапуск."
        default: launchStatus = "Выключено."
        }
    }
}

// MARK: - Settings UI

struct PremiumToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View { PremiumToggle(configuration: configuration) }
}

private struct PremiumToggle: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            configuration.label
            Spacer(minLength: 12)
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? AnyShapeStyle(Theme.accentGradient) : AnyShapeStyle(Color.white.opacity(0.12)))
                    .frame(width: 38, height: 22)
                Circle().fill(.white).frame(width: 18, height: 18).padding(2).shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            }
            .onTapGesture {
                guard enabled else { return }
                withAnimation(.spring(duration: 0.25)) { configuration.isOn.toggle() }
            }
        }
        .contentShape(Rectangle())
    }
}

extension ToggleStyle where Self == PremiumToggleStyle {
    static var premium: PremiumToggleStyle { PremiumToggleStyle() }
}

struct SettingRow<Trailing: View>: View {
    var title: String
    var detail: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.text)
                if let detail { Text(detail).font(.system(size: 12)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var monitor: WiFiMonitor

    var body: some View {
        SnapshotScroll {
            VStack(spacing: 18) {
                Card("Строка меню", icon: "menubar.rectangle") {
                    HStack(spacing: 12) {
                        ForEach(MenuBarMode.allCases) { m in
                            let on = settings.menuBarMode == m
                            VStack(spacing: 10) {
                                StatusLabel(mode: m, forceDark: true)
                                    .frame(width: m.width, height: 22)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                                Text(m.title).font(.system(size: 11.5, weight: on ? .semibold : .regular)).foregroundStyle(on ? Theme.text : Theme.text2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .glass(radius: 12, fill: on ? Theme.accent.opacity(0.12) : Color.white.opacity(0.02))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(on ? Theme.accent.opacity(0.6) : .clear, lineWidth: 1.5))
                            .contentShape(Rectangle())
                            .onTapGesture { settings.menuBarMode = m }
                        }
                    }
                    Toggle(isOn: $settings.coloredIcon) {
                        SettingRow(title: "Цветная иконка Wi‑Fi", detail: "Зелёная — отличный сигнал, жёлтая — средний, красная — слабый.") { EmptyView() }
                    }
                    .toggleStyle(.premium)
                    tip("Чтобы поставить индикатор рядом со значком Wi‑Fi, зажмите ⌘ и перетащите его мышью в строке меню.")
                }

                Card("Уведомления", icon: "bell.badge") {
                    Toggle(isOn: $settings.notifySignal) {
                        SettingRow(title: "Сигнал ослаб", detail: "Если сигнал дольше 15 секунд ниже \(settings.signalThreshold) dBm.") { EmptyView() }
                    }.toggleStyle(.premium)
                    HStack(spacing: 10) {
                        Text("Порог").font(.system(size: 12)).foregroundStyle(Theme.text3)
                        SegmentedControl(options: [-65, -70, -72, -75, -80], selection: $settings.signalThreshold) { "\($0)" }
                        Text("dBm").font(.system(size: 12)).foregroundStyle(Theme.text3)
                    }
                    Divider().overlay(Theme.stroke)
                    Toggle(isOn: $settings.notifyBand) {
                        SettingRow(title: "Переключение на 2,4 ГГц", detail: "Mac ушёл с 5 ГГц на медленный диапазон.") { EmptyView() }
                    }.toggleStyle(.premium)
                    Toggle(isOn: $settings.notifyDisconnect) {
                        SettingRow(title: "Обрыв Wi‑Fi", detail: "Отключение от сети и восстановление связи.") { EmptyView() }
                    }.toggleStyle(.premium)
                    Toggle(isOn: $settings.notifyLoss) {
                        SettingRow(title: "Роутер не отвечает", detail: settings.journalActive && settings.backgroundPing
                                   ? "Несколько пингов подряд до роутера потеряны."
                                   : "Работает только при включённом журнале с пингом роутера.") { EmptyView() }
                    }.toggleStyle(.premium)
                }

                Card("Запуск", icon: "power") {
                    Toggle(isOn: Binding(get: { settings.launchAtLogin }, set: { settings.setLaunchAtLogin($0) })) {
                        SettingRow(title: "Запускать при входе в систему", detail: settings.launchStatus) { EmptyView() }
                    }.toggleStyle(.premium)
                    Toggle(isOn: $settings.showWindowOnLaunch) {
                        SettingRow(title: "Открывать окно при запуске", detail: "Если выключено, приложение стартует только в строке меню.") { EmptyView() }
                    }.toggleStyle(.premium)
                    Toggle(isOn: $settings.hideDockWhenClosed) {
                        SettingRow(title: "Убирать из Dock, когда окно закрыто", detail: "Индикатор в строке меню продолжит работать.") { EmptyView() }
                    }.toggleStyle(.premium)
                }

                JournalSettingsCard()
            }
            .padding(24)
        }
        .navigationTitle("Настройки")
    }

    private func tip(_ t: String) -> some View { Self.tip(t) }

    static func tip(_ t: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "lightbulb.fill").foregroundStyle(Theme.warn).font(.system(size: 11))
            Text(t).font(.system(size: 12)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct JournalSettingsCard: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Card("Журнал и фоновый мониторинг", icon: "waveform.path.ecg.rectangle") {
            Toggle(isOn: $settings.journalEnabled) {
                SettingRow(title: "Вести журнал", detail: "История сигнала, задержки и обрывов за 24 часа. Запись раз в 10 секунд. По умолчанию выключено, чтобы не тратить батарею.") { EmptyView() }
            }.toggleStyle(.premium)
            Group {
                Toggle(isOn: $settings.journalOnlyOnPower) {
                    SettingRow(title: "Только при питании от сети", detail: "На батарее журнал встаёт на паузу и продолжает запись, когда подключите зарядку.") { EmptyView() }
                }.toggleStyle(.premium)
                Toggle(isOn: $settings.backgroundPing) {
                    SettingRow(title: "Пинговать роутер каждые 5 секунд", detail: "Нужно для графика задержек и уведомлений «Роутер не отвечает». Нагрузка — один пакет в 5 секунд.") { EmptyView() }
                }.toggleStyle(.premium)
            }
            .disabled(!settings.journalEnabled)
            .opacity(settings.journalEnabled ? 1 : 0.4)
            HStack(spacing: 8) {
                Circle().fill(statusColor).frame(width: 7, height: 7).shadow(color: statusColor, radius: 3)
                Text(statusText).font(.system(size: 12)).foregroundStyle(Theme.text2)
            }
            SettingsView.tip("Без журнала приложение всё равно раз в секунду обновляет скорость и сигнал для строки меню. Это лёгкий системный запрос, заметного влияния на батарею он не оказывает.")
        }
    }

    private var statusColor: Color {
        !settings.journalEnabled ? Theme.text3 : settings.journalActive ? Theme.good : Theme.warn
    }

    private var statusText: String {
        if !settings.journalEnabled { return "Журнал выключен" }
        if !settings.journalActive { return "На паузе: Mac работает от батареи" }
        return "Журнал ведётся" + (settings.backgroundPing ? ", роутер пингуется" : "")
    }
}
