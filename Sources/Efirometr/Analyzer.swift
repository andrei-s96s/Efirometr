import Foundation
import SwiftUI

enum Severity: Int, Comparable {
    case critical, warning, tip, info, good

    static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }

    var color: Color {
        switch self {
        case .critical: return Theme.bad
        case .warning: return Theme.warn
        case .tip: return Theme.accent
        case .info: return Theme.text2
        case .good: return Theme.good
        }
    }

    var label: String {
        switch self {
        case .critical: return "Важно"
        case .warning: return "Стоит исправить"
        case .tip: return "Улучшение"
        case .info: return "К сведению"
        case .good: return "Всё хорошо"
        }
    }
}

struct Recommendation: Identifiable {
    let id = UUID()
    let severity: Severity
    let icon: String
    let title: String
    let detail: String
    var steps: [String] = []
}

struct ScoreComponent: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let value: Double // 0...1
    let weight: Double
    let detail: String
}

struct Assessment {
    var score: Int
    var grade: String
    var summary: String
    var components: [ScoreComponent]
    var recommendations: [Recommendation]

    static let empty = Assessment(score: 0, grade: "—", summary: "Нет данных", components: [], recommendations: [])
}

struct ChannelLoad: Identifiable {
    var id: Int { channel.number }
    let channel: ChannelInfo
    let load: Double
    let networks: Int
}

