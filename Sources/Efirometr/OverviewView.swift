import SwiftUI

// MARK: - Overview: the short answer — score, key numbers, top tips, shortcuts.

struct OverviewView: View {
    @EnvironmentObject var monitor: WiFiMonitor
    @EnvironmentObject var nav: NavigationModel

    var body: some View {
        let a = monitor.assessment
        SnapshotScroll {
            VStack(spacing: 18) {
                UpdateBanner()
                hero(a)
                LiveMetrics()
                HStack(alignment: .top, spacing: 18) {
                    topTips(a)
                    shortcuts.frame(width: 380)
                }
            }
            .padding(24)
        }
        .navigationTitle("Обзор")
    }

    private func hero(_ a: Assessment) -> some View {
        let tint = Palette.score(Double(a.score) / 100)
        return HStack(alignment: .center, spacing: 32) {
            ZStack(alignment: .topTrailing) {
                ScoreRing(score: a.score, size: 156, lineWidth: 12)
                HintButton(hint: Hints.score).offset(x: 6, y: -2)
            }
            .background(Circle().fill(RadialGradient(colors: [tint.opacity(0.18), .clear], center: .center, startRadius: 40, endRadius: 100)).padding(-20))

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Circle().fill(tint).frame(width: 7, height: 7)
                    Text("ОЦЕНКА СЕТИ · \(a.grade.uppercased())").font(Theme.eyebrow).tracking(1.2).foregroundStyle(tint)
                }
                Text(networkTitle)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(a.summary).font(.system(size: 14)).foregroundStyle(Theme.text2)
                if let l = monitor.link, l.isConnected, let ch = l.channel {
                    HStack(spacing: 6) {
                        Badge(text: ch.band.title, icon: "antenna.radiowaves.left.and.right", tint: NetworkCard.color(ch.band))
                        Badge(text: String(localized: "Канал \(ch.number)"), tint: Theme.accent)
                        Badge(text: String(localized: "\(ch.width) МГц"), tint: Theme.text2)
                        Badge(text: PHY.label(l.phy), tint: Theme.pink).help(PHY.explain(l.phy))
                        Badge(text: l.security.name, icon: "lock.fill", tint: l.security.score >= 0.75 ? Theme.good : Theme.warn)
                    }
                }
                HStack(spacing: 10) {
                    Button { monitor.scan() } label: {
                        Label(monitor.isScanning ? String(localized: "Сканирую…") : String(localized: "Сканировать эфир"), systemImage: "dot.radiowaves.left.and.right")
                    }
                    .buttonStyle(.premium)
                    .disabled(monitor.isScanning)
                    .help("Найти все сети вокруг и пересчитать оценку")
                    Button { nav.section = .advice } label: { Label("Все советы", systemImage: "lightbulb") }
                        .buttonStyle(.premiumSecondary)
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(26)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.card)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.accent.opacity(0.14), Theme.violet.opacity(0.08), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.strokeGradient))
    }

    private var networkTitle: String {
        guard let l = monitor.link, l.isConnected else { return String(localized: "Не подключено") }
        return l.ssid ?? String(localized: "Ваша Wi‑Fi сеть")
    }

    private func topTips(_ a: Assessment) -> some View {
        let tips = a.recommendations.filter { $0.severity <= .tip }
        return Card(String(localized: "Что улучшить"), icon: "lightbulb",
                    trailing: AnyView(Button("Все советы →") { nav.section = .advice }.buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent))) {
            if tips.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.good).font(.system(size: 20))
                    Text("Серьёзных проблем нет — сеть работает хорошо.").font(.system(size: 13.5)).foregroundStyle(Theme.text)
                }
            }
            VStack(spacing: 6) {
                ForEach(tips.prefix(3)) { r in
                    HStack(spacing: 12) {
                        Image(systemName: r.icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(r.severity.color)
                            .frame(width: 30, height: 30).background(r.severity.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 9))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                            Text(r.severity.label).font(.system(size: 11)).foregroundStyle(r.severity.color)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text3)
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                    .onTapGesture { nav.section = .advice }
                }
            }
        }
    }

    private var shortcuts: some View {
        Card(String(localized: "Инструменты"), icon: "square.grid.2x2") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ShortcutTile(icon: "speedometer", title: String(localized: "Тест скорости"), subtitle: SpeedTester.shared.last.map { String(format: String(localized: "↓ %.0f Мбит/с"), $0.down / 1e6) } ?? String(localized: "ещё не было"), tint: Theme.cyan) { nav.section = .speed }
                ShortcutTile(icon: "waveform.path.ecg", title: String(localized: "Монитор"), subtitle: String(localized: "живые графики"), tint: Theme.accent) { nav.section = .monitor }
                ShortcutTile(icon: "chart.xyaxis.line", title: String(localized: "Каналы"), subtitle: String(localized: "сетей рядом: \(monitor.groups.filter { !$0.isMine }.count)"), tint: Theme.violet) { nav.section = .channels }
                ShortcutTile(icon: "map", title: String(localized: "Карта квартиры"), subtitle: SurveyStore.shared.rooms.isEmpty ? String(localized: "обход комнат") : String(localized: "комнат: \(SurveyStore.shared.rooms.count)"), tint: Theme.pink) { nav.section = .survey }
            }
        }
    }
}

