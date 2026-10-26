import SwiftUI

struct RoomMeasurement: Codable, Identifiable {
    var id = UUID()
    let name: String
    let date: Date
    let rssi: Int
    let snr: Int
    let rate: Double
    let ping: Double?
    let loss: Double?
    let band: String?

    var quality: Double {
        let s = Analyzer.clamp(Double(rssi + 85) / 30)
        let p = ping.map { Analyzer.clamp(1 - ($0 - 3) / 40) } ?? s
        return s * 0.7 + p * 0.3
    }
}

/// Room-by-room walk test: averages the link for 10 s and pings the router at each spot.
@MainActor
final class SurveyStore: ObservableObject {
    static let shared = SurveyStore()

    @Published private(set) var rooms: [RoomMeasurement] = []
    @Published private(set) var measuring: String?
    @Published private(set) var progress: Double = 0

    private let url = AppInfo.supportDirectory.appendingPathComponent("survey.json")

    private init() {
        if let data = try? Data(contentsOf: url), let r = try? JSONDecoder().decode([RoomMeasurement].self, from: data) { rooms = r }
    }

    func measure(_ name: String, monitor: WiFiMonitor) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard measuring == nil, !name.isEmpty else { return }
        measuring = name
        progress = 0
        Task {
            let gateway = monitor.capabilities?.gateway
            async let ping: LatencyResult? = gateway != nil ? Pinger.run(label: "Роутер", host: gateway!, count: 20) : nil
            var rssi: [Int] = [], snr: [Int] = [], rate: [Double] = []
            for i in 0..<20 {
                if let l = LiveData.shared.link, l.isConnected {
                    rssi.append(l.rssi); snr.append(l.snr); rate.append(l.txRate)
                }
                progress = Double(i + 1) / 21
                try? await Task.sleep(for: .milliseconds(500))
            }
            let p = await ping
            progress = 1
            if !rssi.isEmpty {
                let m = RoomMeasurement(name: name, date: .now,
                                        rssi: rssi.reduce(0, +) / rssi.count, snr: snr.reduce(0, +) / snr.count,
                                        rate: rate.reduce(0, +) / Double(rate.count),
                                        ping: p?.avg, loss: p?.loss, band: monitor.link?.channel?.band.rawValue)
                rooms.removeAll { $0.name.lowercased() == name.lowercased() }
                rooms.append(m)
                save()
            }
            measuring = nil
        }
    }

    func remove(_ r: RoomMeasurement) { rooms.removeAll { $0.id == r.id }; save() }
    func clear() { rooms = []; save() }
    private func save() { try? JSONEncoder().encode(rooms).write(to: url) }
}

struct SurveyView: View {
    @EnvironmentObject var monitor: WiFiMonitor
    @ObservedObject var store = SurveyStore.shared
    @State private var name = ""

    private let presets = ["Гостиная", "Спальня", "Кухня", "Кабинет", "Детская", "Балкон", "Ванная"]

    var body: some View {
        SnapshotScroll {
            VStack(spacing: 18) {
                Card("Обход квартиры", icon: "map", hint: Hint(title: "Как пользоваться",
                    body: "Перенесите ноутбук в комнату, выберите её название и нажмите «Замерить». За 10 секунд приложение усреднит сигнал и проверит пинг до роутера. Повторите для каждой комнаты: увидите, где связь проседает и куда ставить роутер или mesh‑точку.")) {
                    HStack(spacing: 6) {
                        ForEach(Array(["1. Перейдите в комнату", "2. Выберите название", "3. Замерьте и не двигайтесь 10 с"].enumerated()), id: \.offset) { _, s in
                            Text(s).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.text2)
                                .padding(.horizontal, 10).padding(.vertical, 6).background(Color.white.opacity(0.05), in: Capsule())
                        }
                    }
                    HStack(spacing: 6) {
                        ForEach(presets, id: \.self) { p in
                            let on = name == p
                            Text(p).font(.system(size: 12, weight: on ? .semibold : .regular))
                                .foregroundStyle(on ? Theme.text : Theme.text2)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(on ? Theme.accent.opacity(0.25) : Color.white.opacity(0.05), in: Capsule())
                                .overlay(Capsule().strokeBorder(on ? Theme.accent.opacity(0.6) : .clear))
                                .onTapGesture { name = p }
                        }
                    }
                    HStack(spacing: 10) {
                        TextField("Или своё название", text: $name)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke))
                            .frame(maxWidth: 280)
                            .onSubmit { store.measure(name, monitor: monitor) }
                        Button {
                            store.measure(name, monitor: monitor)
                        } label: {
                            Label(store.measuring != nil ? "Замеряю «\(store.measuring!)»…" : "Замерить", systemImage: "scope")
                        }
                        .buttonStyle(.premium)
                        .disabled(store.measuring != nil || name.trimmingCharacters(in: .whitespaces).isEmpty)
                        if store.measuring != nil { GaugeBar(value: store.progress, tint: Theme.accent).frame(width: 160) }
                        Spacer()
                        if let l = LiveData.shared.link, l.isConnected {
                            Text("сейчас \(l.rssi) dBm").font(Theme.number(12, .medium)).foregroundStyle(Palette.rssi(l.rssi))
                        }
                    }
                }

