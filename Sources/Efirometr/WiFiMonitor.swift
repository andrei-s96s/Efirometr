import Foundation
import CoreWLAN
import CoreLocation
import SwiftUI

@MainActor
final class WiFiMonitor: NSObject, ObservableObject {
    /// Slow-changing link snapshot: republished every 5 s or on a significant change (band, channel, AP…).
    /// Live per-second values live in `LiveData`.
    @Published private(set) var link: LinkSnapshot?
    @Published private(set) var networks: [ScannedNetwork] = []
    /// Networks merged by name: one entry per SSID with all its radios (2.4/5/6 GHz, mesh nodes).
    @Published private(set) var groups: [NetworkGroup] = []
    @Published private(set) var isScanning = false
    @Published private(set) var lastScan: Date?
    @Published private(set) var scanError: String?
    @Published private(set) var capabilities: Capabilities?
    @Published private(set) var latency: [LatencyResult] = []
    @Published private(set) var isTestingLatency = false
    @Published private(set) var locationAuthorized = false
    @Published private(set) var assessment: Assessment = .empty

    private let client = CWWiFiClient.shared()
    private let location = CLLocationManager()
    private var timer: Timer?
    private var tick = 0
    private var lastCounters: (rx: UInt64, tx: UInt64, at: Date)?

    let live = LiveData.shared
    var downRate: Double { live.downRate }
    var upRate: Double { live.upRate }

    // Background health tracking for the journal and notifications.
    private var prevLink: LinkSnapshot?
    private var weakSince: Date?
    private var weakReported = false
    private var lossStreak = 0
    private var lossReported = false
    private var pingInFlight = false
    private var windowPings: [Double] = []
    private var windowLost = false
    private var windowDown = 0.0
    private var windowUp = 0.0
    private var windowN = 0

    var interfaceName: String { client.interface()?.interfaceName ?? "en0" }

