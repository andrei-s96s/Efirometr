import SwiftUI
import AppKit

/// What's drawn inside the menu bar button. Uses `.primary` so it follows the menu bar's light/dark look.
struct StatusLabel: View {
    @EnvironmentObject var monitor: WiFiMonitor
    @EnvironmentObject var live: LiveData
    @EnvironmentObject var settings: AppSettings
    var mode: MenuBarMode? = nil
    var forceDark = false

    var body: some View {
        let m = mode ?? settings.menuBarMode
        HStack(spacing: 4) {
            if m != .speed { icon }
            switch m {
            case .speedSignal, .speed:
                VStack(alignment: .trailing, spacing: -2) {
                    Text("↑ " + Format.speed(live.upRate, compact: true))
                    Text("↓ " + Format.speed(live.downRate, compact: true))
                }
                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                .fixedSize()
            case .score:
                Text("\(monitor.assessment.score)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(settings.coloredIcon ? Palette.score(Double(monitor.assessment.score) / 100) : .primary)
            case .icon:
                EmptyView()
            }
        }
        .foregroundStyle(forceDark ? Color.white : Color.primary)
        .lineLimit(1)
        .frame(width: m.width, height: 22)
    }

    private var icon: some View {
        let l = live.link
        let connected = l?.isConnected == true
        let level = connected ? Analyzer.clamp(Double(l!.rssi + 85) / 30) : 0
        return Image(systemName: connected ? "wifi" : "wifi.slash", variableValue: max(0.05, level))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(settings.coloredIcon && connected ? Palette.rssi(l!.rssi) : (forceDark ? .white : .primary))
    }
}

/// Lets clicks fall through to the status bar button underneath.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class StatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: MenuBarMode.speedSignal.width + 8)
    private let popover = NSPopover()
    private var observer: Any?

    init(monitor: WiFiMonitor, settings: AppSettings) {
        super.init()
        guard let button = item.button else { return }
        let host = PassthroughHostingView(rootView: AnyView(StatusLabel().environmentObject(monitor).environmentObject(settings).environmentObject(LiveData.shared)))
        host.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(host)
        NSLayoutConstraint.activate([
            host.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            host.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
        button.target = self
        button.action = #selector(toggle)
        button.toolTip = AppInfo.name

        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self

        observer = settings.$menuBarMode.sink { [weak self] m in self?.item.length = m.width + 8 }
    }

    @objc private func toggle() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            // Built on demand and released on close so the hidden panel never re-renders in the background.
            popover.contentViewController = NSHostingController(rootView: MenuBarPanel()
                .environmentObject(WiFiMonitor.shared)
                .environmentObject(LiveData.shared)
                .environmentObject(AppSettings.shared)
                .environmentObject(SpeedTester.shared))
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func closePopover() { popover.performClose(nil) }
}

extension StatusItemController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
    }
}

/// Main window managed by AppKit so the app can start silently in the menu bar and hide from the Dock.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()
    private var window: NSWindow?

    func show(section: Section? = nil) {
        if let section { NavigationModel.shared.section = section }
        NSApp.setActivationPolicy(.regular)
        if window == nil {
            let host = NSHostingController(rootView: ContentView()
                .environmentObject(WiFiMonitor.shared)
                .environmentObject(LiveData.shared)
                .environmentObject(AppSettings.shared)
                .environmentObject(SpeedTester.shared)
                .environmentObject(Journal.shared)
                .environmentObject(NavigationModel.shared)
                .preferredColorScheme(.dark)
                .tint(Theme.accent))
            host.sceneBridgingOptions = [.toolbars, .title]
            let w = NSWindow(contentViewController: host)
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.title = AppInfo.name
            w.toolbar = NSToolbar(identifier: "main")
            w.toolbarStyle = .unified
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = NSColor(Theme.bg)
            w.setContentSize(NSSize(width: 1220, height: 840))
            w.contentMinSize = NSSize(width: 1000, height: 680)
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.setFrameAutosaveName("MainWindow")
            if !w.setFrameUsingName("MainWindow") { w.center() }
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }


    func windowWillClose(_ notification: Notification) {
        // Tear the SwiftUI hierarchy down: a closed-but-alive window keeps re-rendering.
        DispatchQueue.main.async {
            self.window?.contentViewController = nil
            self.window = nil
            if AppSettings.shared.hideDockWhenClosed { NSApp.setActivationPolicy(.accessory) }
        }
    }
}

@MainActor
final class NavigationModel: ObservableObject {
    static let shared = NavigationModel()
    @Published var section: Section? = .overview
}
