import Foundation
import CoreWLAN

enum Band: String, CaseIterable, Identifiable, Hashable {
    case ghz2 = "2,4 ГГц"
    case ghz5 = "5 ГГц"
    case ghz6 = "6 ГГц"

    var id: String { rawValue }

    init?(_ band: CWChannelBand) {
        switch band {
        case .band2GHz: self = .ghz2
        case .band5GHz: self = .ghz5
        case .band6GHz: self = .ghz6
        default: return nil
        }
    }

    /// Visible spectrum for the channel map, MHz.
    var spectrum: ClosedRange<Double> {
        switch self {
        case .ghz2: return 2395...2490
        case .ghz5: return 5160...5845
        case .ghz6: return 5945...7125
        }
    }

    /// Channels used as axis labels on the channel map.
    var axisChannels: [Int] {
        switch self {
        case .ghz2: return Array(1...13)
        case .ghz5: return [36, 52, 64, 100, 116, 132, 144, 149, 165]
        case .ghz6: return stride(from: 1, through: 233, by: 32).map { $0 }
        }
    }
}

struct ChannelInfo: Hashable {
    let number: Int
    let band: Band
    let width: Int

    init(number: Int, band: Band, width: Int) {
        self.number = number
        self.band = band
        self.width = width
    }

    init?(_ channel: CWChannel?) {
        guard let channel, let band = Band(channel.channelBand) else { return nil }
        self.init(number: channel.channelNumber, band: band, width: ChannelInfo.mhz(channel.channelWidth))
    }

    static func mhz(_ width: CWChannelWidth) -> Int {
        switch width {
        case .width20MHz: return 20
        case .width40MHz: return 40
        case .width80MHz: return 80
        case .width160MHz: return 160
        default: return 20
        }
    }

    static func centerFrequency(_ channel: Int, band: Band) -> Double {
        switch band {
        case .ghz2: return channel == 14 ? 2484 : Double(2407 + 5 * channel)
        case .ghz5: return Double(5000 + 5 * channel)
        case .ghz6: return Double(5950 + 5 * channel)
        }
    }

    var centerFrequency: Double { ChannelInfo.centerFrequency(number, band: band) }

    /// First and last 20 MHz sub-channel of the bonded block this channel belongs to.
    var block: ClosedRange<Int> {
        guard band != .ghz2 else { return number...number }
        let n = max(1, width / 20)
        let base = band == .ghz6 ? 1 : (number >= 149 ? 149 : 36)
        let step = 4 * n
        let start = base + max(0, (number - base) / step) * step
        return start...(start + 4 * (n - 1))
    }

    /// Occupied spectrum, MHz, with channel bonding taken into account.
    var range: ClosedRange<Double> {
        switch band {
        case .ghz2:
            let c = centerFrequency
            if width >= 40 { return number <= 7 ? (c - 10)...(c + 30) : (c - 30)...(c + 10) }
            return (c - 11)...(c + 11)
        case .ghz5, .ghz6:
            let b = block
            return (ChannelInfo.centerFrequency(b.lowerBound, band: band) - 10)...(ChannelInfo.centerFrequency(b.upperBound, band: band) + 10)
        }
    }

    /// Share of `other`'s spectrum that overlaps this channel (0...1).
    func overlap(with other: ChannelInfo) -> Double {
        guard band == other.band else { return 0 }
        let lo = max(range.lowerBound, other.range.lowerBound)
        let hi = min(range.upperBound, other.range.upperBound)
        guard hi > lo else { return 0 }
        let narrow = min(range.upperBound - range.lowerBound, other.range.upperBound - other.range.lowerBound)
        return min(1, (hi - lo) / narrow)
    }

    var isDFS: Bool { band == .ghz5 && (52...144).contains(number) }

    /// 2.4 GHz channels 12–13: allowed in Europe/BY, but devices made for the US market only scan 1–11.
    var isLimited2G: Bool { band == .ghz2 && number >= 12 }

    /// Extra cost when recommending a channel: DFS may hop away on radar, 12–13 lock out some devices.
    var pickPenalty: Double { isDFS ? 0.15 : isLimited2G ? 0.5 : 0 }

    static let limited2GNote = "Каналы 12–13 не видят устройства для рынка США и часть старой техники (некоторые ноутбуки, принтеры, умные лампы и розетки)."