    func start() {
        guard timer == nil else { return }
        location.delegate = self
        updateAuthorization()
        if location.authorizationStatus == .notDetermined { location.requestWhenInUseAuthorization() }

        loadCapabilities()
        refreshLink()
        sampleThroughput()
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onTick() }
        }
    }

    private func onTick() {
        tick += 1
        refreshLink()
        sampleThroughput()
        windowDown += downRate
        windowUp += upRate
        windowN += 1
        if tick % 60 == 0 { scan() }
        let settings = AppSettings.shared
        if tick % 30 == 0 { settings.refreshPowerSource() }
        if settings.journalActive {
            if tick % 5 == 0 && settings.backgroundPing { backgroundPing() }
            if tick % 10 == 0 { recordJournal() }
        } else if windowN >= 10 {
            resetWindow()
        }
    }

    // MARK: - Journal & events

    private func backgroundPing() {
        guard !pingInFlight, link?.isConnected == true, let gw = capabilities?.gateway else { return }
        pingInFlight = true
        Task {
            let ms = await Task.detached { () -> Double? in
                let out = String(decoding: SystemInfo.run("/sbin/ping", ["-c", "1", "-t", "2", gw]), as: UTF8.self)
                guard let r = out.range(of: "time=") else { return nil }
                return Double(out[r.upperBound...].prefix { "0123456789.".contains($0) })
            }.value
            pingInFlight = false
            handlePing(ms)
        }
    }

    private func handlePing(_ ms: Double?) {
        if let ms {
            windowPings.append(ms)
            if lossReported { Journal.shared.add(.lossRecovered, String(format: "Роутер снова отвечает (%.0f мс)", ms)) }
            lossStreak = 0
            lossReported = false
        } else {
            windowLost = true
            lossStreak += 1
            if lossStreak >= 3 && !lossReported {
                lossReported = true
                Journal.shared.add(.loss, "Роутер не ответил на 3 пинга подряд")
            }
        }
    }

    private func recordJournal() {
        let l = link?.isConnected == true ? link : nil
        let pings = windowPings.sorted()
        Journal.shared.add(sample: JournalSample(
            t: .now, rssi: l?.rssi, noise: l?.noise, rate: l?.txRate,
            ping: pings.isEmpty ? nil : pings[pings.count / 2], lost: windowLost,
            down: windowN > 0 ? windowDown / Double(windowN) : 0, up: windowN > 0 ? windowUp / Double(windowN) : 0))
        resetWindow()
    }

    private func resetWindow() {
        windowPings = []
        windowLost = false
        windowDown = 0
        windowUp = 0
        windowN = 0
    }

    private func detectEvents(_ s: LinkSnapshot) {
        defer { prevLink = s }
        guard let p = prevLink else { return }
        let j = Journal.shared
        if p.isConnected && !s.isConnected {
            j.add(.disconnect, "Wi‑Fi отключился" + (p.ssid.map { " от «\($0)»" } ?? ""))
            return
        }
        if !p.isConnected && s.isConnected {
            j.add(.reconnect, "Подключено" + (s.ssid.map { " к «\($0)»" } ?? "") + " · \(s.channel?.band.rawValue ?? "") · \(s.rssi) dBm")
            return
        }
        guard p.isConnected, s.isConnected, let pc = p.channel, let sc = s.channel else { return }
        if pc.band != sc.band {
            j.add(.bandChange, "Диапазон: \(pc.band.rawValue) → \(sc.band.rawValue)")
        } else if pc.number != sc.number {
            j.add(.channelChange, "Канал роутера: \(pc.number) → \(sc.number)")
        }
        if let a = p.bssid, let b = s.bssid, a != b {
            j.add(.roam, "Переход на другую точку доступа (\(b))")
        }
        let threshold = AppSettings.shared.signalThreshold
        if s.rssi < threshold {
            if weakSince == nil { weakSince = .now }
            if !weakReported, let since = weakSince, Date().timeIntervalSince(since) >= 15 {
                weakReported = true
                j.add(.weakSignal, "Сигнал \(s.rssi) dBm — ниже порога \(threshold) dBm")
            }
        } else if s.rssi >= threshold + 3 {
            if weakReported { j.add(.signalRecovered, "Сигнал восстановился: \(s.rssi) dBm") }
            weakSince = nil
            weakReported = false
        }
    }

    // MARK: - Link

    func refreshLink() {
        guard let iface = client.interface() else {
            if link != nil { link = nil; live.link = nil; reassess() }
            return
        }
        let snap = LinkSnapshot(
            interfaceName: iface.interfaceName ?? "en0",
            ssid: iface.ssid(),
            bssid: iface.bssid(),
            rssi: iface.rssiValue(),
            noise: iface.noiseMeasurement(),
            txRate: iface.transmitRate(),
            channel: ChannelInfo(iface.wlanChannel()),
            phy: iface.activePHYMode(),
            security: SecurityKind(iface.security()),
            countryCode: iface.countryCode(),
            txPower: iface.transmitPower(),
            powerOn: iface.powerOn()
        )
        detectEvents(snap)
        live.link = snap
        if snap.isConnected {
            live.append(SignalSample(date: .now, rssi: snap.rssi, noise: snap.noise, rate: snap.txRate))
        }
        if let cc = snap.countryCode, !cc.isEmpty, capabilities?.countryCode != cc { capabilities?.countryCode = cc }
        if link == nil || tick % 5 == 0 || significantChange(from: link!, to: snap) {
            link = snap
            reassess()
        }
    }

    private func significantChange(from a: LinkSnapshot, to b: LinkSnapshot) -> Bool {
        a.isConnected != b.isConnected || a.ssid != b.ssid || a.bssid != b.bssid || a.channel != b.channel
            || a.phy != b.phy || a.security != b.security || a.powerOn != b.powerOn
    }

    private func sampleThroughput() {
        guard let c = InterfaceCounters.bytes(for: interfaceName) else { return }
        let now = Date()
        if let last = lastCounters {
            let dt = now.timeIntervalSince(last.at)
            if dt > 0.2 {
                // Counters are monotonic; a reset (interface down/up) yields a negative delta which we drop.
                let down = c.rx >= last.rx ? Double(c.rx - last.rx) / dt : 0
                let up = c.tx >= last.tx ? Double(c.tx - last.tx) / dt : 0
                live.downRate = down
                live.upRate = up
                live.append(ThroughputSample(date: now, down: down, up: up))
            }
        }
        lastCounters = (c.rx, c.tx, now)
    }

    // MARK: - Capabilities

    private func loadCapabilities() {
        var caps = Capabilities()
        if let iface = client.interface() {
            var byBand: [Band: Set<Int>] = [:]
            var maxWidth = 20
            for ch in iface.supportedWLANChannels() ?? [] {
                guard let info = ChannelInfo(ch) else { continue }
                byBand[info.band, default: []].insert(info.number)
                maxWidth = max(maxWidth, info.width)
            }
            caps.channels = byBand.mapValues { $0.sorted() }
            caps.maxWidth = maxWidth
            caps.countryCode = iface.countryCode() ?? ""
        }
        capabilities = caps
        Task.detached(priority: .utility) {
            var extended = caps
            SystemInfo.load(into: &extended)
            await MainActor.run { [extended] in
                self.capabilities = extended
                self.reassess()
            }
        }
    }

    // MARK: - Scan

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        let currentBSSID = link?.bssid
        let currentChannel = link?.channel
        let currentSSID = link?.ssid
        Task.detached(priority: .userInitiated) {
            var result: [ScannedNetwork] = []
            var error: String?
            do {
                let found = try CWWiFiClient.shared().interface()?.scanForNetworks(withName: nil, includeHidden: true) ?? []
                for n in found {
                    guard let ch = ChannelInfo(n.wlanChannel) else { continue }
                    let phy = PHY.descending.first { n.supportsPHYMode($0) } ?? .modeNone
                    let isCurrent: Bool
                    if let b = currentBSSID, let nb = n.bssid { isCurrent = b == nb }
                    else { isCurrent = currentChannel?.number == ch.number && currentSSID != nil && currentSSID == n.ssid }
                    result.append(ScannedNetwork(id: n.bssid ?? UUID().uuidString, ssid: n.ssid, bssid: n.bssid, rssi: n.rssiValue,
                                                 noise: n.noiseMeasurement, channel: ch, phy: phy,
                                                 security: SecurityKind(network: n), isCurrent: isCurrent))
                }
            } catch let e {
                error = e.localizedDescription
            }
            // CoreWLAN may return one BSSID several times (entries differing only in IEs): keep the strongest.
            var byBSSID: [String: ScannedNetwork] = [:]
            var noBSSID: [ScannedNetwork] = []
            for n in result {
                guard let b = n.bssid else { noBSSID.append(n); continue }
                if byBSSID[b].map({ $0.rssi < n.rssi || n.isCurrent }) ?? true { byBSSID[b] = n }
            }
            let sorted = (Array(byBSSID.values) + noBSSID).sorted { $0.rssi > $1.rssi }
            await MainActor.run { [sorted, error] in
                self.finishScan(sorted, error: error)
            }
        }
    }

    private func finishScan(_ found: [ScannedNetwork], error: String?) {
        isScanning = false
        scanError = error
        if error == nil {
            var list = found
            // Without location access BSSIDs are hidden; mark the strongest network on our channel as ours.
            if !list.contains(where: \.isCurrent), let ch = link?.channel,
               let i = list.firstIndex(where: { $0.channel.number == ch.number && abs($0.rssi - (link?.rssi ?? 0)) <= 6 }) {
                list[i].isCurrent = true
            }
            if let me = list.first(where: \.isCurrent) {
                for i in list.indices where !list[i].isCurrent {
                    list[i].isSibling = WiFiMonitor.sameRadio(me, list[i]) || WiFiMonitor.sameRouter(me, list[i])
                }
            }
            networks = list
            groups = NetworkGroup.make(list)
            lastScan = .now
        }
        reassess()
    }

    /// Same AP radio: BSSIDs differ only in the first/last octet (virtual interfaces),
    /// or — when BSSIDs are hidden — identical channel, width and near-identical signal.
    nonisolated static func sameRadio(_ a: ScannedNetwork, _ b: ScannedNetwork) -> Bool {
        guard a.channel.band == b.channel.band, a.channel.number == b.channel.number else { return false }
        if let x = a.bssid?.split(separator: ":"), let y = b.bssid?.split(separator: ":"), x.count == 6, y.count == 6 {
            return x[1...4] == y[1...4]
        }
        return a.channel.width == b.channel.width && abs(a.rssi - b.rssi) <= 3
    }

    /// Same router on any band: same network name, or BSSIDs from one device (adjacent MACs).
    nonisolated static func sameRouter(_ a: ScannedNetwork, _ b: ScannedNetwork) -> Bool {
        if let s = a.ssid, !s.isEmpty, s == b.ssid { return true }
        if let x = a.bssid?.split(separator: ":"), let y = b.bssid?.split(separator: ":"), x.count == 6, y.count == 6 {
            return x[1...4] == y[1...4]
        }
        return false
    }

    // MARK: - Latency

    func testLatency() {
        guard !isTestingLatency else { return }
        isTestingLatency = true
        Task {
            let gateway = await Task.detached { SystemInfo.defaultGateway() }.value
            async let gw: LatencyResult? = gateway != nil ? Pinger.run(label: "Роутер", host: gateway!) : nil
            async let inet = Pinger.run(label: "Интернет", host: "1.1.1.1")
            let results = await [gw, inet].compactMap { $0 }
            latency = results
            isTestingLatency = false
            reassess()
        }
    }

    // MARK: -

    private func reassess() {
        assessment = Analyzer.assess(link: link, networks: networks, caps: capabilities, latency: latency, locationAuthorized: locationAuthorized)
    }

    private func updateAuthorization() {
        let s = location.authorizationStatus
        locationAuthorized = s == .authorizedAlways || s == .authorized
    }

    func openLocationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }
}