                if !store.rooms.isEmpty {
                    verdict
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                        ForEach(store.rooms.sorted { $0.quality > $1.quality }) { r in roomCard(r) }
                    }
                    HStack {
                        Spacer()
                        Button("Начать новый обход") { store.clear() }.buttonStyle(.premiumSecondary)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Карта квартиры")
    }

    private var verdict: some View {
        let sorted = store.rooms.sorted { $0.quality > $1.quality }
        let best = sorted.first!, worst = sorted.last!
        let weak = sorted.filter { $0.rssi < -70 }
        let text: String
        if store.rooms.count == 1 {
            text = "Замерьте ещё хотя бы одну комнату, чтобы сравнить."
        } else if weak.isEmpty {
            text = "Во всех комнатах сигнал достаточный. Лучше всего в «\(best.name)», хуже всего в «\(worst.name)» (\(worst.rssi) dBm), но и там хватит для видео."
        } else {
            text = "Слабое покрытие: \(weak.map { "«\($0.name)» (\($0.rssi) dBm)" }.joined(separator: ", ")). Передвиньте роутер ближе к этим комнатам или поставьте mesh‑точку на полпути между «\(best.name)» и «\(weak.last!.name)». Репитер в самой слабой комнате не поможет: он будет повторять уже плохой сигнал."
        }
        return Card("Вывод", icon: "sparkles") {
            Text(text).font(.system(size: 13.5)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func roomCard(_ r: RoomMeasurement) -> some View {
        let tint = Palette.score(r.quality)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(r.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                Spacer()
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.text3)
                    .onTapGesture { store.remove(r) }
                    .help("Удалить замер")
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(r.rssi)").font(Theme.number(30)).foregroundStyle(tint)
                Text("dBm").font(.system(size: 12)).foregroundStyle(Theme.text3)
                Spacer()
                SignalBars(rssi: r.rssi).scaleEffect(1.3)
            }
            GaugeBar(value: r.quality, tint: tint)
            HStack(spacing: 12) {
                mini("SNR", "\(r.snr) dB")
                mini("Скорость", String(format: "%.0f", r.rate))
                mini("Пинг", r.ping.map { String(format: "%.0f мс", $0) } ?? "—")
            }
            if let loss = r.loss, loss > 0 { Text(String(format: "потери %.0f%%", loss * 100)).font(.system(size: 11.5)).foregroundStyle(Theme.warn) }
            Text("\(r.band ?? "") · \(r.date.formatted(date: .omitted, time: .shortened))").font(.system(size: 11)).foregroundStyle(Theme.text3)
        }
        .padding(16)
        .glass(radius: 16)
    }

    private func mini(_ t: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(t.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(0.6).foregroundStyle(Theme.text3)
            Text(v).font(Theme.number(12.5, .medium)).foregroundStyle(Theme.text)
        }
    }
}

// MARK: - Per-app traffic

struct AppTraffic: Identifiable {
    var id: String { name }
    let name: String
    let pid: Int32
    var down: Double // bytes/s
    var up: Double
}

/// Samples per-process Wi‑Fi traffic with `nettop` while the view is visible.
@MainActor
final class AppTrafficMonitor: ObservableObject {
    static let shared = AppTrafficMonitor()
    @Published private(set) var apps: [AppTraffic] = []
    @Published private(set) var lastUpdate: Date?
    private var task: Task<Void, Never>?

