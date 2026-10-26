import SwiftUI

struct DeviceView: View {
    @EnvironmentObject var monitor: WiFiMonitor

    var body: some View {
        let caps = monitor.capabilities ?? Capabilities()
        SnapshotScroll {
            VStack(spacing: 18) {
                HStack(alignment: .top, spacing: 18) {
                    Card("Mac", icon: "laptopcomputer") {
                        row("Модель", caps.macName)
                        row("Идентификатор", caps.macModel)
                        row("Процессор", caps.chip)
                    }
                    Card("Модуль Wi‑Fi", icon: "cpu") {
                        row("Чип", caps.cardType.isEmpty ? "—" : "Broadcom \(caps.cardType)")
                        row("Стандарты", caps.bestStandard.map { "до \($0.generation) (\($0.letters))" } ?? caps.phyModes)
                        row("Макс. ширина канала", "\(caps.maxWidth) МГц")
                        row("Потолок скорости", String(format: "≈ %.0f Мбит/с", Analyzer.maxRate(width: caps.maxWidth)))
                        row("Код страны", caps.countryCode.isEmpty ? "—" : caps.countryCode)
                        row("Роутер", caps.gateway ?? "—")
                    }
                }

                Card("Диапазоны", icon: "antenna.radiowaves.left.and.right") {
                    HStack(spacing: 12) {
                        ForEach(Band.allCases) { b in
                            let ok = caps.supports(b)
                            let tint = ok ? Theme.good : Theme.bad
                            VStack(spacing: 8) {
                                Image(systemName: ok ? "checkmark" : "xmark")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(tint)
                                    .frame(width: 40, height: 40)
                                    .background(tint.opacity(0.14), in: Circle())
                                    .shadow(color: tint.opacity(0.4), radius: 8)
                                Text(b.rawValue).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                                Text(ok ? "каналов: \(caps.channels[b]?.count ?? 0)" : "не поддерживается")
                                    .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .glass(radius: 14, fill: tint.opacity(0.05))
                        }
                    }
                    if !caps.supports(.ghz6) {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "info.circle.fill").foregroundStyle(Theme.accent)
                            Text(caps.chipLacks6GHz
                                 ? "Модуль \(caps.cardType) не имеет радио 6 ГГц, поэтому Wi‑Fi 6E на этом Mac невозможен ни программно, ни через настройки. Он появился в MacBook Pro на M2 Pro/Max и новее."
                                 : "Каналов 6 ГГц нет в списке разрешённых: либо модуль не поддерживает Wi‑Fi 6E, либо диапазон запрещён в регионе \(caps.countryCode).")
                                .font(.system(size: 12.5)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                StandardsCard(caps: caps, current: monitor.link?.isConnected == true ? monitor.link?.phy : nil)

                ForEach(Band.allCases.filter { caps.supports($0) }) { b in
                    Card("Каналы · \(b.rawValue)", icon: "number") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 6)], spacing: 6) {
                            ForEach(caps.channels[b] ?? [], id: \.self) { ch in
                                let isCur = monitor.link?.channel?.band == b && monitor.link?.channel?.number == ch
                                let info = ChannelInfo(number: ch, band: b, width: 20)
                                let dfs = info.isDFS || info.isLimited2G
                                Text("\(ch)")
                                    .font(Theme.number(12.5, isCur ? .bold : .medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 7)
                                    .foregroundStyle(isCur ? Color.white : dfs ? Theme.warn : Theme.text)
                                    .background {
                                        if isCur { RoundedRectangle(cornerRadius: 8).fill(Theme.accentGradient).shadow(color: Theme.accent.opacity(0.5), radius: 6) }
                                        else { RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)) }
                                    }
                                    .help(isCur ? "Текущий канал" : info.isDFS ? "DFS‑канал" : info.isLimited2G ? ChannelInfo.limited2GNote : "Канал \(ch)")
                            }
                        }
                        if b == .ghz2 && (caps.channels[b] ?? []).contains(where: { $0 >= 12 }) {
                            HStack(spacing: 14) {
                                legendDot(Theme.accent, "текущий")
                                legendDot(Theme.warn, "12–13 — не видят устройства для рынка США и часть старой техники")
                            }
                        }
                        if b == .ghz5 {
                            HStack(spacing: 14) {
                                legendDot(Theme.accent, "текущий")
                                legendDot(Theme.warn, "DFS — роутер уходит с канала при обнаружении радара")
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Устройство")
    }

    private func legendDot(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(c).frame(width: 7, height: 7)
            Text(t).font(.system(size: 11.5)).foregroundStyle(Theme.text3)
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).foregroundStyle(Theme.text3)
            Spacer()
            Text(v.isEmpty ? "—" : v).foregroundStyle(Theme.text).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .font(.system(size: 13))
    }
}