extension WiFiMonitor: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let was = self.locationAuthorized
            self.updateAuthorization()
            if !was && self.locationAuthorized {
                self.refreshLink()
                self.scan()
            }
        }
    }
}


// MARK: - Demo data (README screenshots: fictional networks, no real SSIDs/MACs)

extension WiFiMonitor {
    func loadDemo() {
        var caps = Capabilities()
        caps.macName = "MacBook Pro"; caps.macModel = "Mac15,7"; caps.chip = "Apple M3 Pro"
        caps.cardType = "(0x14E4, 0x4388)"; caps.firmware = "demo"; caps.phyModes = "802.11 a/b/g/n/ac/ax"
        caps.countryCode = "EU"; caps.maxWidth = 160; caps.gateway = "192.168.1.1"
        caps.channels = [.ghz2: Array(1...13), .ghz5: [36, 40, 44, 48, 52, 56, 60, 64, 100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144, 149, 153, 157, 161, 165],
                         .ghz6: stride(from: 1, through: 233, by: 4).map { $0 }]
        capabilities = caps

        func net(_ ssid: String?, _ mac: String, _ band: Band, _ ch: Int, _ w: Int, _ rssi: Int, _ phy: CWPHYMode, _ sec: SecurityKind,
                 current: Bool = false, sibling: Bool = false) -> ScannedNetwork {
            var n = ScannedNetwork(id: mac, ssid: ssid, bssid: mac, rssi: rssi, noise: -92, channel: ChannelInfo(number: ch, band: band, width: w),
                                   phy: phy, security: sec, isCurrent: current)
            n.isSibling = sibling
            return n
        }
        let list = [
            net("Home", "a4:2b:b0:5e:10:34", .ghz5, 36, 160, -52, .mode11ax, .wpa3Transition, current: true),
            net("Home", "a4:2b:b0:5e:10:30", .ghz2, 6, 20, -47, .mode11ax, .wpa3Transition, sibling: true),
            net("Home-Guest", "a6:2b:b0:5e:10:31", .ghz2, 6, 20, -48, .mode11ax, .wpa2, sibling: true),
            net("Kvartira-42", "3c:84:6a:21:77:01", .ghz2, 1, 20, -61, .mode11n, .wpa2),
            net("Kvartira-42", "3c:84:6a:21:77:05", .ghz5, 100, 80, -74, .mode11ac, .wpa2),
            net("Lena_Home", "d8:07:b6:aa:01:12", .ghz2, 11, 20, -58, .mode11n, .wpa2),
            net("Office-5G", "f0:9f:c2:33:44:55", .ghz5, 44, 80, -78, .mode11ax, .wpa3),
            net("Sosedi", "00:1a:2b:3c:4d:5e", .ghz2, 6, 40, -69, .mode11n, .wpa2),
            net("Printer-Direct", "02:1a:2b:aa:bb:cc", .ghz2, 13, 20, -80, .mode11g, .wpa),
            net("Cafe Free", "9c:5c:8e:10:20:30", .ghz2, 1, 20, -83, .mode11n, .open),
            net("Neighbor-6E", "7c:10:c9:01:02:03", .ghz6, 37, 160, -79, .mode11ax, .wpa3),
            net(nil, "12:34:56:78:9a:bc", .ghz5, 149, 80, -86, .mode11ac, .wpa2),
        ]
        networks = list
        groups = NetworkGroup.make(list)
        lastScan = .now
        locationAuthorized = true
        latency = [LatencyResult(label: "Роутер", host: "192.168.1.1", avg: 3.2, min: 2.1, max: 9.8, jitter: 1.4, loss: 0),
                   LatencyResult(label: "Интернет", host: "1.1.1.1", avg: 17.6, min: 14.2, max: 31.0, jitter: 3.1, loss: 0)]
        let snap = LinkSnapshot(interfaceName: "en0", ssid: "Home", bssid: "a4:2b:b0:5e:10:34", rssi: -52, noise: -92, txRate: 1201,
                                channel: ChannelInfo(number: 36, band: .ghz5, width: 160), phy: .mode11ax, security: .wpa3Transition,
                                countryCode: "EU", txPower: 63, powerOn: true)
        link = snap
        live.link = snap
        let now = Date()
        for i in 0..<LiveData.capacity {
            let t = now.addingTimeInterval(Double(i - LiveData.capacity))
            let x = Double(i)
            live.append(SignalSample(date: t, rssi: -52 + Int((sin(x / 9) * 3).rounded()), noise: -92 + Int((cos(x / 5) * 1.5).rounded()), rate: 1201))
            let burst = max(0, sin(x / 14)) * 38e6 + 1.5e6
            live.append(ThroughputSample(date: t, down: burst / 8 * (1 + 0.25 * sin(x / 2)), up: burst / 8 * 0.18))
        }
        live.downRate = 31e6 / 8
        live.upRate = 4.2e6 / 8
        reassess()
    }
}
