import SwiftUI
import Charts
import UserNotifications

struct JournalSample: Codable, Identifiable {
    var id: Date { t }
    let t: Date
    let rssi: Int?
    let noise: Int?
    let rate: Double?
    let ping: Double?
    let lost: Bool
    let down: Double
    let up: Double
}

struct JournalEvent: Codable, Identifiable {
    enum Kind: String, Codable {
        case disconnect, reconnect, roam, bandChange, channelChange, weakSignal, signalRecovered, loss, lossRecovered, speedTest

        var icon: String {
            switch self {
            case .disconnect: return "wifi.slash"
            case .reconnect: return "wifi"
            case .roam: return "arrow.triangle.swap"
            case .bandChange: return "antenna.radiowaves.left.and.right"
            case .channelChange: return "dial.medium"
            case .weakSignal: return "wifi.exclamationmark"
            case .signalRecovered: return "checkmark.circle"
            case .loss: return "exclamationmark.triangle"
            case .lossRecovered: return "checkmark.circle"
            case .speedTest: return "speedometer"
            }
        }

        var color: Color {
            switch self {
            case .disconnect, .loss: return Theme.bad
            case .weakSignal, .bandChange: return Theme.warn
            case .reconnect, .signalRecovered, .lossRecovered: return Theme.good
            case .roam, .channelChange: return Theme.violet
            case .speedTest: return Theme.cyan
            }
        }

        var isProblem: Bool { [.disconnect, .loss, .weakSignal, .bandChange].contains(self) }
    }

    var id = UUID()
    let t: Date
    let kind: Kind
    let text: String
}

/// 24 h rolling history of link quality and notable events, persisted in Application Support.
@MainActor
final class Journal: ObservableObject {
    static let shared = Journal()

    @Published private(set) var samples: [JournalSample] = []
    @Published private(set) var events: [JournalEvent] = []

    private let keep: TimeInterval = 24 * 3600
    private var dirty = false
    private let url = AppInfo.supportDirectory.appendingPathComponent("journal.json")

    private struct Stored: Codable { var samples: [JournalSample]; var events: [JournalEvent] }

    private init() {
        if let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Stored.self, from: data) {
            samples = s.samples
            events = s.events
            prune()
        }
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.save() }
        }
    }

    func add(sample: JournalSample) {
        samples.append(sample)
        dirty = true
        prune()
    }

    func add(_ kind: JournalEvent.Kind, _ text: String) {
        let e = JournalEvent(t: .now, kind: kind, text: text)
        if AppSettings.shared.journalActive {
            events.append(e)
            dirty = true
        }
        Notifier.shared.handle(e)
    }

    func save() {
        guard dirty else { return }
        dirty = false
        try? JSONEncoder().encode(Stored(samples: samples, events: events)).write(to: url, options: .atomic)
    }

    func clear() {
        samples = []
        events = []
        dirty = true
        save()
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-keep)
        if let i = samples.firstIndex(where: { $0.t >= cutoff }), i > 0 { samples.removeFirst(i) }
        if let i = events.firstIndex(where: { $0.t >= cutoff }), i > 0 { events.removeFirst(i) }
    }
}

// MARK: - Notifications

