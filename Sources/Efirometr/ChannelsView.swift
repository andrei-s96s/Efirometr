import SwiftUI
import Charts

struct ChannelsView: View {
    @EnvironmentObject var monitor: WiFiMonitor
    @State private var band: Band
    @State private var hoverFreq: Double?
    @State private var didPickBand: Bool

    init(startBand: Band? = nil) {
        _band = State(initialValue: startBand ?? .ghz5)
        _didPickBand = State(initialValue: startBand != nil)
    }

    private var bandNetworks: [ScannedNetwork] { monitor.networks.filter { $0.channel.band == band } }

    var body: some View {
        SnapshotScroll {
            VStack(spacing: 18) {
                header
                if band == .ghz6 && !(monitor.capabilities?.supports(.ghz6) ?? false) {
                    Card {
                        HStack(spacing: 12) {
                            Image(systemName: "6.circle").font(.system(size: 22)).foregroundStyle(Theme.warn)
                            Text("Этот Mac не принимает 6 ГГц, поэтому сети в этом диапазоне ему не видны, даже если они есть.")
                                .font(.system(size: 13)).foregroundStyle(Theme.text2)
                        }
                    }
                }
                spectrum
                HStack(alignment: .top, spacing: 18) {
                    loadCard
                    byChannelCard
                }
            }
            .padding(24)
        }
        .navigationTitle("Каналы")
        .onAppear {
            if !didPickBand, let b = monitor.link?.channel?.band { band = b; didPickBand = true }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            SegmentedControl(options: Band.allCases, selection: $band) { b in
                "\(b.rawValue)  \(monitor.networks.filter { $0.channel.band == b }.count)"
            }
            Spacer()
            if let d = monitor.lastScan {
                Text("обновлено в \(d.formatted(date: .omitted, time: .shortened))").font(.system(size: 12)).foregroundStyle(Theme.text3)
            }
            Button { monitor.scan() } label: {
                Label(monitor.isScanning ? "Сканирую…" : "Обновить", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.premiumSecondary)
            .disabled(monitor.isScanning)
            .help("Пересканировать эфир (≈3 секунды)")
        }
    }

    // MARK: Spectrum

    private var spectrum: some View {
        let nets = bandNetworks
        let hovered = hoverFreq.map { f in nets.filter { $0.channel.range.contains(f) }.sorted { $0.rssi > $1.rssi } } ?? []
        let labeled = labelIDs(nets)
        return Card("Спектр · \(band.rawValue)", icon: "chart.xyaxis.line", hint: Hints.spectrum,
                    trailing: AnyView(Text("сетей: \(nets.count)").font(.system(size: 12)).foregroundStyle(Theme.text3))) {
            Chart {
                ForEach(nets.sorted { ($0.isCurrent || $0.isSibling ? 1 : 0) < ($1.isCurrent || $1.isSibling ? 1 : 0) }) { n in
                    let r = n.channel.range
                    let h = Double(max(1, n.rssi + 100))
                    let edge = min(4, (r.upperBound - r.lowerBound) / 6)
                    let color = n.isCurrent || n.isSibling ? Theme.accent : Palette.network(n.id)
                    let pts: [(Double, Double)] = [(r.lowerBound, 0), (r.lowerBound + edge, h), (r.upperBound - edge, h), (r.upperBound, 0)]
                    ForEach(Array(pts.enumerated()), id: \.offset) { _, p in
                        AreaMark(x: .value("МГц", p.0), y: .value("Сила", p.1), series: .value("Сеть", n.id), stacking: .unstacked)
                            .foregroundStyle(LinearGradient(colors: [color.opacity(n.isCurrent ? 0.5 : n.isSibling ? 0.3 : 0.25), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        LineMark(x: .value("МГц", p.0), y: .value("Сила", p.1), series: .value("Сеть", n.id))
                            .foregroundStyle(color.opacity(n.isCurrent ? 1 : 0.75))
                            .lineStyle(StrokeStyle(lineWidth: n.isCurrent ? 2.5 : n.isSibling ? 1.8 : 1.2, dash: n.isSibling ? [5, 3] : []))
                    }
                    if labeled.contains(n.id) {
                        PointMark(x: .value("МГц", (r.lowerBound + r.upperBound) / 2), y: .value("Сила", h))
                            .symbolSize(0)
                            .annotation(position: .top, spacing: 3) {
                                Text(n.isCurrent ? "★ \(n.ssid ?? "Ваша сеть")" : n.isSibling ? "☆ \(n.ssid ?? "ваш роутер")" : (n.ssid ?? "канал \(n.channel.number)"))
                                    .font(.system(size: 10.5, weight: n.isCurrent ? .bold : .medium))
                                    .foregroundStyle(n.isCurrent || n.isSibling ? Theme.accent : Theme.text2)
                                    .lineLimit(1)
                            }
                    }
                }
                if let f = hoverFreq {
                    RuleMark(x: .value("МГц", f))
                        .foregroundStyle(Color.white.opacity(0.35))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            tooltip(freq: f, nets: hovered)
                        }
                }
            }
            .chartXScale(domain: band.spectrum)
            .chartYScale(domain: 0...75)
            .chartXAxis {
                AxisMarks(values: band.axisChannels.map { ChannelInfo.centerFrequency($0, band: band) }) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel {
                        if let f = v.as(Double.self), let ch = band.axisChannels.first(where: { ChannelInfo.centerFrequency($0, band: band) == f }) {
                            Text("\(ch)").foregroundStyle(band == .ghz2 && ch >= 12 ? Theme.warn : Theme.text2)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [10, 25, 40, 55, 70]) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel { if let y = v.as(Double.self) { Text("\(Int(y) - 100)").foregroundStyle(Theme.text3) } }
                }
            }
            .chartXSelection(value: $hoverFreq)
            .frame(height: 300)
            HStack(spacing: 18) {
                axisHint("arrow.left.and.right", "номер канала")
                axisHint("arrow.up.and.down", "сила сигнала, dBm")
                axisHint("cursorarrow.rays", "наведите — увидите, кто на частоте")
            }
        }
    }

    /// Labels the current network plus strong neighbours whose labels wouldn't collide.
    private func labelIDs(_ nets: [ScannedNetwork]) -> Set<String> {
        var placed: [(x: Double, y: Int)] = []
        var ids = Set<String>()
        let span = band.spectrum.upperBound - band.spectrum.lowerBound
        let hasCurrent = nets.contains(where: \.isCurrent)
        for n in nets.sorted(by: { ($0.isCurrent ? 2 : $0.isSibling ? 1 : 0, $0.rssi) > ($1.isCurrent ? 2 : $1.isSibling ? 1 : 0, $1.rssi) })
            where n.isCurrent || (n.isSibling && !hasCurrent) || (n.rssi > -72 && !n.isSibling) {
            let x = (n.channel.range.lowerBound + n.channel.range.upperBound) / 2
            if placed.contains(where: { abs($0.x - x) < span * 0.09 && abs($0.y - n.rssi) < 8 }) { continue }
            placed.append((x, n.rssi))
            ids.insert(n.id)
        }
        return ids
    }

    private func axisHint(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).foregroundStyle(Theme.text3)
            Text(text).foregroundStyle(Theme.text3)
        }
        .font(.system(size: 11))
    }

    private func tooltip(freq: Double, nets: [ScannedNetwork]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(String(format: "%.0f МГц", freq)).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text)
            if nets.isEmpty { Text("свободно — хорошее место для канала").font(.system(size: 11)).foregroundStyle(Theme.good) }
            ForEach(nets.prefix(6)) { n in
                HStack(spacing: 6) {
                    Circle().fill(n.isCurrent || n.isSibling ? Theme.accent : Palette.network(n.id)).frame(width: 7, height: 7)
                    Text(n.displayName + (n.isSibling ? " (ваш роутер)" : "")).lineLimit(1).foregroundStyle(Theme.text)
                    Spacer(minLength: 8)
                    Text("кан. \(n.channel.number) · \(n.rssi)").foregroundStyle(Theme.text3)
                }
                .font(.system(size: 11))
            }
            if nets.count > 6 { Text("и ещё \(nets.count - 6)").font(.system(size: 10)).foregroundStyle(Theme.text3) }
        }
        .padding(10)
        .frame(width: 240, alignment: .leading)
        .background(Theme.bgRaised.opacity(0.96), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke))
    }

    // MARK: Load per channel

    private var loadCard: some View {
        let caps = monitor.capabilities ?? Capabilities()
        let cur = monitor.link?.channel
        let width = band == .ghz2 ? 20 : (cur?.band == band ? max(cur!.width, 20) : 80)
        let cands = Analyzer.candidates(band: band, width: width, caps: caps, networks: monitor.networks)
        let best = cands.min { ($0.load + $0.channel.pickPenalty) < ($1.load + $1.channel.pickPenalty) }
        // When the winner is 12/13, also point at the best channel every device can see.
        let safeBest = best?.channel.isLimited2G == true ? cands.filter { !$0.channel.isLimited2G }.min { $0.load < $1.load } : nil
        let maxLoad = max(1.0, cands.map(\.load).max() ?? 1)
        return Card("Загрузка каналов · \(width) МГц", icon: "chart.bar.xaxis", hint: Hints.channelLoad) {
            if cands.isEmpty {
                Text("Нет доступных каналов в этом диапазоне").font(.system(size: 13)).foregroundStyle(Theme.text2)
            } else {
                VStack(spacing: 9) {
                    ForEach(cands) { c in
                        let isCur = cur.map { $0.band == band && c.channel.block.contains($0.number) } ?? false
                        let isBest = c.id == best?.id && !isCur
                        let isSafe = c.id == safeBest?.id && !isCur
                        let tint: Color = isCur ? Theme.accent : isBest ? Theme.good : Palette.score(1 / (1 + c.load * 0.6))
                        HStack(spacing: 10) {
                            HStack(spacing: 4) {
                                let b = c.channel.block
                                Text(b.count > 1 ? "\(b.lowerBound)–\(b.upperBound)" : "\(c.channel.number)").font(Theme.number(13, isCur || isBest ? .bold : .medium)).foregroundStyle(Theme.text)
                                if c.channel.isDFS { Text("DFS").font(.system(size: 8.5, weight: .bold)).foregroundStyle(Theme.warn) }
                                if c.channel.isLimited2G {
                                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9)).foregroundStyle(Theme.warn)
                                        .help(ChannelInfo.limited2GNote)
                                }
                            }
                            .frame(width: 92, alignment: .leading)
                            GaugeBar(value: c.load / maxLoad, tint: tint, height: 8)
                            Text(String(format: "%.1f", c.load)).font(Theme.number(11.5, .medium)).foregroundStyle(Theme.text2).frame(width: 28, alignment: .trailing)
                            Group {
                                if isCur { Badge(text: "ваш", tint: Theme.accent) }
                                else if isBest { Badge(text: "лучший", icon: "star.fill", tint: Theme.good) }
                                else if isSafe { Badge(text: "для всех", icon: "checkmark", tint: Theme.cyan).help("Лучший из каналов, которые видят все устройства") }
                                else { Text(c.networks == 0 ? "пусто" : "сетей: \(c.networks)").font(.system(size: 11)).foregroundStyle(Theme.text3) }
                            }
                            .fixedSize()
                            .frame(width: 84, alignment: .leading)
                        }
                        .help(isCur ? "Канал, на котором сейчас ваш роутер" : isBest ? "Наименее загруженный канал — выберите его в настройках роутера" : "Давление соседей на этом канале")
                    }
                }
                Text("0 — канал свободен, 1 — как одна сильная сеть прямо на нём. DFS‑каналы чуть штрафуются: на них роутер может уходить из‑за радаров." + (band == .ghz2 ? " ⚠ — " + ChannelInfo.limited2GNote : ""))
                    .font(.system(size: 11.5)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var byChannelCard: some View {
        let groups = Dictionary(grouping: bandNetworks) { $0.channel.number }.sorted { $0.key < $1.key }
        return Card("Соседи по каналам", icon: "list.bullet.rectangle") {
            if groups.isEmpty {
                Text(monitor.isScanning ? "Сканирую…" : "Сетей не найдено").font(.system(size: 13)).foregroundStyle(Theme.text2)
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(groups, id: \.key) { ch, nets in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text("Канал \(ch)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                            if ChannelInfo(number: ch, band: band, width: 20).isDFS { Badge(text: "DFS", tint: Theme.warn) }
                            if ChannelInfo(number: ch, band: band, width: 20).isLimited2G {
                                Badge(text: "не все устройства", icon: "exclamationmark.triangle.fill", tint: Theme.warn).help(ChannelInfo.limited2GNote)
                            }
                            Spacer()
                            Text("\(nets.count)").font(Theme.number(12)).foregroundStyle(Theme.text3)
                        }
                        ForEach(nets.sorted { $0.rssi > $1.rssi }) { n in
                            HStack(spacing: 8) {
                                SignalBars(rssi: n.rssi)
                                Text(n.isSibling && n.ssid == nil ? "Доп. сеть вашего роутера" : n.displayName).lineLimit(1).fontWeight(n.isCurrent ? .bold : .regular)
                                    .foregroundStyle(n.isCurrent ? Theme.accent : n.isSibling ? Theme.text2 : Theme.text)
                                if n.isSibling { Badge(text: "ваш роутер", tint: Theme.accent).help("Другой диапазон или гостевая сеть вашего роутера — не считается помехой") }
                                Spacer()
                                Text("\(n.channel.width) МГц · \(n.rssi) dBm").font(.system(size: 11.5).monospacedDigit()).foregroundStyle(Theme.text3)
                            }
                            .font(.system(size: 13))
                        }
                    }
                    if ch != groups.last?.key { Divider().overlay(Theme.stroke) }
                }
            }
        }
    }
}
