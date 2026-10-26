import SwiftUI
import CoreWLAN

/// Plain-language reference for each 802.11 generation.
struct StandardInfo: Identifiable {
    let letters: String       // "ax"
    let generation: String    // "Wi‑Fi 6"
    let year: String
    let bands: String
    let maxSpeed: String
    let note: String

    var id: String { letters }
    var code: String { "802.11" + letters }

    static let catalog: [StandardInfo] = [
        .init(letters: "be", generation: "Wi‑Fi 7", year: "2024", bands: "2,4 · 5 · 6 ГГц", maxSpeed: "до 46 Гбит/с",
              note: "Каналы 320 МГц и MLO — работа сразу в нескольких диапазонах для минимальной задержки."),
        .init(letters: "ax", generation: "Wi‑Fi 6", year: "2019", bands: "2,4 · 5 ГГц", maxSpeed: "до 9,6 Гбит/с",
              note: "OFDMA и Target Wake Time: быстрее в квартире с десятками устройств, меньше расход батареи."),
        .init(letters: "ac", generation: "Wi‑Fi 5", year: "2013", bands: "5 ГГц", maxSpeed: "до 6,9 Гбит/с",
              note: "Каналы 80/160 МГц и MU‑MIMO. Только 5 ГГц — на 2,4 ГГц такие устройства работают по n."),
        .init(letters: "n", generation: "Wi‑Fi 4", year: "2009", bands: "2,4 · 5 ГГц", maxSpeed: "до 600 Мбит/с",
              note: "Первый с MIMO (несколько антенн) и каналами 40 МГц. Сейчас — минимум для нормальной работы."),
        .init(letters: "g", generation: "Wi‑Fi 3*", year: "2003", bands: "2,4 ГГц", maxSpeed: "до 54 Мбит/с",
              note: "Устаревший. Если в сети есть такое устройство, роутер может замедлять всех остальных."),
        .init(letters: "a", generation: "Wi‑Fi 2*", year: "1999", bands: "5 ГГц", maxSpeed: "до 54 Мбит/с",
              note: "Первый стандарт на 5 ГГц. Устаревший."),
        .init(letters: "b", generation: "Wi‑Fi 1*", year: "1999", bands: "2,4 ГГц", maxSpeed: "до 11 Мбит/с",
              note: "Самый первый массовый Wi‑Fi. Устаревший и очень медленный."),
    ]

    static func info(_ letters: String) -> StandardInfo? { catalog.first { $0.letters == letters } }
}

extension PHY {
    static func letters(_ mode: CWPHYMode) -> String {
        switch mode {
        case .mode11be: return "be"
        case .mode11ax: return "ax"
        case .mode11ac: return "ac"
        case .mode11n: return "n"
        case .mode11a: return "a"
        case .mode11g: return "g"
        case .mode11b: return "b"
        default: return ""
        }
    }

    /// "Wi‑Fi 6 (ax)" — generation plus the letter code people see in router settings.
    static func label(_ mode: CWPHYMode) -> String {
        let l = letters(mode)
        guard !l.isEmpty else { return "—" }
        let name = name(mode)
        return name.hasPrefix("Wi‑Fi") ? "\(name) (\(l))" : name
    }

    /// One-line explanation for tooltips.
    static func explain(_ mode: CWPHYMode) -> String {
        guard let i = StandardInfo.info(letters(mode)) else { return "Стандарт не определён" }
        return "\(i.generation.replacingOccurrences(of: "*", with: "")) = \(i.code), \(i.year) г. · \(i.bands) · \(i.maxSpeed). \(i.note)"
    }
}

extension Capabilities {
    /// Letter codes from "802.11 a/b/g/n/ac/ax".
    var supportedStandards: Set<String> {
        guard let slash = phyModes.split(separator: " ").last else { return [] }
        return Set(slash.split(separator: "/").map { String($0) })
    }

    var bestStandard: StandardInfo? {
        StandardInfo.catalog.first { supportedStandards.contains($0.letters) }
    }
}

/// Reference card on the Device screen: every Wi‑Fi generation, decoded, with what this Mac supports.
struct StandardsCard: View {
    let caps: Capabilities
    var current: CWPHYMode?