    func start() {
        guard task == nil, !AppInfo.isDemo else { return }
        task = Task {
            while !Task.isCancelled {
                let out = await Task.detached { String(decoding: SystemInfo.run("/usr/bin/nettop", ["-P", "-d", "-L", "2", "-s", "1", "-J", "bytes_in,bytes_out", "-x", "-t", "wifi"]), as: UTF8.self) }.value
                apps = AppTrafficMonitor.parse(out)
                lastUpdate = .now
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func stop() { task?.cancel(); task = nil }

    /// nettop prints two blocks; the second holds per-second deltas.
    nonisolated static func parse(_ out: String) -> [AppTraffic] {
        let blocks = out.components(separatedBy: ",bytes_in,bytes_out,")
        guard blocks.count >= 3 else { return [] }
        var byName: [String: AppTraffic] = [:]
        for line in blocks[2].split(separator: "\n") {
            let f = line.split(separator: ",", omittingEmptySubsequences: false)
            guard f.count >= 3, let i = Double(f[1]), let o = Double(f[2]) else { continue }
            let proc = String(f[0])
            let dot = proc.lastIndex(of: ".")
            let name = dot.map { String(proc[..<$0]) } ?? proc
            let pid = dot.flatMap { Int32(proc[proc.index(after: $0)...]) } ?? 0
            let pretty = NSRunningApplication(processIdentifier: pid)?.localizedName ?? name
            byName[pretty, default: AppTraffic(name: pretty, pid: pid, down: 0, up: 0)].down += i
            byName[pretty]!.up += o
        }
        return byName.values.filter { $0.down + $0.up > 0 }.sorted { $0.down + $0.up > $1.down + $1.up }
    }
}

struct AppTrafficView: View {
    @EnvironmentObject var monitor: WiFiMonitor
    @EnvironmentObject var live: LiveData
    @ObservedObject var traffic = AppTrafficMonitor.shared

    var body: some View {
        SnapshotScroll {
            VStack(spacing: 18) {
                HStack(spacing: 14) {
                    total("Всего входящий", live.downRate, Theme.cyan, "arrow.down")
                    total("Всего исходящий", live.upRate, Theme.pink, "arrow.up")
                }
                Card("Кто сейчас использует Wi‑Fi", icon: "app.badge",
                     hint: Hint(title: "Трафик по приложениям", body: "Скорость каждого процесса через Wi‑Fi за последнюю секунду (данные системной утилиты nettop). Помогает найти, кто «съедает» канал: облачная синхронизация, торрент, обновления."),
                     trailing: AnyView(Text(traffic.lastUpdate.map { "обновлено \($0.formatted(date: .omitted, time: .standard))" } ?? "загрузка…").font(.system(size: 11.5)).foregroundStyle(Theme.text3))) {
                    if traffic.apps.isEmpty {
                        Text("Сейчас никто не передаёт данные через Wi‑Fi.").font(.system(size: 13)).foregroundStyle(Theme.text2)
                    }
                    let peak = max(1, traffic.apps.map { $0.down + $0.up }.max() ?? 1)
                    ForEach(traffic.apps.prefix(15)) { a in
                        HStack(spacing: 12) {
                            appIcon(a).frame(width: 22, height: 22)
                            Text(a.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text).lineLimit(1).frame(width: 200, alignment: .leading)
                            GeometryReader { g in
                                HStack(spacing: 0) {
                                    Capsule().fill(Theme.cyan).frame(width: g.size.width * a.down / peak)
                                    Capsule().fill(Theme.pink).frame(width: g.size.width * a.up / peak)
                                }
                                .frame(maxHeight: .infinity)
                            }
                            .frame(height: 6)
                            Text("↓ " + Format.speed(a.down)).foregroundStyle(Theme.cyan).frame(width: 100, alignment: .trailing)
                            Text("↑ " + Format.speed(a.up)).foregroundStyle(Theme.pink).frame(width: 100, alignment: .trailing)
                        }
                        .font(.system(size: 12).monospacedDigit())
                    }
                    if traffic.apps.contains(where: { $0.name.localizedCaseInsensitiveContains("vpn") }) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lock.shield").foregroundStyle(Theme.warn)
                            Text("Включён VPN: трафик приложений внутри туннеля виден одной строкой — самим VPN‑клиентом.")
                                .font(.system(size: 12)).foregroundStyle(Theme.text2)
                        }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Приложения")
        .onAppear { traffic.start() }
        .onDisappear { traffic.stop() }
    }

    private func total(_ t: String, _ v: Double, _ c: Color, _ icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundStyle(c)
                .frame(width: 36, height: 36).background(c.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(t.uppercased()).font(Theme.eyebrow).tracking(0.8).foregroundStyle(Theme.text3)
                Text(Format.speed(v)).font(Theme.number(24)).foregroundStyle(Theme.text)
            }
            Spacer()
        }
        .padding(16)
        .glass(radius: 16)
    }

    @ViewBuilder private func appIcon(_ a: AppTraffic) -> some View {
        if let img = NSRunningApplication(processIdentifier: a.pid)?.icon {
            Image(nsImage: img).resizable()
        } else {
            Image(systemName: "gearshape.fill").font(.system(size: 13)).foregroundStyle(Theme.text3)
        }
    }
}


extension SurveyStore {
    func loadDemo() {
        let now = Date()
        rooms = [("Гостиная", -48, 44, 1201.0, 3.0), ("Кухня", -59, 33, 864.0, 5.0), ("Кабинет", -63, 29, 720.0, 6.0), ("Спальня", -74, 18, 286.0, 14.0)].map {
            RoomMeasurement(name: $0.0, date: now, rssi: $0.1, snr: $0.2, rate: $0.3, ping: $0.4, loss: 0, band: "5 ГГц")
        }
    }
}

extension AppTrafficMonitor {
    func loadDemo() {
        apps = [AppTraffic(name: "Safari", pid: 0, down: 3.1e6, up: 0.12e6), AppTraffic(name: "Музыка", pid: 0, down: 0.41e6, up: 0.01e6),
                AppTraffic(name: "iCloud Drive", pid: 0, down: 0.05e6, up: 0.9e6), AppTraffic(name: "Telegram", pid: 0, down: 0.08e6, up: 0.02e6),
                AppTraffic(name: "mDNSResponder", pid: 0, down: 0.002e6, up: 0.001e6)]
        lastUpdate = .now
    }
}