    var title: String { "\(number) · \(band.rawValue) · \(width) МГц" }
}

enum PHY {
    static func name(_ mode: CWPHYMode) -> String {
        switch mode {
        case .mode11be: return "Wi‑Fi 7"
        case .mode11ax: return "Wi‑Fi 6"
        case .mode11ac: return "Wi‑Fi 5"
        case .mode11n: return "Wi‑Fi 4"
        case .mode11a: return "802.11a"
        case .mode11g: return "802.11g"
        case .mode11b: return "802.11b"
        default: return "—"
        }
    }

    static func standard(_ mode: CWPHYMode) -> String {
        switch mode {
        case .mode11be: return "802.11be"
        case .mode11ax: return "802.11ax"
        case .mode11ac: return "802.11ac"
        case .mode11n: return "802.11n"
        case .mode11a: return "802.11a"
        case .mode11g: return "802.11g"
        case .mode11b: return "802.11b"
        default: return "—"
        }
    }

    static func rank(_ mode: CWPHYMode) -> Int {
        switch mode {
        case .mode11be: return 7
        case .mode11ax: return 6
        case .mode11ac: return 5
        case .mode11n: return 4
        case .mode11a, .mode11g: return 3
        case .mode11b: return 2
        default: return 0
        }
    }

    static let descending: [CWPHYMode] = [.mode11be, .mode11ax, .mode11ac, .mode11n, .mode11a, .mode11g, .mode11b]
}

enum SecurityKind: Int, Comparable {
    case open, wep, wpa, wpa2, wpa3Transition, wpa3, enterprise, unknown

    static func < (a: SecurityKind, b: SecurityKind) -> Bool { a.rawValue < b.rawValue }

    init(_ security: CWSecurity) {
        switch security {
        case .none, .OWE, .oweTransition: self = .open
        case .WEP, .dynamicWEP: self = .wep
        case .wpaPersonal, .wpaPersonalMixed, .wpaEnterprise, .wpaEnterpriseMixed: self = .wpa
        case .wpa2Personal, .personal: self = .wpa2
        case .wpa3Transition: self = .wpa3Transition
        case .wpa3Personal: self = .wpa3
        case .wpa2Enterprise, .wpa3Enterprise, .enterprise: self = .enterprise
        default: self = .unknown
        }
    }

    /// Best security a scanned network advertises.
    init(network: CWNetwork) {
        if network.supportsSecurity(.wpa3Enterprise) || network.supportsSecurity(.wpa2Enterprise) { self = .enterprise }
        else if network.supportsSecurity(.wpa3Personal) && network.supportsSecurity(.wpa2Personal) { self = .wpa3Transition }
        else if network.supportsSecurity(.wpa3Personal) { self = .wpa3 }
        else if network.supportsSecurity(.wpa2Personal) || network.supportsSecurity(.personal) { self = .wpa2 }
        else if network.supportsSecurity(.wpaPersonal) || network.supportsSecurity(.wpaPersonalMixed) { self = .wpa }
        else if network.supportsSecurity(.WEP) || network.supportsSecurity(.dynamicWEP) { self = .wep }
        else if network.supportsSecurity(.none) || network.supportsSecurity(.OWE) { self = .open }
        else { self = .unknown }
    }

    var name: String {
        switch self {
        case .open: return "Открытая"
        case .wep: return "WEP"
        case .wpa: return "WPA"
        case .wpa2: return "WPA2"
        case .wpa3Transition: return "WPA2/WPA3"
        case .wpa3: return "WPA3"
        case .enterprise: return "Enterprise"
        case .unknown: return "—"
        }
    }

    var score: Double {
        switch self {
        case .open: return 0
        case .wep: return 0.1
        case .wpa: return 0.3
        case .wpa2: return 0.75
        case .wpa3Transition: return 0.9
        case .wpa3, .enterprise: return 1
        case .unknown: return 0.5
        }
    }
}

struct LinkSnapshot {
    var interfaceName: String
    var ssid: String?
    var bssid: String?
    var rssi: Int
    var noise: Int
    var txRate: Double
    var channel: ChannelInfo?
    var phy: CWPHYMode
    var security: SecurityKind
    var countryCode: String?
    var txPower: Int
    var powerOn: Bool

    var isConnected: Bool { powerOn && channel != nil && rssi != 0 }
    var snr: Int { rssi - noise }
}

