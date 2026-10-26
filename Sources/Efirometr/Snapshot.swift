import SwiftUI

/// Debug aid: `Efirometr --snapshot <dir>` renders each screen to PNG after the first scan and quits.
@MainActor
enum Snapshot {
    static func schedule(to dir: URL, demo: Bool = false) {
        let monitor = WiFiMonitor.shared
        if !demo {
            monitor.testLatency()
            AppTrafficMonitor.shared.start()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (demo ? 2 : 14)) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let summary = monitor.groups.map { g in
                "\(g.displayName) | mine=\(g.isMine) current=\(g.isCurrent) | " + g.radios.map { "\($0.channel.band.short):\($0.channel.number)/\($0.rssi)\($0.isSibling ? "s" : "")\($0.isCurrent ? "*" : "")[\($0.bssid ?? "-")]" }.joined(separator: " ")
            }.joined(separator: "\n")
            try? summary.write(to: dir.appendingPathComponent("groups.txt"), atomically: true, encoding: .utf8)
            render(OverviewView(), "overview", dir, monitor)
            render(AdviceView(), "advice", dir, monitor)
            render(NetworksView(), "networks", dir, monitor, width: 900)
            render(MonitorView(), "monitor", dir, monitor)
            render(ChannelsView(), "channels", dir, monitor)
            render(ChannelsView(startBand: .ghz2), "channels24", dir, monitor)
            render(DeviceView(), "device", dir, monitor)
            render(SpeedTestView(), "speed", dir, monitor)
            render(JournalView(), "journal", dir, monitor)
            render(SurveyView(), "survey", dir, monitor)
            render(AppTrafficView(), "apps", dir, monitor)
            render(SettingsView(), "settings", dir, monitor)
            render(DonateView(), "donate", dir, monitor)
            render(HStack(spacing: 20) { ForEach(MenuBarMode.allCases) { m in StatusLabel(mode: m, forceDark: true) } }.padding(8).background(Color.black), "statuslabel", dir, monitor, width: 330)
            render(MenuBarPanel().fixedSize(), "menubar", dir, monitor, width: 320)
            NSApp.terminate(nil)
        }
    }

    private static func render<V: View>(_ view: V, _ name: String, _ dir: URL, _ monitor: WiFiMonitor, width: CGFloat = 1100) {
        let content = view
            .environmentObject(monitor)
            .environmentObject(AppSettings.shared)
            .environmentObject(LiveData.shared)
            .environmentObject(NavigationModel.shared)
            .environmentObject(SpeedTester.shared)
            .environmentObject(Journal.shared)
            .environment(\.snapshotMode, true)
            .environment(\.colorScheme, .dark)
            .frame(width: width)
            .background(AppBackground())
        let r = ImageRenderer(content: content)
        r.scale = 1.5
        guard let img = r.nsImage, let tiff = img.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: dir.appendingPathComponent("\(name).png"))
    }
}