@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    private var lastSent: [JournalEvent.Kind: Date] = [:]
    private let cooldown: TimeInterval = 180

    func requestAuthorization() {
        let c = UNUserNotificationCenter.current()
        c.delegate = self
        c.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func handle(_ e: JournalEvent) {
        let s = AppSettings.shared
        let enabled: Bool
        let title: String
        switch e.kind {
        case .weakSignal: enabled = s.notifySignal; title = "Сигнал Wi‑Fi ослаб"
        case .bandChange: enabled = s.notifyBand && e.text.hasSuffix("2,4 ГГц"); title = "Mac переключился на 2,4 ГГц"
        case .disconnect: enabled = s.notifyDisconnect; title = "Wi‑Fi отключился"
        case .reconnect: enabled = s.notifyDisconnect && lastSent[.disconnect] != nil; title = "Wi‑Fi снова на связи"
        case .loss: enabled = s.notifyLoss; title = "Роутер не отвечает"
        default: enabled = false; title = ""
        }
        guard enabled else { return }
        if let last = lastSent[e.kind], Date().timeIntervalSince(last) < cooldown { return }
        lastSent[e.kind] = .now

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = e.text
        content.sound = e.kind.isProblem ? .default : nil
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: e.id.uuidString, content: content, trigger: nil))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { MainWindowController.shared.show(section: .journal) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

// MARK: - View

struct JournalView: View {
    @EnvironmentObject var journal: Journal
    @EnvironmentObject var settings: AppSettings
    @State private var hours = 1

    private var cutoff: Date { Date().addingTimeInterval(-Double(hours) * 3600) }
    private var samples: [JournalSample] { journal.samples.filter { $0.t >= cutoff } }
    private var events: [JournalEvent] { journal.events.filter { $0.t >= cutoff } }

    var body: some View {
        SnapshotScroll {
            VStack(spacing: 18) {
                if !settings.journalActive { stateBanner }
                HStack {
                    SegmentedControl(options: [1, 6, 24], selection: $hours) { "\($0) ч" }
                    Spacer()
                    summary
                }
                Card("Сигнал", icon: "wifi", hint: Hint(title: "История сигнала", body: "Запись каждые 10 секунд, хранится 24 часа. Провалы ниже оранжевой линии означают, что связь в этот момент могла тормозить.")) {
                    if samples.count < 3 { empty } else { signalChart }
                }
                Card("Задержка до роутера", icon: "timer", hint: Hint(title: "Задержка и потери", body: "Фоновый пинг роутера каждые 5 секунд. Красные отметки — моменты, когда роутер не ответил. Именно они чувствуются как «зависания» звонков.")) {
                    if samples.filter({ $0.ping != nil || $0.lost }).count < 3 { empty } else { pingChart }
                }
                Card("События", icon: "list.bullet.rectangle",
                     trailing: AnyView(Button("Очистить журнал") { journal.clear() }.buttonStyle(.premiumSecondary))) {
                    if events.isEmpty {
                        Text("За выбранный период событий нет — связь была стабильной.").font(.system(size: 13)).foregroundStyle(Theme.text2)
                    }
                    ForEach(events.reversed()) { e in
                        HStack(spacing: 12) {
                            Image(systemName: e.kind.icon).font(.system(size: 12, weight: .semibold)).foregroundStyle(e.kind.color)
                                .frame(width: 28, height: 28).background(e.kind.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
                            Text(e.text).font(.system(size: 13)).foregroundStyle(Theme.text)
                            Spacer()
                            Text(e.t.formatted(date: .omitted, time: .standard)).font(.system(size: 12).monospacedDigit()).foregroundStyle(Theme.text3)
                        }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Журнал")
    }

    private var stateBanner: some View {
        let paused = settings.journalEnabled
        return HStack(alignment: .center, spacing: 16) {
            Image(systemName: paused ? "battery.75percent" : "pause.circle")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(paused ? Theme.warn : Theme.accent)
                .frame(width: 48, height: 48)
                .background((paused ? Theme.warn : Theme.accent).opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(paused ? "Журнал на паузе — Mac работает от батареи" : "Журнал выключен")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                Text(paused
                     ? "Запись продолжится автоматически, когда подключите зарядку. Это можно изменить в настройках."
                     : "Включите, чтобы записывать сигнал, задержку и обрывы за последние 24 часа. Удобно, если связь «иногда лагает» и нужно понять когда.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if paused {
                Button("Писать и на батарее") { settings.journalOnlyOnPower = false }.buttonStyle(.premiumSecondary)
            } else {
                Button { settings.journalEnabled = true } label: { Label("Включить журнал", systemImage: "record.circle") }.buttonStyle(.premium)
            }
        }
        .padding(20)
        .glass(radius: 18, fill: Color.white.opacity(0.04))
    }

    private var summary: some View {
        let problems = events.filter { $0.kind.isProblem }.count
        let lost = samples.filter(\.lost).count
        let pings = samples.compactMap(\.ping).sorted()
        let median = pings.isEmpty ? nil : pings[pings.count / 2]
        return HStack(spacing: 10) {
            Badge(text: problems == 0 ? "без проблем" : "проблем: \(problems)", icon: problems == 0 ? "checkmark" : "exclamationmark", tint: problems == 0 ? Theme.good : Theme.warn)
            if let median { Badge(text: String(format: "медиана пинга %.0f мс", median), tint: Theme.accent) }
            if lost > 0 { Badge(text: "потерь: \(lost)", tint: Theme.bad) }
        }
    }

    private var empty: some View {
        Text(settings.journalActive ? "Данные копятся, пока приложение работает (в том числе только в строке меню). Загляните через несколько минут." : "Нет записей за этот период.")
            .font(.system(size: 13)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
    }

    private var signalChart: some View {
        Chart {
            ForEach(samples) { s in
                if let r = s.rssi {
                    AreaMark(x: .value("Время", s.t), yStart: .value("dBm", -100), yEnd: .value("dBm", r))
                        .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Время", s.t), y: .value("dBm", r)).foregroundStyle(Theme.accent)
                }
            }
            RuleMark(y: .value("Порог", -67)).foregroundStyle(Theme.warn.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
            ForEach(events.filter { $0.kind == .disconnect || $0.kind == .roam || $0.kind == .bandChange }) { e in
                RuleMark(x: .value("Время", e.t)).foregroundStyle(e.kind.color.opacity(0.6))
                    .annotation(position: .top, alignment: .leading) { Image(systemName: e.kind.icon).font(.system(size: 9)).foregroundStyle(e.kind.color) }
            }
        }
        .chartYScale(domain: -100 ... -20)
        .modifier(DarkTimeAxes())
        .frame(height: 180)
    }

    private var pingChart: some View {
        Chart {
            ForEach(samples) { s in
                if let p = s.ping {
                    LineMark(x: .value("Время", s.t), y: .value("мс", min(p, 200))).foregroundStyle(Theme.cyan).interpolationMethod(.monotone)
                }
                if s.lost {
                    RuleMark(x: .value("Время", s.t)).foregroundStyle(Theme.bad.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
            RuleMark(y: .value("Норма", 15)).foregroundStyle(Theme.warn.opacity(0.4)).lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
        .modifier(DarkTimeAxes())
        .frame(height: 160)
    }
}

struct DarkTimeAxes: ViewModifier {
    func body(content: Content) -> some View {
        content
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel().foregroundStyle(Theme.text3)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel(format: .dateTime.hour().minute()).foregroundStyle(Theme.text3)
                }
            }
    }
}


extension Journal {
    func loadDemo() {
        let now = Date()
        samples = (0..<360).map { i in
            let t = now.addingTimeInterval(Double(i - 360) * 10)
            let x = Double(i)
            let dip = (200...215).contains(i) ? -14 : 0
            return JournalSample(t: t, rssi: -53 + Int((sin(x / 25) * 3).rounded()) + dip, noise: -92, rate: 1201,
                                 ping: 3 + abs(sin(x / 7)) * 4 + ((200...215).contains(i) ? 40 : 0), lost: i == 207, down: 0, up: 0)
        }
        events = [
            JournalEvent(t: now.addingTimeInterval(-1600), kind: .weakSignal, text: "Сигнал −71 dBm — ниже порога −70 dBm"),
            JournalEvent(t: now.addingTimeInterval(-1450), kind: .signalRecovered, text: "Сигнал восстановился: −54 dBm"),
            JournalEvent(t: now.addingTimeInterval(-900), kind: .speedTest, text: "Тест скорости: ↓ 341 / ↑ 48 Мбит/с"),
        ]
        dirty = false
    }
}