    var body: some View {
        let supported = caps.supportedStandards
        let currentLetters = current.map(PHY.letters) ?? ""
        Card("Стандарты Wi‑Fi", icon: "list.bullet.rectangle.portrait",
             hint: Hint(title: "Что значат буквы 802.11",
                        body: "802.11 — общее название семейства стандартов Wi‑Fi, а буквы после него — версия. С 2018 года версиям дали простые номера: ax = Wi‑Fi 6, ac = Wi‑Fi 5, n = Wi‑Fi 4. Устройство и роутер работают на самом новом стандарте, который поддерживают оба.",
                        tip: "* — неофициальные номера: Wi‑Fi Alliance пронумеровала только начиная с Wi‑Fi 4.")) {
            if let best = caps.bestStandard {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.good).font(.system(size: 18))
                    Text("Ваш Mac поддерживает до \(best.generation) (\(best.code))" + (caps.supports(.ghz6) && best.letters == "ax" ? " включая 6E" : "") + ".")
                        .font(.system(size: 13.5, weight: .medium)).foregroundStyle(Theme.text)
                }
            }
            VStack(spacing: 6) {
                // Newest first; 6E sits between Wi‑Fi 7 and Wi‑Fi 6.
                ForEach(StandardInfo.catalog) { s in
                    if s.letters == "ax" { row6E(supported: supported) }
                    row(s, supported: supported.contains(s.letters), inUse: s.letters == currentLetters)
                }
            }
            Text("Буквы в строке «802.11 a/b/g/n/ac/ax» — это и есть список поддерживаемых стандартов. * — неофициальные номера: официально нумерация начинается с Wi‑Fi 4.")
                .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
        }
    }

    private func row(_ s: StandardInfo, supported: Bool, inUse: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: supported ? "checkmark.circle.fill" : "xmark.circle")
                .font(.system(size: 14))
                .foregroundStyle(supported ? Theme.good : Theme.text3)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(s.generation).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(supported ? Theme.text : Theme.text2)
                    Text(s.code).font(.system(size: 12).monospaced()).foregroundStyle(Theme.text3)
                    if inUse { Badge(text: "сейчас", tint: Theme.good) }
                    Spacer(minLength: 8)
                    Text(s.year).frame(width: 40, alignment: .trailing)
                    Text(s.bands).frame(width: 120, alignment: .trailing)
                    Text(s.maxSpeed).frame(width: 110, alignment: .trailing)
                }
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Theme.text2)
                Text(s.note).font(.system(size: 11.5)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(inUse ? Theme.good.opacity(0.07) : Color.white.opacity(supported ? 0.035 : 0.015), in: RoundedRectangle(cornerRadius: 10))
        .opacity(supported ? 1 : 0.75)
    }

    /// 6E isn't a separate letter: it's 802.11ax extended to 6 GHz.
    private func row6E(supported: Set<String>) -> some View {
        let ok = supported.contains("ax") && caps.supports(.ghz6)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
                .font(.system(size: 14)).foregroundStyle(ok ? Theme.good : Theme.text3).padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("Wi‑Fi 6E").font(.system(size: 13.5, weight: .semibold)).foregroundStyle(ok ? Theme.text : Theme.text2)
                    Text("802.11ax + 6 ГГц").font(.system(size: 12).monospaced()).foregroundStyle(Theme.text3)
                    Spacer(minLength: 8)
                    Text("2020").frame(width: 40, alignment: .trailing)
                    Text("2,4 · 5 · 6 ГГц").frame(width: 120, alignment: .trailing)
                    Text("до 9,6 Гбит/с").frame(width: 110, alignment: .trailing)
                }
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Theme.text2)
                Text(ok ? "Тот же Wi‑Fi 6, но ещё и в чистом диапазоне 6 ГГц без старых устройств и соседей."
                        : "Тот же Wi‑Fi 6, но ещё и в диапазоне 6 ГГц. На этом Mac недоступен: " + (caps.chipLacks6GHz ? "модуль не имеет радио 6 ГГц." : "нет разрешённых каналов 6 ГГц."))
                    .font(.system(size: 11.5)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(Color.white.opacity(ok ? 0.035 : 0.015), in: RoundedRectangle(cornerRadius: 10))
        .opacity(ok ? 1 : 0.75)
    }
}