struct ShortcutTile: View {
    var icon: String
    var title: String
    var subtitle: String
    var tint: Color
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 30, height: 30).background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
            Text(subtitle).font(.system(size: 11.5)).foregroundStyle(Theme.text3).lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(hover ? 0.07 : 0.035), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: action)
    }
}

/// The four live tiles. Only this view re-renders every second on the Overview.
struct LiveMetrics: View {
    @EnvironmentObject var live: LiveData
    @EnvironmentObject var monitor: WiFiMonitor

    var body: some View {
        let l = live.link
        let ok = l?.isConnected == true
        let ceiling = Analyzer.maxRate(width: min(monitor.capabilities?.maxWidth ?? 80, l?.channel?.width ?? 80))
        return HStack(spacing: 14) {
            MetricCard(title: String(localized: "Сигнал"), value: ok ? "\(l!.rssi)" : "—", unit: "dBm",
                       caption: ok ? quality(l!.rssi) : String(localized: "нет данных"), icon: "wifi",
                       tint: ok ? Palette.rssi(l!.rssi) : Theme.text3,
                       progress: ok ? Double(l!.rssi + 90) / 60 : nil, ticks: [23.0 / 60, 35.0 / 60], hint: Hints.signal)
            MetricCard(title: String(localized: "Сигнал / шум"), value: ok ? "\(l!.snr)" : "—", unit: "dB",
                       caption: ok ? String(localized: "шум \(l!.noise) dBm · \(snrQuality(l!.snr))") : String(localized: "нет данных"), icon: "waveform",
                       tint: ok ? Palette.score(Double(l!.snr - 10) / 30) : Theme.text3,
                       progress: ok ? Double(l!.snr) / 50 : nil, ticks: [0.5, 0.8], hint: Hints.snr)
            MetricCard(title: String(localized: "Скорость канала"), value: ok ? String(format: "%.0f", l!.txRate) : "—", unit: String(localized: "Мбит/с"),
                       caption: ok ? String(format: String(localized: "%.0f%% от потолка %.0f"), l!.txRate / ceiling * 100, ceiling) : String(localized: "нет данных"),
                       icon: "speedometer", tint: Theme.accent, progress: ok ? l!.txRate / ceiling : nil, hint: Hints.rate)
            MetricCard(title: String(localized: "Трафик сейчас"), value: Format.speed(live.downRate), unit: "",
                       caption: String(localized: "↑ отдача ") + Format.speed(live.upRate), icon: "arrow.up.arrow.down", tint: Theme.cyan, hint: Hints.traffic)
        }
    }

    private func quality(_ rssi: Int) -> String {
        if rssi >= -55 { return String(localized: "отличный сигнал") }
        if rssi >= -67 { return String(localized: "хороший сигнал") }
        if rssi >= -75 { return String(localized: "средний сигнал") }
        return String(localized: "слабый сигнал")
    }

