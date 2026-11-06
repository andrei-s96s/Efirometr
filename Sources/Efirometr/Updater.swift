import SwiftUI
import UserNotifications

struct ReleaseInfo: Equatable {
    let version: String
    let pageURL: URL
    let downloadURL: URL?
    let notes: String
    let date: Date?
}

/// Checks GitHub Releases for a newer version: once a day in the background, or on demand.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    static let repo = "andrei-s96s/Efirometr"

    enum State: Equatable {
        case idle, checking, upToDate, failed(String)
        case available(ReleaseInfo)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastCheck: Date?
    @Published private(set) var skippedVersion: String?

    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private let interval: TimeInterval = 24 * 3600

    private init() {
        lastCheck = defaults.object(forKey: "lastUpdateCheck") as? Date
        skippedVersion = defaults.string(forKey: "skippedVersion")
    }

    /// Newer release the user hasn't skipped.
    var available: ReleaseInfo? {
        if case .available(let r) = state, r.version != skippedVersion { return r }
        return nil
    }

    func start() {
        guard !AppInfo.isDemo, timer == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.checkIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
    }

    private func checkIfDue() {
        guard AppSettings.shared.autoCheckUpdates else { return }
        if let last = lastCheck, Date().timeIntervalSince(last) < interval, state != .idle { return }
        Task { await check() }
    }

    func check() async {
        guard state != .checking else { return }
        state = .checking
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest")!, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Efirometr/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else {
                state = .failed(String(localized: "Не удалось получить данные о релизе"))
                return
            }
            let assets = json["assets"] as? [[String: Any]] ?? []
            let dmg = assets.first { ($0["name"] as? String)?.hasSuffix(".dmg") == true }?["browser_download_url"] as? String
            let release = ReleaseInfo(version: tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV")),
                                      pageURL: page,
                                      downloadURL: dmg.flatMap(URL.init(string:)),
                                      notes: json["body"] as? String ?? "",
                                      date: (json["published_at"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) })
            lastCheck = .now
            defaults.set(lastCheck, forKey: "lastUpdateCheck")
            if Self.isNewer(release.version, than: AppInfo.version) {
                state = .available(release)
                notifyOnce(release)
            } else {
                state = .upToDate
            }
        } catch {
            state = .failed(String(localized: "Нет связи с GitHub"))
        }
    }

    func skip(_ r: ReleaseInfo) {
        skippedVersion = r.version
        defaults.set(r.version, forKey: "skippedVersion")
    }

    func download(_ r: ReleaseInfo) { NSWorkspace.shared.open(r.downloadURL ?? r.pageURL) }
    func openNotes(_ r: ReleaseInfo) { NSWorkspace.shared.open(r.pageURL) }

    /// One notification per new version.
    private func notifyOnce(_ r: ReleaseInfo) {
        guard defaults.string(forKey: "notifiedVersion") != r.version, r.version != skippedVersion else { return }
        defaults.set(r.version, forKey: "notifiedVersion")
        let content = UNMutableNotificationContent()
        content.title = String(format: String(localized: "Доступен %@ %@"), AppInfo.name, r.version)
        content.body = String(format: String(localized: "У вас версия %@. Откройте приложение, чтобы скачать обновление."), AppInfo.version)
        content.userInfo = ["section": Section.overview.rawValue]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "update-\(r.version)", content: content, trigger: nil))
    }

    /// Numeric comparison of dotted versions: 1.10.0 > 1.9.2.
    nonisolated static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

// MARK: - UI

/// Banner shown on the Overview when a newer release exists.
struct UpdateBanner: View {
    @ObservedObject var updater = UpdateChecker.shared

    var body: some View {
        if let r = updater.available {
            HStack(spacing: 14) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 22)).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Доступна версия \(r.version)").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                    Text("У вас \(AppInfo.version). Если ставили через Homebrew: brew upgrade --cask efirometr")
                        .font(.system(size: 12)).foregroundStyle(Theme.text3)
                }
                Spacer(minLength: 8)
                Button("Пропустить") { updater.skip(r) }.buttonStyle(.premiumSecondary)
                Button("Что нового") { updater.openNotes(r) }.buttonStyle(.premiumSecondary)
                Button { updater.download(r) } label: { Label("Скачать", systemImage: "arrow.down") }.buttonStyle(.premium)
            }
            .padding(16)
            .glass(radius: 16, fill: Theme.accent.opacity(0.08))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.accent.opacity(0.4)))
        }
    }
}

struct UpdateSettingsCard: View {
    @EnvironmentObject var settings: AppSettings
    @ObservedObject var updater = UpdateChecker.shared

    var body: some View {
        Card(String(localized: "Обновления"), icon: "arrow.triangle.2.circlepath") {
            Toggle(isOn: $settings.autoCheckUpdates) {
                SettingRow(title: String(localized: "Проверять обновления автоматически"),
                           detail: String(localized: "Раз в сутки приложение спрашивает GitHub, вышла ли новая версия. Больше ничего не отправляется.")) { EmptyView() }
            }.toggleStyle(.premium)
            HStack(spacing: 12) {
                statusIcon
                Text(statusText).font(.system(size: 12.5)).foregroundStyle(Theme.text2)
                Spacer()
                if let r = updater.available {
                    Button { updater.download(r) } label: { Label("Скачать \(r.version)", systemImage: "arrow.down") }.buttonStyle(.premium)
                }
                Button(updater.state == .checking ? String(localized: "Проверяю…") : String(localized: "Проверить сейчас")) { Task { await updater.check() } }
                    .buttonStyle(.premiumSecondary)
                    .disabled(updater.state == .checking)
            }
        }
    }

    @ViewBuilder private var statusIcon: some View {
        switch updater.state {
        case .checking: ProgressView().controlSize(.small)
        case .available: Image(systemName: "arrow.down.circle.fill").foregroundStyle(Theme.accent)
        case .upToDate: Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.warn)
        case .idle: Image(systemName: "clock").foregroundStyle(Theme.text3)
        }
    }

    private var statusText: String {
        let when = updater.lastCheck.map { " · " + String(format: String(localized: "проверено %@"), $0.formatted(date: .abbreviated, time: .shortened)) } ?? ""
        switch updater.state {
        case .checking: return String(localized: "Проверяю…")
        case .available(let r): return String(format: String(localized: "Доступна версия %@ (у вас %@)"), r.version, AppInfo.version) + when
        case .upToDate: return String(format: String(localized: "У вас последняя версия %@"), AppInfo.version) + when
        case .failed(let e): return e
        case .idle: return String(format: String(localized: "Версия %@"), AppInfo.version) + when
        }
    }
}

/// Compact "update available" link for the sidebar footer and the menu bar panel.
struct UpdatePill: View {
    @ObservedObject var updater = UpdateChecker.shared

    var body: some View {
        if let r = updater.available {
            Button { updater.download(r) } label: {
                Label("Обновление \(r.version)", systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .help("Скачать новую версию")
        }
    }
}
