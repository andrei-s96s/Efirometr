import SwiftUI
import Charts

struct SpeedResult: Codable, Identifiable {
    var id = UUID()
    let date: Date
    let down: Double // bits per second
    let up: Double
    let rtt: Double // ms, idle
    let rpm: Double // round-trips per minute under load
    let rssi: Int?
    let band: String?
    let phyRate: Double?

    var responsiveness: (label: String, color: Color) {
        switch rpm {
        case 1000...: return ("высокая", Theme.good)
        case 400..<1000: return ("средняя", Theme.fair)
        case 200..<400: return ("низкая", Theme.warn)
        default: return ("очень низкая", Theme.bad)
        }
    }

    /// Loaded latency derived from RPM: 60 000 ms / RPM.
    var loadedLatency: Double { rpm > 0 ? 60_000 / rpm : 0 }
}

/// Runs Apple's built-in `networkQuality` (same servers as System Information speed test).
@MainActor
final class SpeedTester: ObservableObject {
    static let shared = SpeedTester()

    @Published private(set) var running = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var results: [SpeedResult] = []
    @Published private(set) var error: String?

    private let duration = 15.0
    private let url = AppInfo.supportDirectory.appendingPathComponent("speedtests.json")

    private init() {
        if let data = try? Data(contentsOf: url), let r = try? JSONDecoder().decode([SpeedResult].self, from: data) { results = r }
    }

    var last: SpeedResult? { results.last }