    private func snrQuality(_ snr: Int) -> String {
        if snr >= 40 { return String(localized: "чисто") }
        if snr >= 25 { return String(localized: "нормально") }
        if snr >= 15 { return String(localized: "помехи") }
        return String(localized: "сильные помехи")
    }
}

// MARK: - Advice: full recommendations and what the score is made of.

struct AdviceView: View {
    @EnvironmentObject var monitor: WiFiMonitor

    var body: some View {
        let a = monitor.assessment
        SnapshotScroll {
            VStack(spacing: 18) {
                HStack(alignment: .top, spacing: 18) {
                    breakdown(a).frame(maxWidth: 400)
                    LatencyCard()
                }
                recommendations(a)
            }
            .padding(24)
        }
        .navigationTitle("Советы")
    }

    private func breakdown(_ a: Assessment) -> some View {
        let weakest = a.components.min { $0.value < $1.value }?.id
        return Card(String(localized: "Из чего складывается оценка"), icon: "chart.bar.doc.horizontal", hint: Hints.breakdown,
                    trailing: AnyView(Text("\(a.score) / 100").font(Theme.number(14)).foregroundStyle(Palette.score(Double(a.score) / 100)))) {
            VStack(spacing: 14) {
                ForEach(a.components) { c in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: c.icon).font(.system(size: 11)).foregroundStyle(Theme.text3).frame(width: 16)
                            Text(c.name).font(.system(size: 13, weight: c.id == weakest ? .semibold : .regular)).foregroundStyle(Theme.text)
                            if c.id == weakest && c.value < 0.85 {
                                Text("СЛАБОЕ МЕСТО").font(.system(size: 8.5, weight: .bold)).tracking(0.6).foregroundStyle(Theme.warn)
                                    .padding(.horizontal, 5).padding(.vertical, 2).background(Theme.warn.opacity(0.14), in: Capsule())
                            }
                            Spacer()
                            Text(c.detail).font(.system(size: 11.5)).foregroundStyle(Theme.text3)
                        }
                        GaugeBar(value: c.value, tint: Palette.score(c.value), height: 5)
                    }
                }
                if a.components.isEmpty { Text("Нет подключения").foregroundStyle(Theme.text2) }
            }
        }
    }

    private func recommendations(_ a: Assessment) -> some View {
        let firstWithSteps = a.recommendations.first { !$0.steps.isEmpty }?.title
        let actionable = a.recommendations.filter { $0.severity <= .tip }.count
        return Card(String(localized: "Рекомендации"), icon: "lightbulb",
                    trailing: AnyView(Text(actionable == 0 ? String(localized: "всё в порядке") : String(localized: "что улучшить: \(actionable)"))
                        .font(.system(size: 12)).foregroundStyle(Theme.text3))) {
            VStack(spacing: 2) {
                // Keyed by title so rows keep their expanded state when the assessment refreshes.
                ForEach(a.recommendations, id: \.title) { rec in
                    RecommendationRow(rec: rec, expanded: rec.title == firstWithSteps)
                    if rec.id != a.recommendations.last?.id { Divider().overlay(Theme.stroke).padding(.leading, 62) }
                }
            }
            Text("Нажмите на совет, чтобы раскрыть пошаговую инструкцию.").font(.system(size: 11.5)).foregroundStyle(Theme.text3)
        }
    }
}

// MARK: - Monitor: live charts.

struct MonitorView: View {
    @EnvironmentObject var live: LiveData

