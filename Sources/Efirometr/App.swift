import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            Migration.run() // before anything reads settings or data files
            let monitor = WiFiMonitor.shared
            let settings = AppSettings.shared
            _ = Journal.shared
            // --demo: fictional networks for screenshots, nothing is scanned or saved.
            let demo = CommandLine.arguments.contains("--demo")
            if demo {
                monitor.loadDemo()
                SpeedTester.shared.loadDemo()
                Journal.shared.loadDemo()
                SurveyStore.shared.loadDemo()
                AppTrafficMonitor.shared.loadDemo()
            } else {
                monitor.start()
                Notifier.shared.requestAuthorization()
            }
            statusItem = StatusItemController(monitor: monitor, settings: settings)

            if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
                Snapshot.schedule(to: URL(fileURLWithPath: CommandLine.arguments[i + 1]), demo: demo)
                return
            }
            if settings.showWindowOnLaunch {
                MainWindowController.shared.show()
            } else {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    // The menu bar indicator keeps working after the main window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated { MainWindowController.shared.show() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { Journal.shared.save() }
    }
}

extension WiFiMonitor {
    static let shared = WiFiMonitor()
}

@main
struct EfirometrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(AppSettings.shared)
                .environmentObject(WiFiMonitor.shared)
                .environmentObject(LiveData.shared)
                .frame(width: 720, height: 640)
                .background(AppBackground())
                .preferredColorScheme(.dark)
        }
    }
}

enum Section: String, CaseIterable, Identifiable {
    case overview = "Обзор"
    case advice = "Советы"
    case monitor = "Монитор"
    case channels = "Каналы"
    case networks = "Сети"
    case speed = "Тест скорости"
    case journal = "Журнал"
    case survey = "Карта квартиры"
    case apps = "Приложения"
    case device = "Устройство"
    case settings = "Настройки"
    case donate = "Поддержать"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.67percent"
        case .advice: return "lightbulb"
        case .monitor: return "waveform.path.ecg"
        case .channels: return "chart.xyaxis.line"
        case .networks: return "wifi"
        case .speed: return "speedometer"
        case .journal: return "clock.arrow.circlepath"
        case .survey: return "map"
        case .apps: return "app.badge"
        case .device: return "laptopcomputer"
        case .settings: return "gearshape"
        case .donate: return "heart.fill"
        }
    }

    static let groups: [(String, [Section])] = [
        ("Сеть", [.overview, .advice, .monitor, .channels, .networks]),
        ("Инструменты", [.speed, .journal, .survey, .apps]),
        ("Mac", [.device, .settings]),
        ("Проект", [.donate]),
    ]
}

struct ContentView: View {
    @EnvironmentObject var nav: NavigationModel

    var body: some View {
        NavigationSplitView {
            // Custom sidebar: plain taps instead of List selection, which ignored clicks in this hosting setup.
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Section.groups, id: \.0) { title, items in
                        Text(title.uppercased())
                            .font(.system(size: 10.5, weight: .semibold)).tracking(1)
                            .foregroundStyle(Theme.text3)
                            .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 4)
                        ForEach(items) { s in
                            SidebarRow(section: s, selected: (nav.section ?? .overview) == s)
                                .onTapGesture { nav.section = s }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 8)
            }
            .scrollIndicators(.never)
            .navigationSplitViewColumnWidth(min: 210, ideal: 230)
            .safeAreaInset(edge: .bottom) { SidebarFooter() }
        } detail: {
            Group {
                switch nav.section ?? .overview {
                case .overview: OverviewView()
                case .advice: AdviceView()
                case .monitor: MonitorView()
                case .channels: ChannelsView()
                case .networks: NetworksView()
                case .speed: SpeedTestView()
                case .journal: JournalView()
                case .survey: SurveyView()
                case .apps: AppTrafficView()
                case .device: DeviceView()
                case .settings: SettingsView()
                case .donate: DonateView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppBackground())
            .toolbarBackground(Theme.bg, for: .windowToolbar)
        }
    }
}

struct SidebarRow: View {
    let section: Section
    var selected = false
    @EnvironmentObject var monitor: WiFiMonitor
    @EnvironmentObject var journal: Journal
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: section.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? Color.white : Theme.accent.opacity(0.9))
                .frame(width: 20)
            Text(section.rawValue)
                .font(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Color.white : Theme.text)
            Spacer(minLength: 4)
            if badge > 0 {
                Text("\(badge)")
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(selected ? Color.white : Theme.text2)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background((selected ? Color.white : Theme.text3).opacity(0.18), in: Capsule())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.accentGradient.opacity(0.85))
            } else if hover {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.06))
            }
        }
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }

    private var badge: Int {
        switch section {
        case .networks: return monitor.groups.count
        case .advice: return monitor.assessment.recommendations.filter { $0.severity <= .warning }.count
        case .journal:
            let hour = Date().addingTimeInterval(-3600)
            return journal.events.filter { $0.t >= hour && $0.kind.isProblem }.count
        default: return 0
        }
    }
}

