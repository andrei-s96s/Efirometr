import SwiftUI

enum NetworkSort: String, CaseIterable, Identifiable {
    case signal = "Сигнал"
    case name = "Имя"
    case channel = "Канал"

    var id: String { rawValue }
}

/// Compact two-line list of networks — fits the window width, no horizontal scrolling.
struct NetworksView: View {
    @EnvironmentObject var monitor: WiFiMonitor
    @State private var search = ""
    @State private var bandFilter = "all"
    @State private var sort: NetworkSort = .signal
    @State private var expanded: Set<String> = []
    @Environment(\.snapshotMode) private var snapshot

    private var groups: [NetworkGroup] {
        let filtered = monitor.groups
            .filter { g in bandFilter == "all" || g.bands.contains { $0.rawValue == bandFilter } }
            .filter { g in search.isEmpty || g.displayName.localizedCaseInsensitiveContains(search)
                || g.radios.contains { ($0.bssid ?? "").contains(search.lowercased()) } }
        let sorted: [NetworkGroup]
        switch sort {
        case .signal: sorted = filtered.sorted { $0.best.rssi > $1.best.rssi }
        case .name: sorted = filtered.sorted { ($0.ssid == nil ? 1 : 0, $0.displayName.lowercased()) < ($1.ssid == nil ? 1 : 0, $1.displayName.lowercased()) }
        case .channel: sorted = filtered.sorted { ($0.best.channel.band.order, $0.best.channel.number) < ($1.best.channel.band.order, $1.best.channel.number) }
        }
        // Your own network always on top.
        return sorted.filter(\.isMine) + sorted.filter { !$0.isMine }
    }

    var body: some View {
        let groups = groups
        SnapshotScroll {
            VStack(spacing: 14) {
                controls(count: groups.count)
                if monitor.networks.isEmpty {
                    Card {
                        HStack(spacing: 10) {
                            if monitor.isScanning { ProgressView().controlSize(.small) }
                            Text(monitor.isScanning ? "Сканирую эфир…" : "Сетей не найдено").foregroundStyle(Theme.text2)
                        }
                    }
                }
                LazyVStack(spacing: 8) {
                    ForEach(groups) { g in
                        NetworkCard(group: g, expanded: expanded.contains(g.id) || (snapshot && g.isMine)) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                if expanded.contains(g.id) { expanded.remove(g.id) } else { expanded.insert(g.id) }
                            }
                        }
                    }
                }
                if !monitor.locationAuthorized && !monitor.networks.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "location.slash").foregroundStyle(Theme.warn)
                        Text("Имена сетей скрыты: разрешите приложению доступ к геолокации, тогда сети одного роутера объединятся в одну строку.")
                            .font(.system(size: 12)).foregroundStyle(Theme.text2)
                        Button("Открыть настройки") { monitor.openLocationSettings() }.buttonStyle(.premiumSecondary)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Сети")
        .onAppear {
            if let mine = monitor.groups.first(where: \.isMine), mine.radios.count > 1 { expanded.insert(mine.id) }
        }
    }

    private func controls(count: Int) -> some View {
        HStack(spacing: 12) {
            SegmentedControl(options: ["all"] + Band.allCases.map(\.rawValue), selection: $bandFilter) { $0 == "all" ? "Все" : $0 }
            SegmentedControl(options: NetworkSort.allCases, selection: $sort) { $0.rawValue }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.text3)
                TextField("Поиск по имени или BSSID", text: $search).textFieldStyle(.plain).font(.system(size: 12.5))
                if !search.isEmpty {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.text3).onTapGesture { search = "" }
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.white.opacity(0.05), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.stroke))
            .frame(minWidth: 160, maxWidth: 260)
            Spacer(minLength: 0)
            Text("\(count) сетей · \(monitor.networks.count) BSSID").font(.system(size: 11.5)).foregroundStyle(Theme.text3).fixedSize()
            Button { monitor.scan() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.premiumSecondary)
                .disabled(monitor.isScanning)
                .help("Пересканировать эфир")
        }
    }
}

struct NetworkCard: View {
    let group: NetworkGroup
    let expanded: Bool
    let toggle: () -> Void
    @State private var hover = false