struct SignalSample: Identifiable {
    let id = UUID()
    let date: Date
    let rssi: Int
    let noise: Int
    let rate: Double
}

struct ThroughputSample: Identifiable {
    let id = UUID()
    let date: Date
    let down: Double // bytes per second
    let up: Double
}

struct ScannedNetwork: Identifiable, Hashable {
    let id: String
    let ssid: String?
    let bssid: String?
    let rssi: Int
    let noise: Int
    let channel: ChannelInfo
    let phy: CWPHYMode
    let security: SecurityKind
    var isCurrent: Bool
    /// Another SSID broadcast by the same access point radio (guest network etc.).
    var isSibling = false

    var displayName: String { ssid ?? "Скрытая / без доступа" }
}

struct Capabilities {
    var macName: String = "Mac"
    var macModel: String = ""
    var chip: String = ""
    var cardType: String = ""
    var firmware: String = ""
    var phyModes: String = ""
    var countryCode: String = ""
    var channels: [Band: [Int]] = [:]
    var maxWidth: Int = 80
    var gateway: String?

    func supports(_ band: Band) -> Bool { !(channels[band]?.isEmpty ?? true) }

    /// Broadcom chips Apple shipped that physically lack a 6 GHz radio.
    var chipLacks6GHz: Bool {
        ["0x4364", "0x4377", "0x4378", "0x4387", "0x4355", "0x4350"].contains { cardType.contains($0) }
    }
}

struct LatencyResult: Identifiable {
    let id = UUID()
    let label: String
    let host: String
    let avg: Double
    let min: Double
    let max: Double
    let jitter: Double
    let loss: Double // 0...1
}

/// One logical network: every radio broadcasting the same name (bands of one router, mesh nodes).
struct NetworkGroup: Identifiable {
    let id: String
    let ssid: String?
    let radios: [ScannedNetwork]

    var isMine: Bool { radios.contains { $0.isCurrent || $0.isSibling } }
    var isCurrent: Bool { radios.contains(where: \.isCurrent) }
    var best: ScannedNetwork { radios.max { $0.rssi < $1.rssi }! }
    var displayName: String { ssid ?? best.displayName }

    var bands: [Band] {
        Band.allCases.filter { b in radios.contains { $0.channel.band == b } }
    }

    /// Physical access points: radios grouped by the device part of their BSSID.
    var accessPoints: Int {
        let keys = radios.compactMap { r -> String? in
            guard let parts = r.bssid?.split(separator: ":"), parts.count == 6 else { return nil }
            return parts[1...4].joined(separator: ":")
        }
        if keys.count == radios.count { return Set(keys).count }
        return bands.map { b in radios.filter { $0.channel.band == b }.count }.max() ?? 1
    }

    var bestPHY: CWPHYMode { radios.max { PHY.rank($0.phy) < PHY.rank($1.phy) }!.phy }
    var weakestSecurity: SecurityKind { radios.map(\.security).min()! }

    static func make(_ networks: [ScannedNetwork]) -> [NetworkGroup] {
        var named: [String: [ScannedNetwork]] = [:]
        var loose: [NetworkGroup] = []
        // Without location access names are hidden: keep our own router's radios together anyway.
        let mineKey = networks.first(where: \.isCurrent).map { $0.ssid ?? "\u{0}current" }
        for n in networks {
            if let s = n.ssid, !s.isEmpty { named[s, default: []].append(n) }
            else if (n.isCurrent || n.isSibling), let k = mineKey { named[k, default: []].append(n) }
            else { loose.append(NetworkGroup(id: n.id, ssid: nil, radios: [n])) }
        }
        let groups = named.map { NetworkGroup(id: "ssid:" + $0.key, ssid: $0.key.hasPrefix("\u{0}") ? nil : $0.key,
                                              radios: $0.value.sorted { ($0.channel.band.order, -$0.rssi) < ($1.channel.band.order, -$1.rssi) }) }
        return (groups + loose).sorted { $0.best.rssi > $1.best.rssi }
    }
}

extension Band {
    var order: Int { Band.allCases.firstIndex(of: self) ?? 0 }
    var short: String {
        switch self {
        case .ghz2: return "2,4"
        case .ghz5: return "5"
        case .ghz6: return "6"
        }
    }
}
