import Foundation

/// One-time import from the app's previous name ("Wi‑Fi Доктор", id local.wifidoctor):
/// settings and the journal / speed-test / survey files.
enum Migration {
    private static let oldBundleID = "local.wifidoctor"
    private static let doneKey = "migratedFromWiFiDoctor"

    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }

        if let old = defaults.persistentDomain(forName: oldBundleID) {
            for (key, value) in old where defaults.object(forKey: key) == nil && !key.hasPrefix("NS") {
                defaults.set(value, forKey: key)
            }
        }

        let fm = FileManager.default
        let oldDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WiFiDoctor")
        let newDir = AppInfo.supportDirectory
        for name in ["journal.json", "speedtests.json", "survey.json"] {
            let from = oldDir.appendingPathComponent(name), to = newDir.appendingPathComponent(name)
            if fm.fileExists(atPath: from.path) && !fm.fileExists(atPath: to.path) {
                try? fm.moveItem(at: from, to: to)
            }
        }
        if (try? fm.contentsOfDirectory(atPath: oldDir.path))?.isEmpty == true { try? fm.removeItem(at: oldDir) }
    }
}
