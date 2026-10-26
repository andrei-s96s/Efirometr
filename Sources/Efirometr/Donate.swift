import SwiftUI
import CoreImage.CIFilterBuiltins

/// Product identity in one place, so a rename touches a single constant.
enum AppInfo {
    static let name = "Эфирометр"
    static let tagline = "Понятная диагностика домашнего Wi‑Fi для Mac"
    static let bundleID = "local.efirometr"
    static let isDemo = CommandLine.arguments.contains("--demo")

    /// ~/Library/Application Support/Efirometr — journal, speed tests, survey.
    static let supportDirectory: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Efirometr")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }

    static let donationAddress = "TXaAjjkbDLFbFKS2pWfmneXzfRNZZgGWkW"
    static let donationNetwork = "USDT · сеть TRON (TRC20)"
}

enum QRCode {
    /// Crisp QR image: CoreImage output scaled with nearest-neighbour so modules stay sharp.
    static func image(for text: String, size: CGFloat) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: size, height: size))
    }
}

struct DonateView: View {
    @State private var copied = false

    private let features: [(String, String, String, Color)] = [
        ("gauge.with.dots.needle.67percent", "Оценка и советы", "Балл от 0 до 100 и пошаговые инструкции, что поменять в роутере", Theme.good),
        ("chart.xyaxis.line", "Каналы и соседи", "Спектр эфира, загрузка каналов и лучший канал для вашей сети", Theme.accent),
        ("speedometer", "Тест скорости", "Реальная скорость интернета и где узкое место — Wi‑Fi или провайдер", Theme.cyan),
        ("clock.arrow.circlepath", "Журнал и уведомления", "История обрывов и задержек, оповещения о проблемах", Theme.warn),
        ("map", "Карта квартиры", "Замеры по комнатам: где слабый сигнал и куда ставить роутер", Theme.pink),
        ("menubar.rectangle", "Скорость в строке меню", "Входящий и исходящий трафик всегда на виду", Theme.violet),
    ]

    var body: some View {
        SnapshotScroll {
            VStack(spacing: 18) {
                hero
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    ForEach(features, id: \.1) { f in feature(f.0, f.1, f.2, f.3) }
                }
                principles
                donation
                Text("\(AppInfo.name) \(AppInfo.version) · сделано с любовью к стабильному интернету")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.text3)
                    .padding(.top, 4)
            }
            .padding(24)
        }
        .navigationTitle("Поддержать")
    }

    // MARK: Sections

    private var hero: some View {
        HStack(spacing: 24) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .shadow(color: Theme.accent.opacity(0.35), radius: 18, y: 6)
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow(text: "О проекте", icon: "sparkles")
                Text(AppInfo.name).font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
                Text(AppInfo.tagline).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.accent)
                Text("Wi‑Fi тормозит, а непонятно почему? Приложение смотрит на сеть глазами инженера: силу сигнала, помехи, загрузку каналов соседями, стандарт и защиту — и переводит всё это на человеческий язык. Без графиков ради графиков: только понятный диагноз и конкретные шаги, что сделать.")
                    .font(.system(size: 13.5)).foregroundStyle(Theme.text2).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(26)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.card)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.accent.opacity(0.16), Theme.violet.opacity(0.08), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.strokeGradient))
    }

    private func feature(_ icon: String, _ title: String, _ text: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint)
                .frame(width: 32, height: 32).background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
            Text(title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Theme.text)
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .glass(radius: 14)
    }

    private var principles: some View {
        HStack(spacing: 10) {
            principle("lock.shield", "Данные не покидают Mac")
            principle("person.crop.circle.badge.xmark", "Без аккаунтов и рекламы")
            principle("bolt", "Лёгкое: ~1% процессора")
            principle("gift", "Бесплатно")
        }
    }

    private func principle(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(Theme.good)
            Text(text).foregroundStyle(Theme.text2)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 12).padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.035), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.stroke))
    }

    private var donation: some View {
        HStack(alignment: .center, spacing: 28) {
            VStack(spacing: 10) {
                if let qr = QRCode.image(for: AppInfo.donationAddress, size: 360) {
                    Image(nsImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 180, height: 180)
                        .padding(12)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: Theme.accent.opacity(0.3), radius: 16, y: 4)
                }
                Text("Отсканируйте в кошельке").font(.system(size: 11)).foregroundStyle(Theme.text3)
            }

            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "Поддержать разработку", icon: "heart.fill")
                Text("Если приложение помогло — можно угостить автора кофе")
                    .font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(Theme.text)
                Text("Проект развивается в свободное время. Любая сумма помогает добавлять новые функции и держать приложение бесплатным.")
                    .font(.system(size: 13)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Badge(text: "USDT", icon: "dollarsign.circle.fill", tint: Theme.good)
                    Badge(text: "TRON · TRC20", tint: Theme.accent)
                }

                HStack(spacing: 10) {
                    Text(AppInfo.donationAddress)
                        .font(.system(size: 13.5, weight: .medium).monospaced())
                        .foregroundStyle(Theme.text)
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer(minLength: 8)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(AppInfo.donationAddress, forType: .string)
                        withAnimation { copied = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { withAnimation { copied = false } }
                    } label: {
                        Label(copied ? "Скопировано" : "Скопировать", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.premium)
                }
                .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 6)
                .background(Color.white.opacity(0.05), in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.stroke))

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn).font(.system(size: 11))
                    Text("Отправляйте только USDT в сети TRON (TRC20). Перевод в другой сети (ERC20, BEP20 и т. п.) или другой монеты будет потерян.")
                        .font(.system(size: 11.5)).foregroundStyle(Theme.text3).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.card)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(RadialGradient(colors: [Theme.accent.opacity(0.14), .clear], center: .init(x: 0.12, y: 0.5), startRadius: 0, endRadius: 360))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.accent.opacity(0.35)))
    }
}