enum Analyzer {
    static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }

    /// Wi‑Fi 6, 2 spatial streams, MCS 11, 0.8 µs GI.
    static func maxRate(width: Int) -> Double {
        switch width {
        case ..<40: return 287
        case 40..<80: return 574
        case 80..<160: return 1201
        default: return 2402
        }
    }

    // MARK: - Channel congestion

    /// Sum of neighbours' airtime pressure on `channel`: each network weighs by its strength and spectral overlap.
    static func load(on channel: ChannelInfo, networks: [ScannedNetwork], excludeCurrent: Bool = true) -> (load: Double, count: Int) {
        var total = 0.0
        var count = 0
        for n in networks where n.channel.band == channel.band {
            if excludeCurrent && (n.isCurrent || n.isSibling) { continue }
            let overlap = channel.overlap(with: n.channel)
            guard overlap > 0 else { continue }
            let strength = clamp(Double(n.rssi + 90) / 35)
            guard strength > 0 else { continue }
            total += strength * overlap
            count += 1
        }
        return (total, count)
    }

    /// Candidate channels for a band at a given width, with the load each would see.
    static func candidates(band: Band, width: Int, caps: Capabilities, networks: [ScannedNetwork]) -> [ChannelLoad] {
        let supported = Set(caps.channels[band] ?? [])
        var starts: [Int]
        switch band {
        case .ghz2:
            starts = [1, 6, 11]
            if supported.contains(13) { starts.append(13) }
        case .ghz5:
            let n = max(1, width / 20)
            let step = 4 * n
            starts = stride(from: 36, through: 144, by: step).map { $0 } + stride(from: 149, through: 165, by: step).map { $0 }
            starts = starts.filter { s in (0..<n).allSatisfy { supported.contains(s + 4 * $0) } }
        case .ghz6:
            let n = max(1, width / 20)
            starts = stride(from: 1, through: 233, by: 4 * n).filter { supported.contains($0) }
        }
        return starts.map { s in
            let ch = ChannelInfo(number: s, band: band, width: band == .ghz2 ? 20 : width)
            let l = load(on: ch, networks: networks, excludeCurrent: true)
            return ChannelLoad(channel: ch, load: l.load, networks: l.count)
        }
    }

    // MARK: - Assessment

    static func assess(link: LinkSnapshot?, networks: [ScannedNetwork], caps: Capabilities?, latency: [LatencyResult], locationAuthorized: Bool) -> Assessment {
        guard let link, link.isConnected, let ch = link.channel else {
            var recs = [Recommendation(severity: .critical, icon: "wifi.slash", title: "Нет подключения к Wi‑Fi",
                                       detail: link?.powerOn == false ? "Wi‑Fi выключен. Включите его в Пункте управления." : "Mac не подключён ни к одной сети.")]
            if let caps { recs += hardwareNotes(link: nil, caps: caps, networks: networks) }
            return Assessment(score: 0, grade: "Нет связи", summary: "Подключитесь к сети, чтобы получить оценку", components: [], recommendations: recs)
        }
        let caps = caps ?? Capabilities()
        let admin = "Откройте в браузере **http://\(caps.gateway ?? "192.168.0.1")** и войдите в настройки роутера (логин и пароль обычно на наклейке снизу)."
        var recs: [Recommendation] = []
        var parts: [ScoreComponent] = []

        // Signal
        let sig = clamp(Double(link.rssi + 85) / 30)
        parts.append(ScoreComponent(name: "Сигнал", icon: "wifi", value: sig, weight: 30, detail: "\(link.rssi) dBm"))
        if link.rssi < -75 {
            recs.append(Recommendation(severity: .critical, icon: "wifi.exclamationmark", title: "Слабый сигнал (\(link.rssi) dBm)",
                                       detail: "Подойдите ближе к роутеру или уберите препятствия — стены, зеркала, аквариумы. Для большой квартиры лучше mesh‑система или вторая точка доступа, а не репитер.",
                                       steps: ["Поставьте роутер выше, на шкаф или полку, а не на пол и не в тумбу.",
                                               "Уберите его от металла, зеркал, аквариумов и микроволновки.",
                                               "Разверните антенны: одну вертикально, другую горизонтально.",
                                               "Если не помогло — поставьте mesh‑систему или вторую точку доступа по кабелю."]))
        } else if link.rssi < -67 {
            recs.append(Recommendation(severity: .warning, icon: "wifi", title: "Сигнал средний (\(link.rssi) dBm)",
                                       detail: "Для видеозвонков и стабильной скорости желательно −65 dBm и лучше. Поставьте роутер выше и ближе к центру помещения.",
                                       steps: ["Откройте вкладку «Обзор» и следите за графиком сигнала.",
                                               "Медленно переставляйте роутер или ноутбук, пока сигнал не поднимется выше −65 dBm.",
                                               "Проверьте, что роутер не стоит за телевизором или в закрытом шкафу."]))
        }

        // SNR
        let snrScore = clamp(Double(link.snr - 10) / 30)
        parts.append(ScoreComponent(name: "Сигнал/шум", icon: "waveform", value: snrScore, weight: 20, detail: "\(link.snr) dB"))
        if link.snr < 20 {
            recs.append(Recommendation(severity: .warning, icon: "waveform.badge.exclamationmark", title: "Высокий уровень помех (SNR \(link.snr) dB)",
                                       detail: "Шум \(link.noise) dBm. Источники: микроволновки, Bluetooth, USB 3‑хабы рядом с ноутбуком, соседние сети. Попробуйте другой канал или 5 ГГц.",
                                       steps: ["Отодвиньте от ноутбука USB‑хабы и док‑станции USB 3: они фонят на 2,4 ГГц.",
                                               "Откройте вкладку «Каналы» и найдите самый свободный канал.",
                                               admin,
                                               "Задайте этот канал вручную вместо «Авто» и сохраните."]))
        }

        // Band & standard
        var bandScore: Double = ch.band == .ghz2 ? 0.5 : ch.band == .ghz5 ? 0.85 : 1.0
        switch PHY.rank(link.phy) {
        case 6...: bandScore += 0.1
        case 5: break
        default: bandScore -= 0.15
        }
        if ch.band != .ghz2 { bandScore += ch.width >= 160 ? 0.05 : ch.width < 80 ? -0.1 : 0 }
        parts.append(ScoreComponent(name: "Диапазон и стандарт", icon: "antenna.radiowaves.left.and.right", value: clamp(bandScore), weight: 15,
                                    detail: "\(ch.band.rawValue), \(PHY.label(link.phy)), \(ch.width) МГц"))

        // Congestion
        let current = load(on: ch, networks: networks)
        let congestion = 1 / (1 + current.load * 0.6)
        parts.append(ScoreComponent(name: "Загрузка канала", icon: "chart.bar.xaxis", value: congestion, weight: 15,
                                    detail: current.count == 0 ? "соседей нет" : "соседей: \(current.count)"))

        // Security
        parts.append(ScoreComponent(name: "Безопасность", icon: "lock.shield", value: link.security.score, weight: 10, detail: link.security.name))

        // Latency
        if let gw = latency.first(where: { $0.label == "Роутер" }) {
            let v = clamp(1 - (gw.avg - 3) / 40) * clamp(1 - gw.loss * 5) * clamp(1 - gw.jitter / 60)
            parts.append(ScoreComponent(name: "Задержка до роутера", icon: "timer", value: v, weight: 10,
                                        detail: String(format: "%.0f мс, потери %.0f%%", gw.avg, gw.loss * 100)))
        }

        // Band advice
        if ch.band == .ghz2 && caps.supports(.ghz5) {
            let same5 = networks.filter { $0.channel.band == .ghz5 && link.ssid != nil && $0.ssid == link.ssid }
            if let best = same5.max(by: { $0.rssi < $1.rssi }), best.rssi > -75 {
                recs.append(Recommendation(severity: .warning, icon: "arrow.up.right.circle", title: "Вы на 2,4 ГГц, хотя рядом есть 5 ГГц",
                                           detail: "Ваша сеть «\(link.ssid ?? "")» вещает и на 5 ГГц (\(best.rssi) dBm, канал \(best.channel.number)). Там в разы выше скорость и меньше помех. Разделите имена сетей на роутере или включите Band Steering.",
                                           steps: [admin,
                                                   "Раздел Wi‑Fi: дайте сети 5 ГГц отдельное имя, например «\(link.ssid ?? "Home")‑5G».",
                                                   "На Mac: меню Wi‑Fi → подключитесь к сети 5G.",
                                                   "Системные настройки → Wi‑Fi → Подробнее: поставьте сеть 5G выше в списке или отключите автоподключение к 2,4."]))
            } else {
                recs.append(Recommendation(severity: .tip, icon: "arrow.up.right.circle", title: "Подключение на 2,4 ГГц",
                                           detail: "Этот диапазон медленный и загружен соседями. Если роутер поддерживает 5 ГГц — включите его и подключитесь к нему.",
                                           steps: [admin, "Раздел Wi‑Fi → включите радиомодуль 5 ГГц.", "Подключитесь к появившейся сети из меню Wi‑Fi."]))
            }
        }

        // Channel advice
        let cands = candidates(band: ch.band, width: ch.band == .ghz2 ? 20 : ch.width, caps: caps, networks: networks)
        if let best = cands.min(by: { ($0.load + $0.channel.pickPenalty) < ($1.load + $1.channel.pickPenalty) }),
           best.channel.block != ch.block, current.load - best.load > 0.6 {
            let dfs = best.channel.isDFS ? " Это DFS‑канал: роутер может кратковременно уходить с него при обнаружении радаров."
                : best.channel.isLimited2G ? " Учтите: " + ChannelInfo.limited2GNote : ""
            recs.append(Recommendation(severity: current.load > 1.5 ? .warning : .tip, icon: "dial.medium",
                                       title: "Смените канал \(ch.number) → \(best.channel.number)",
                                       detail: String(format: "На вашем канале давление соседей %.1f, на канале %d — %.1f. Выберите его вручную в настройках роутера вместо «Авто».", current.load, best.channel.number, best.load) + dfs,
                                       steps: [admin,
                                               "Раздел Wi‑Fi → \(ch.band.rawValue) → «Канал» (Channel).",
                                               "Смените «Авто» на **\(best.channel.number)**, ширину оставьте \(ch.band == .ghz2 ? 20 : ch.width) МГц.",
                                               "Сохраните. Mac переподключится через 10–30 секунд.",
                                               "Вернитесь в приложение и нажмите «Сканировать эфир», чтобы проверить результат."]))
        } else if current.count > 0 && current.load < 0.6 {
            recs.append(Recommendation(severity: .good, icon: "checkmark.circle", title: "Канал выбран удачно", detail: "Соседние сети почти не пересекаются с вашей."))
        }

        if ch.isLimited2G {
            recs.append(Recommendation(severity: .warning, icon: "exclamationmark.triangle", title: "Канал \(ch.number) видят не все устройства",
                                       detail: ChannelInfo.limited2GNote + " Если какое‑то устройство не находит вашу сеть — причина, скорее всего, в этом.",
                                       steps: [admin, "Wi‑Fi → 2,4 ГГц → «Канал»: выберите 1, 6 или 11 (самый свободный — на вкладке «Каналы»).", "Сохраните и проверьте, что проблемное устройство теперь видит сеть."]))
        }

        // Width advice
        if ch.band == .ghz2 && ch.width >= 40 && current.count >= 3 {
            recs.append(Recommendation(severity: .tip, icon: "arrow.left.and.right", title: "Сузьте канал 2,4 ГГц до 20 МГц",
                                       detail: "40 МГц в плотном эфире больше мешают, чем помогают: роутер постоянно уступает соседям.",
                                       steps: [admin, "Wi‑Fi → 2,4 ГГц → «Ширина канала» (Bandwidth) → 20 МГц.", "Каналы на 2,4 ГГц: только 1, 6 или 11 — они не пересекаются."]))
        }
        if ch.band == .ghz5 && ch.width < 80 {
            recs.append(Recommendation(severity: .tip, icon: "arrow.left.and.right", title: "Включите ширину 80 МГц",
                                       detail: "Сейчас \(ch.width) МГц. При 80 МГц скорость вырастет примерно в \(ch.width == 20 ? "4" : "2") раза.",
                                       steps: [admin, "Wi‑Fi → 5 ГГц → «Ширина канала» → 80 МГц (или 20/40/80 МГц).", "Режим — 802.11ax или ac/ax."]))
        }
        if ch.band == .ghz5 && ch.width == 80 && caps.maxWidth >= 160 {
            let wide = ChannelInfo(number: ch.number, band: .ghz5, width: 160)
            let l = load(on: wide, networks: networks)
            if l.load < 1.2 && link.rssi > -65 {
                recs.append(Recommendation(severity: .tip, icon: "bolt.horizontal", title: "Можно включить 160 МГц",
                                           detail: String(format: "Ваш Mac поддерживает 160 МГц, а эфир вокруг канала %d свободен (давление %.1f). Это поднимет скорость соединения примерно до 1200 Мбит/с.", ch.number, l.load)))
            }
        }

        if ch.band != .ghz2, caps.maxWidth < 160,
           let mine = networks.first(where: \.isCurrent), mine.channel.width > ch.width {
            recs.append(Recommendation(severity: .info, icon: "arrow.left.and.right", title: "Роутер вещает \(mine.channel.width) МГц, а Mac берёт только \(ch.width)",
                                       detail: String(format: "Модуль Wi‑Fi этого Mac (или регион %@) ограничен %d МГц, поэтому потолок соединения — около %.0f Мбит/с (сейчас %.0f). Широкий канал роутера при этом сильнее пересекается с соседями; если устройств с поддержкой 160 МГц нет, 80 МГц на роутере будет стабильнее.", caps.countryCode, caps.maxWidth, Analyzer.maxRate(width: caps.maxWidth), link.txRate)))
        }

        // Rate advice
        if ch.band != .ghz2 && link.rssi > -60 && link.txRate > 0 && link.txRate < 200 {
            recs.append(Recommendation(severity: .warning, icon: "speedometer", title: "Низкая скорость при хорошем сигнале",
                                       detail: String(format: "Сигнал отличный, но скорость всего %.0f Мбит/с. Проверьте ширину канала и режим на роутере, обновите его прошивку.", link.txRate)))
        }

        // Standard advice
        if PHY.rank(link.phy) < 6 && caps.phyModes.contains("ax") {
            recs.append(Recommendation(severity: .tip, icon: "arrow.up.circle", title: "Роутер не даёт Wi‑Fi 6",
                                       detail: "Подключение идёт по \(PHY.standard(link.phy)), хотя Mac умеет 802.11ax (Wi‑Fi 6). Обновите роутер или включите режим ax/Wi‑Fi 6 в его настройках."))
        }

        // Security advice
        switch link.security {
        case .open:
            recs.append(Recommendation(severity: .critical, icon: "lock.open", title: "Сеть без пароля", detail: "Трафик могут перехватить. Включите WPA3 или WPA2/WPA3 на роутере, а в чужих сетях используйте VPN."))
        case .wep, .wpa:
            recs.append(Recommendation(severity: .critical, icon: "lock.trianglebadge.exclamationmark", title: "Устаревшая защита \(link.security.name)", detail: "Взламывается за минуты и режет скорость до 54 Мбит/с. Переключите роутер на WPA2/WPA3.",
                                   steps: [admin, "Wi‑Fi → Безопасность → «WPA2/WPA3‑Personal».", "Задайте пароль не короче 12 символов."]))
        case .wpa2:
            recs.append(Recommendation(severity: .tip, icon: "lock.shield", title: "Включите WPA3", detail: "WPA3 защищает от подбора пароля офлайн. Безопасный вариант — режим «WPA2/WPA3», чтобы старые устройства не отвалились.",
                                   steps: [admin, "Wi‑Fi → Безопасность → «WPA2/WPA3‑Personal» (Transition).", "Сохраните. Пароль менять не нужно."]))
        default: break
        }

        // Latency advice
        if let gw = latency.first(where: { $0.label == "Роутер" }) {
            if gw.loss > 0.01 || gw.avg > 15 || gw.jitter > 25 {
                recs.append(Recommendation(severity: .warning, icon: "timer", title: "Нестабильная связь с роутером",
                                           detail: String(format: "Медианная задержка %.0f мс, джиттер %.0f мс, потери %.0f%%. Для локальной сети норма — до 5 мс без потерь. Причина обычно в помехах или слабом сигнале.", gw.avg, gw.jitter, gw.loss * 100),
                                           steps: ["Повторите тест рядом с роутером. Если там хорошо — дело в покрытии.",
                                                   "Если плохо и рядом — перезагрузите роутер и смените канал (вкладка «Каналы»).",
                                                   "Для звонков и игр лучше всего кабель Ethernet через USB‑C адаптер."]))
            }
        }
        if let inet = latency.first(where: { $0.label == "Интернет" }), let gw = latency.first(where: { $0.label == "Роутер" }), inet.avg - gw.avg > 60 {
            recs.append(Recommendation(severity: .info, icon: "globe", title: "Задержка в основном у провайдера",
                                       detail: String(format: "До роутера %.0f мс, до интернета %.0f мс. Wi‑Fi тут ни при чём — дело в канале провайдера.", gw.avg, inet.avg)))
        }

        if !locationAuthorized {
            recs.append(Recommendation(severity: .info, icon: "location.slash", title: "Имена сетей скрыты",
                                       detail: "macOS показывает SSID только приложениям с доступом к геолокации. Разрешите его в Настройках → Конфиденциальность → Службы геолокации.",
                                   steps: ["Откройте Системные настройки → Конфиденциальность и безопасность → Службы геолокации.",
                                           "Включите переключатель у «\(AppInfo.name)».",
                                           "Вернитесь в приложение: имена сетей появятся при следующем скане."]))
        }

        recs += hardwareNotes(link: link, caps: caps, networks: networks)

        let total = parts.reduce(0) { $0 + $1.weight }
        let score = Int((parts.reduce(0) { $0 + $1.value * $1.weight } / max(total, 1) * 100).rounded())
        let grade: String
        let summary: String
        switch score {
        case 85...: grade = "Отлично"; summary = "Сеть работает на пределе возможностей"
        case 70..<85: grade = "Хорошо"; summary = "Есть что подкрутить, но в целом стабильно"
        case 50..<70: grade = "Средне"; summary = "Скорость и стабильность заметно страдают"
        default: grade = "Плохо"; summary = "Сеть требует внимания"
        }
        if recs.allSatisfy({ $0.severity >= .info }) {
            recs.append(Recommendation(severity: .good, icon: "sparkles", title: "Серьёзных проблем нет", detail: "Сигнал, канал и защита в порядке."))
        }
        return Assessment(score: score, grade: grade, summary: summary, components: parts, recommendations: recs.sorted { $0.severity < $1.severity })
    }

    private static func hardwareNotes(link: LinkSnapshot?, caps: Capabilities, networks: [ScannedNetwork]) -> [Recommendation] {
        var recs: [Recommendation] = []
        if !caps.supports(.ghz6) {
            if caps.chipLacks6GHz {
                recs.append(Recommendation(severity: .info, icon: "6.circle", title: "6 ГГц (Wi‑Fi 6E) недоступен на этом Mac",
                                           detail: "Модуль \(caps.cardType) физически не имеет радио 6 ГГц. Это ограничение железа — драйвером или настройками не исправить. Wi‑Fi 6E есть в Mac на M2 Pro/Max и новее."))
            } else {
                recs.append(Recommendation(severity: .info, icon: "6.circle", title: "Нет каналов 6 ГГц",
                                           detail: "Список разрешённых каналов не содержит 6 ГГц. Либо модуль не поддерживает Wi‑Fi 6E, либо диапазон запрещён в регионе (код страны \(caps.countryCode.isEmpty ? "—" : caps.countryCode))."))
            }
        } else if let link, link.channel?.band != .ghz6, networks.contains(where: { $0.channel.band == .ghz6 && link.ssid != nil && $0.ssid == link.ssid }) {
            recs.append(Recommendation(severity: .tip, icon: "6.circle", title: "Доступна ваша сеть на 6 ГГц", detail: "Mac поддерживает 6 ГГц, и роутер вещает в нём. Это самый чистый диапазон — подключитесь к нему."))
        }
        return recs
    }
}