    var body: some View {
        let best = group.best
        VStack(alignment: .leading, spacing: 0) {
            // Line 1: name, status, signal
            HStack(spacing: 10) {
                SignalBars(rssi: best.rssi)
                Text(group.displayName)
                    .font(.system(size: 14, weight: group.isMine ? .semibold : .medium))
                    .foregroundStyle(group.ssid == nil ? Theme.text2 : Theme.text)
                    .lineLimit(1)
                if group.isCurrent { Badge(text: "подключено", icon: "checkmark", tint: Theme.good) }
                else if group.isMine { Badge(text: "ваш роутер", tint: Theme.accent) }
                Spacer(minLength: 8)
                Text("\(best.rssi)").font(Theme.number(15)).foregroundStyle(Palette.rssi(best.rssi))
                + Text(" dBm").font(.system(size: 11)).foregroundStyle(Theme.text3)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.text3)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }
            // Line 2: one chip per band + standard, security, APs
            HStack(spacing: 6) {
                ForEach(group.bands) { b in bandChip(b) }
                Spacer(minLength: 8)
                meta(PHY.label(group.bestPHY), color: Theme.text2).help(PHY.explain(group.bestPHY))
                dot
                meta(group.weakestSecurity.name, color: group.weakestSecurity.score < 0.5 ? Theme.warn : Theme.text2,
                     icon: group.weakestSecurity.score < 0.5 ? "lock.open" : "lock.fill")
                if group.accessPoints > 1 {
                    dot
                    meta("точек: \(group.accessPoints)", color: Theme.text2, icon: "point.3.connected.trianglepath.dotted")
                }
            }
            .padding(.top, 7)
            .padding(.leading, 28)

            if expanded {
                VStack(spacing: 6) {
                    ForEach(group.bands) { b in bandRow(b) }
                    if group.bands.contains(where: { b in group.radios.filter { $0.channel.band == b }.count > 1 }) && group.accessPoints == 1 {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle").foregroundStyle(Theme.accent)
                            Text("Роутер вещает эту сеть с нескольких MAC‑адресов в одном диапазоне — это виртуальные точки (mesh, гостевой режим или WPA2/WPA3). Физически это один радиомодуль, так и должно быть.")
                                .foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.system(size: 11.5))
                        .padding(.top, 2)
                    }
                }
                .padding(.top, 10)
                .padding(.leading, 28)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(group.isMine ? Theme.accent.opacity(0.07) : Color.white.opacity(hover ? 0.05 : 0.03),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(group.isMine ? Theme.accent.opacity(0.35) : Theme.stroke))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture(perform: toggle)
        .help("Нажмите, чтобы показать диапазоны и MAC‑адреса")
    }

    private var dot: some View { Text("·").foregroundStyle(Theme.text3) }

    private func meta(_ text: String, color: Color, icon: String? = nil) -> some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 9.5)) }
            Text(text)
        }
        .font(.system(size: 11.5))
        .foregroundStyle(color)
        .lineLimit(1)
    }

    private func bandChip(_ b: Band) -> some View {
        let radios = group.radios.filter { $0.channel.band == b }
        let channels = Array(Set(radios.map(\.channel.number))).sorted()
        let widths = Array(Set(radios.map(\.channel.width))).sorted()
        let tint = Self.color(b)
        return HStack(spacing: 5) {
            Text(b.rawValue).font(.system(size: 11, weight: .semibold))
            Text("кан. " + channels.map(String.init).joined(separator: ", ")).font(.system(size: 11).monospacedDigit())
            Text(widths.map(String.init).joined(separator: "/") + " МГц").font(.system(size: 11)).opacity(0.75)
            if radios.contains(where: { $0.channel.isDFS }) { Text("DFS").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.warn) }
            if radios.contains(where: { $0.channel.isLimited2G }) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9)).foregroundStyle(Theme.warn)
            }
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.25)))
        .lineLimit(1)
        .fixedSize()
        .help(radios.contains(where: { $0.channel.isLimited2G }) ? ChannelInfo.limited2GNote : b.rawValue)
    }

    /// One line per band; several BSSIDs of the same band are listed inside it.
    private func bandRow(_ b: Band) -> some View {
        let radios = group.radios.filter { $0.channel.band == b }.sorted { $0.rssi > $1.rssi }
        let best = radios[0]
        let channels = Array(Set(radios.map(\.channel.number))).sorted().map(String.init).joined(separator: ", ")
        let widths = Array(Set(radios.map(\.channel.width))).sorted().map(String.init).joined(separator: "/")
        let bssids = radios.compactMap(\.bssid)
        return HStack(alignment: .top, spacing: 10) {
            Circle().fill(Self.color(b)).frame(width: 6, height: 6).padding(.top, 5)
            Text(b.rawValue).frame(width: 52, alignment: .leading).foregroundStyle(Theme.text)
            Text("кан. \(channels) · \(widths) МГц").frame(width: 130, alignment: .leading)
            Text("\(best.rssi) dBm").foregroundStyle(Palette.rssi(best.rssi)).frame(width: 64, alignment: .leading)
            Text(PHY.label(best.phy)).frame(width: 84, alignment: .leading).help(PHY.explain(best.phy))
            VStack(alignment: .leading, spacing: 2) {
                if bssids.isEmpty {
                    Text("BSSID скрыт").foregroundStyle(Theme.text3)
                } else {
                    ForEach(bssids, id: \.self) { m in
                        Text(m).font(.system(size: 11).monospaced()).foregroundStyle(Theme.text3)
                    }
                }
            }
            .help(bssids.count > 1 ? "Несколько MAC‑адресов в одном диапазоне — виртуальные точки одного радиомодуля" : "MAC‑адрес точки доступа")
            Spacer(minLength: 0)
            if radios.contains(where: \.isCurrent) { Text("вы здесь").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.good) }
        }
        .font(.system(size: 11.5).monospacedDigit())
        .foregroundStyle(Theme.text2)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
    }

    static func color(_ b: Band) -> Color {
        switch b {
        case .ghz2: return Theme.warn
        case .ghz5: return Theme.cyan
        case .ghz6: return Theme.violet
        }
    }
}