struct SidebarFooter: View {
    @EnvironmentObject var monitor: WiFiMonitor
    @EnvironmentObject var live: LiveData

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                ScoreRing(score: monitor.assessment.score, size: 38, lineWidth: 4, showCaption: false)
                VStack(alignment: .leading, spacing: 1) {
                    Text(monitor.assessment.grade).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.score(Double(monitor.assessment.score) / 100))
                    Text(monitor.link?.ssid ?? "Wi‑Fi").font(.system(size: 11)).foregroundStyle(Theme.text3).lineLimit(1)
                }
            }
            HStack(spacing: 10) {
                Text("↓ \(Format.speed(live.downRate))").foregroundStyle(Theme.cyan)
                Text("↑ \(Format.speed(live.upRate))").foregroundStyle(Theme.pink)
            }
            .font(Theme.number(11, .medium))
            if !monitor.locationAuthorized {
                Button("Показать имена сетей…") { monitor.openLocationSettings() }
                    .buttonStyle(.link).font(.caption)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 14, fill: Color.white.opacity(0.03))
        .padding(10)
    }
}

struct MenuBarPanel: View {
    @EnvironmentObject var monitor: WiFiMonitor
    @EnvironmentObject var live: LiveData
    @EnvironmentObject var tester: SpeedTester

    var body: some View {
        let l = live.link
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ScoreRing(score: monitor.assessment.score, size: 56, lineWidth: 6, showCaption: false)
                VStack(alignment: .leading, spacing: 2) {
                    Text(l?.ssid ?? (l?.isConnected == true ? "Wi‑Fi" : "Не подключено")).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text(monitor.assessment.grade).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Palette.score(Double(monitor.assessment.score) / 100))
                    if let l, l.isConnected, let ch = l.channel {
                        Text("\(ch.band.rawValue) · канал \(ch.number) · \(ch.width) МГц").font(.system(size: 11)).foregroundStyle(Theme.text3)
                    }
                }
                Spacer()
            }

            HStack(spacing: 10) {
                speedTile("Входящий", live.downRate, "arrow.down", Theme.cyan)
                speedTile("Исходящий", live.upRate, "arrow.up", Theme.pink)
            }

            LiveThroughputChart(showLabels: false)
            .frame(height: 70)

            if let l, l.isConnected {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow { Text("Сигнал").foregroundStyle(Theme.text3); Text("\(l.rssi) dBm · SNR \(l.snr) dB").foregroundStyle(Theme.text) }
                    GridRow { Text("Канал").foregroundStyle(Theme.text3); Text(String(format: "%.0f Мбит/с · %@", l.txRate, PHY.label(l.phy))).foregroundStyle(Theme.text) }
                    if let r = tester.last {
                        GridRow {
                            Text("Интернет").foregroundStyle(Theme.text3)
                            Text(String(format: "↓ %.0f / ↑ %.0f Мбит/с · %@", r.down / 1e6, r.up / 1e6, r.date.formatted(date: .omitted, time: .shortened))).foregroundStyle(Theme.text)
                        }
                    }
                }
                .font(.system(size: 11.5))
            }

            HStack(spacing: 8) {
                Button {
                    tester.run(monitor: monitor)
                } label: {
                    Label(tester.running ? "Тест… \(Int(tester.progress * 100))%" : "Тест скорости", systemImage: "speedometer")
                }
                .buttonStyle(.premiumSecondary)
                .disabled(tester.running)
                Button { monitor.scan() } label: { Label("Скан", systemImage: "dot.radiowaves.left.and.right") }
                    .buttonStyle(.premiumSecondary)
                    .disabled(monitor.isScanning)
            }

            if let top = monitor.assessment.recommendations.first(where: { $0.severity <= .tip }) {
                Label(top.title, systemImage: top.icon).font(.system(size: 11.5, weight: .medium)).foregroundStyle(top.severity.color).lineLimit(2)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(top.severity.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .contentShape(Rectangle())
                    .onTapGesture { MainWindowController.shared.show(section: .overview) }
                    .help("Открыть рекомендации")
            }

            Divider().overlay(Theme.stroke)
            HStack {
                Button("Открыть \(AppInfo.name)") { MainWindowController.shared.show() }
                    .buttonStyle(.premium)
                Spacer()
                Button { MainWindowController.shared.show(section: .settings) } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.premiumSecondary)
                    .help("Настройки")
                Button("Выйти") { NSApp.terminate(nil) }.buttonStyle(.premiumSecondary)
            }
        }
        .padding(16)
        .frame(width: 340)
        .background(AppBackground())
    }

    private func speedTile(_ title: String, _ rate: Double, _ icon: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: icon).font(.system(size: 11, weight: .medium)).foregroundStyle(tint)
            Text(Format.speed(rate)).font(Theme.number(18)).foregroundStyle(Theme.text)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 12, fill: tint.opacity(0.08))
    }
}