    func run(monitor: WiFiMonitor) {
        guard !running else { return }
        running = true
        progress = 0
        error = nil
        let iface = monitor.interfaceName
        let link = monitor.link
        let start = Date()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.running else { return }
                self.progress = min(0.97, Date().timeIntervalSince(start) / (self.duration + 2))
            }
        }
        let duration = duration
        Task.detached(priority: .userInitiated) {
            let data = SystemInfo.run("/usr/bin/networkQuality", ["-c", "-M", "\(Int(duration))", "-I", iface])
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            await MainActor.run {
                timer.invalidate()
                self.running = false
                self.progress = 1
                guard let json, let down = json["dl_throughput"] as? Double, let up = json["ul_throughput"] as? Double else {
                    self.error = "Тест не удался. Проверьте подключение к интернету."
                    return
                }
                let r = SpeedResult(date: .now, down: down, up: up,
                                    rtt: json["base_rtt"] as? Double ?? 0, rpm: json["responsiveness"] as? Double ?? 0,
                                    rssi: link?.rssi, band: link?.channel?.band.rawValue, phyRate: link?.txRate)
                self.results.append(r)
                if self.results.count > 100 { self.results.removeFirst(self.results.count - 100) }
                try? JSONEncoder().encode(self.results).write(to: self.url)
                Journal.shared.add(.speedTest, String(format: "Тест скорости: ↓ %.0f / ↑ %.0f Мбит/с", down / 1e6, up / 1e6))
            }
        }
    }

    func clear() {
        results = []
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - View

struct SpeedTestView: View {
    @EnvironmentObject var monitor: WiFiMonitor
    @EnvironmentObject var tester: SpeedTester

    var body: some View {
        SnapshotScroll {
            VStack(spacing: 18) {
                hero
                if let r = tester.last {
                    HStack(alignment: .top, spacing: 18) {
                        verdictCard(r)
                        latencyCard(r)
                    }
                }
                historyCard
            }
            .padding(24)
        }
        .navigationTitle("Тест скорости")
    }

    private var hero: some View {
        let r = tester.last
        return HStack(spacing: 28) {
            SpeedDial(title: "Загрузка", icon: "arrow.down", value: tester.running ? nil : r.map { $0.down / 1e6 }, tint: Theme.cyan,
                      max: max(100, monitor.link?.txRate ?? 500))
            SpeedDial(title: "Отдача", icon: "arrow.up", value: tester.running ? nil : r.map { $0.up / 1e6 }, tint: Theme.pink,
                      max: max(100, monitor.link?.txRate ?? 500))
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "Реальная скорость интернета", icon: "speedometer")
                Text(tester.running ? "Измеряю…" : r == nil ? "Ещё не измеряли" : "Последний тест · \(r!.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
                Text("Использует встроенный в macOS тест Apple (networkQuality): несколько параллельных потоков на серверы Apple, около 15 секунд. Расходует 300–800 МБ трафика.")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                if tester.running {
                    GaugeBar(value: tester.progress, tint: Theme.accent, height: 6).frame(maxWidth: 320)
                } else {
                    Button { tester.run(monitor: monitor) } label: {
                        Label(r == nil ? "Запустить тест" : "Повторить тест", systemImage: "play.fill")
                    }
                    .buttonStyle(.premium)
                }
                if let e = tester.error { Text(e).font(.system(size: 12)).foregroundStyle(Theme.bad) }
            }
            Spacer(minLength: 0)
        }
        .padding(28)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.card)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.cyan.opacity(0.12), Theme.violet.opacity(0.08), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.strokeGradient))
    }

    private func verdictCard(_ r: SpeedResult) -> some View {
        let phy = r.phyRate ?? monitor.link?.txRate ?? 0
        let wifiReal = phy * 0.65
        let down = r.down / 1e6
        let wifiBound = wifiReal > 0 && down > wifiReal * 0.8
        return Card("Где узкое место", icon: "point.topleft.down.to.point.bottomright.curvepath",
                    hint: Hint(title: "Как это считается",
                               body: "Wi‑Fi на практике даёт около 65% от скорости канала. Если интернет почти упирается в это значение, ограничивает Wi‑Fi. Если интернет заметно ниже, ограничивает тариф или провайдер.")) {
            HStack(spacing: 14) {
                pipe("Wi‑Fi (реально)", wifiReal, Theme.accent, highlight: wifiBound)
                Image(systemName: "chevron.right").foregroundStyle(Theme.text3)
                pipe("Интернет", down, Theme.cyan, highlight: !wifiBound)
            }
            Text(wifiBound
                 ? "Скорость упирается в Wi‑Fi. Улучшите сигнал или канал, тогда интернет станет быстрее."
                 : String(format: "Wi‑Fi может дать до ~%.0f Мбит/с, а интернет — %.0f. Ограничивает тариф или провайдер, а не Wi‑Fi.", wifiReal, down))
                .font(.system(size: 13)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pipe(_ title: String, _ v: Double, _ c: Color, highlight: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(Theme.eyebrow).tracking(0.8).foregroundStyle(Theme.text3)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.0f", v)).font(Theme.number(26)).foregroundStyle(c)
                Text("Мбит/с").font(.system(size: 12)).foregroundStyle(Theme.text3)
            }
            if highlight { Badge(text: "узкое место", icon: "exclamationmark", tint: Theme.warn) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 14, fill: Color.white.opacity(0.03))
    }

    private func latencyCard(_ r: SpeedResult) -> some View {
        let resp = r.responsiveness
        return Card("Отзывчивость под нагрузкой", icon: "bolt.horizontal.circle",
                    hint: Hint(title: "Отзывчивость (RPM)",
                               body: "Сколько запросов в минуту сеть успевает обработать, пока канал забит загрузкой. Это показывает, будут ли лагать звонки и игры, когда кто‑то качает файлы.",
                               scale: [.init(range: "> 1000 RPM", label: "Высокая", color: Theme.good),
                                       .init(range: "400–1000", label: "Средняя", color: Theme.fair),
                                       .init(range: "200–400", label: "Низкая", color: Theme.warn),
                                       .init(range: "< 200", label: "Лаги при загрузке", color: Theme.bad)],
                               tip: "Низкая отзывчивость лечится включением SQM / Smart Queue (или «QoS») на роутере.")) {
            HStack(spacing: 14) {
                stat("В покое", String(format: "%.0f", r.rtt), "мс", Theme.text)
                stat("Под нагрузкой", String(format: "%.0f", r.loadedLatency), "мс", resp.color)
                stat("Отзывчивость", String(format: "%.0f", r.rpm), "RPM", resp.color)
            }
            Text("Отзывчивость \(resp.label). " + (r.rpm < 400 ? "Когда кто‑то качает, звонки и игры будут подлагивать." : "Звонки не пострадают даже при загрузке канала."))
                .font(.system(size: 13)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stat(_ t: String, _ v: String, _ u: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(t.uppercased()).font(Theme.eyebrow).tracking(0.8).foregroundStyle(Theme.text3)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(v).font(Theme.number(24)).foregroundStyle(c)
                Text(u).font(.system(size: 11)).foregroundStyle(Theme.text3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var historyCard: some View {
        Card("История тестов", icon: "clock.arrow.circlepath",
             trailing: AnyView(Group { if !tester.results.isEmpty { Button("Очистить") { tester.clear() }.buttonStyle(.premiumSecondary) } })) {
            if tester.results.count < 2 {
                Text("Здесь появится график, когда будет хотя бы два теста. Запускайте тест в разное время суток, чтобы увидеть вечернюю просадку провайдера.")
                    .font(.system(size: 13)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
            } else {
                Chart(tester.results) { r in
                    LineMark(x: .value("Дата", r.date), y: .value("Мбит/с", r.down / 1e6), series: .value("Ряд", "↓"))
                        .foregroundStyle(Theme.cyan).symbol(.circle)
                    LineMark(x: .value("Дата", r.date), y: .value("Мбит/с", r.up / 1e6), series: .value("Ряд", "↑"))
                        .foregroundStyle(Theme.pink).symbol(.circle)
                }
                .chartYAxis {
                    AxisMarks(position: .trailing) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.06))
                        AxisValueLabel().foregroundStyle(Theme.text3)
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.06))
                        AxisValueLabel(format: .dateTime.day().month().hour().minute()).foregroundStyle(Theme.text3)
                    }
                }
                .frame(height: 180)
                ChartLegend(items: [("Загрузка, Мбит/с", Theme.cyan), ("Отдача", Theme.pink)])
            }
            ForEach(tester.results.suffix(6).reversed()) { r in
                HStack {
                    Text(r.date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(Theme.text2).frame(width: 150, alignment: .leading)
                    Text(String(format: "↓ %.0f", r.down / 1e6)).foregroundStyle(Theme.cyan).frame(width: 70, alignment: .leading)
                    Text(String(format: "↑ %.0f", r.up / 1e6)).foregroundStyle(Theme.pink).frame(width: 70, alignment: .leading)
                    Text(String(format: "%.0f RPM", r.rpm)).foregroundStyle(r.responsiveness.color).frame(width: 80, alignment: .leading)
                    Spacer()
                    if let rssi = r.rssi { Text("\(r.band ?? "") · \(rssi) dBm").foregroundStyle(Theme.text3) }
                }
                .font(.system(size: 12).monospacedDigit())
            }
        }
    }
}

struct SpeedDial: View {
    var title: String
    var icon: String
    var value: Double? // Mbit/s, nil = running/empty
    var tint: Color
    var max: Double

    var body: some View {
        let frac = value.map { Swift.min(1, $0 / max) } ?? 0
        ZStack {
            Circle().trim(from: 0, to: 0.75).stroke(Color.white.opacity(0.07), style: StrokeStyle(lineWidth: 10, lineCap: .round)).rotationEffect(.degrees(135))
            Circle().trim(from: 0, to: 0.75 * frac)
                .stroke(LinearGradient(colors: [tint.opacity(0.5), tint], startPoint: .leading, endPoint: .trailing), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(135))
                .shadow(color: tint.opacity(0.5), radius: 8)
                .animation(.spring(duration: 1), value: frac)
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 12, weight: .bold)).foregroundStyle(tint)
                Text(value.map { String(format: "%.0f", $0) } ?? "—").font(Theme.number(30, .bold)).foregroundStyle(Theme.text)
                Text("Мбит/с").font(.system(size: 10.5)).foregroundStyle(Theme.text3)
                Text(title.uppercased()).font(.system(size: 9.5, weight: .semibold)).tracking(0.8).foregroundStyle(Theme.text2).padding(.top, 4)
            }
        }
        .frame(width: 150, height: 150)
    }
}


extension SpeedTester {
    func loadDemo() {
        let now = Date()
        results = [(-50, 286.0, 41.0, 22.0, 640.0), (-30, 302.0, 44.0, 19.0, 910.0), (-8, 318.0, 47.0, 17.0, 1180.0), (0, 341.0, 48.0, 16.0, 1250.0)].map {
            SpeedResult(date: now.addingTimeInterval(Double($0.0) * 3600), down: $0.1 * 1e6, up: $0.2 * 1e6, rtt: $0.3, rpm: $0.4,
                        rssi: -52, band: "5 ГГц", phyRate: 1201)
        }
    }
}