    var body: some View {
        SnapshotScroll {
            VStack(spacing: 18) {
                LiveMetrics()
                Card(String(localized: "Сигнал в реальном времени · 2 минуты"), icon: "waveform.path.ecg", hint: Hints.signalChart,
                     trailing: AnyView(Text(live.link.map { "\($0.rssi) dBm" } ?? "").font(Theme.number(13)).foregroundStyle(Theme.accent))) {
                    LiveSignalChart().frame(height: 200)
                    ChartLegend(items: [(String(localized: "Сигнал"), Theme.accent), (String(localized: "Шум"), Theme.text3)])
                }
                Card(String(localized: "Трафик Wi‑Fi · Мбит/с"), icon: "arrow.up.arrow.down", hint: Hints.traffic,
                     trailing: AnyView(HStack(spacing: 10) {
                         Text("↓ \(Format.speed(live.downRate))").foregroundStyle(Theme.cyan)
                         Text("↑ \(Format.speed(live.upRate))").foregroundStyle(Theme.pink)
                     }.font(Theme.number(12.5)))) {
                    LiveThroughputChart().frame(height: 200)
                    ChartLegend(items: [(String(localized: "Входящий"), Theme.cyan), (String(localized: "Исходящий"), Theme.pink)])
                }
                LatencyCard()
            }
            .padding(24)
        }
        .navigationTitle("Монитор")
    }
}

struct ChartLegend: View {
    var items: [(String, Color)]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(items, id: \.0) { name, color in
                HStack(spacing: 6) {
                    Capsule().fill(color).frame(width: 14, height: 3)
                    Text(name).font(.system(size: 11)).foregroundStyle(Theme.text2)
                }
            }
        }
    }
}

struct LatencyCard: View {
    @EnvironmentObject var monitor: WiFiMonitor

    var body: some View {
        Card(String(localized: "Задержка и потери"), icon: "timer", hint: Hints.latency,
             trailing: AnyView(Button(monitor.isTestingLatency ? String(localized: "Измеряю…") : (monitor.latency.isEmpty ? String(localized: "Запустить") : String(localized: "Повторить"))) { monitor.testLatency() }
                .buttonStyle(.premiumSecondary)
                .disabled(monitor.isTestingLatency))) {
            if monitor.latency.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Тест покажет, где теряется скорость: в Wi‑Fi (до роутера) или у провайдера (до интернета). Занимает около 5 секунд.")
                        .font(.system(size: 13)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                    if monitor.isTestingLatency { ProgressView().controlSize(.small) }
                }
            } else {
                HStack(spacing: 12) {
                    ForEach(monitor.latency) { r in tile(r) }
                }
                if let verdict {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.turn.down.right").foregroundStyle(Theme.accent)
                        Text(verdict).foregroundStyle(Theme.text)
                    }
                    .font(.system(size: 12.5, weight: .medium))
                }
            }
        }
    }

    private var verdict: String? {
        guard let gw = monitor.latency.first(where: { $0.label == String(localized: "Роутер") }),
              let inet = monitor.latency.first(where: { $0.label == String(localized: "Интернет") }) else { return nil }
        if gw.avg > 15 || gw.loss > 0.01 { return String(localized: "Узкое место — Wi‑Fi между Mac и роутером.") }
        if inet.avg - gw.avg > 60 { return String(localized: "Wi‑Fi в порядке, задержку добавляет провайдер.") }
        return String(localized: "И Wi‑Fi, и интернет отвечают быстро.")
    }

    private func tile(_ r: LatencyResult) -> some View {
        let isGW = r.label == String(localized: "Роутер")
        let tint = r.loss >= 1 ? Theme.bad : Palette.score(1 - r.avg / (isGW ? 40 : 150))
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: isGW ? "wifi.router" : "globe").foregroundStyle(Theme.text3)
                Text(isGW ? String(localized: "До роутера") : String(localized: "До интернета")).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.text2)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(r.loss >= 1 ? "—" : String(format: "%.0f", r.avg)).font(Theme.number(30)).foregroundStyle(tint)
                Text(r.loss >= 1 ? String(localized: "нет ответа") : String(localized: "мс")).font(.system(size: 13)).foregroundStyle(Theme.text3)
            }
            Text(String(format: String(localized: "джиттер %.0f мс · %.0f–%.0f мс"), r.jitter, r.min, r.max)).font(.system(size: 11.5)).foregroundStyle(Theme.text3)
            Text(String(format: String(localized: "потери %.0f%%"), r.loss * 100)).font(.system(size: 11.5, weight: r.loss > 0 ? .semibold : .regular))
                .foregroundStyle(r.loss > 0 ? Theme.warn : Theme.text3)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(radius: 14, fill: Color.white.opacity(0.03))
    }
}
