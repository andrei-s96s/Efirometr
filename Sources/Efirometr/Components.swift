import SwiftUI

// MARK: - Theme

enum Theme {
    static let bg = Color(red: 0.035, green: 0.039, blue: 0.058)
    static let bgRaised = Color(red: 0.07, green: 0.075, blue: 0.105)
    static let card = Color.white.opacity(0.035)
    static let stroke = Color.white.opacity(0.08)
    static let text = Color.white.opacity(0.94)
    static let text2 = Color.white.opacity(0.62)
    static let text3 = Color.white.opacity(0.38)

    static let accent = Color(red: 1.0, green: 0.26, blue: 0.36)    // crimson
    static let violet = Color(red: 0.85, green: 0.14, blue: 0.44)   // raspberry, second stop of the accent gradient
    static let cyan = Color(red: 0.27, green: 0.86, blue: 0.92)
    static let pink = Color(red: 1.0, green: 0.42, blue: 0.66)
    static let good = Color(red: 0.32, green: 0.87, blue: 0.58)
    static let fair = Color(red: 0.75, green: 0.88, blue: 0.35)
    static let warn = Color(red: 1.0, green: 0.71, blue: 0.32)
    static let bad = Color(red: 1.0, green: 0.45, blue: 0.28)      // scarlet-orange, distinct from the crimson accent

    static let accentGradient = LinearGradient(colors: [accent, violet], startPoint: .leading, endPoint: .trailing)
    static let strokeGradient = LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom)

    static func number(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    static let eyebrow = Font.system(size: 11, weight: .semibold)
}

struct AppBackground: View {
    var body: some View {
        ZStack {
            Theme.bg
            RadialGradient(colors: [Theme.accent.opacity(0.16), .clear], center: .init(x: 0.15, y: 0), startRadius: 0, endRadius: 520)
            RadialGradient(colors: [Theme.violet.opacity(0.12), .clear], center: .init(x: 0.95, y: 0.1), startRadius: 0, endRadius: 480)
            RadialGradient(colors: [Theme.cyan.opacity(0.05), .clear], center: .init(x: 0.5, y: 1), startRadius: 0, endRadius: 600)
        }
        .ignoresSafeArea()
    }
}

enum Palette {
    static func score(_ value: Double) -> Color {
        switch value {
        case 0.85...: return Theme.good
        case 0.7..<0.85: return Theme.fair
        case 0.5..<0.7: return Theme.warn
        default: return Theme.bad
        }
    }

    static func rssi(_ rssi: Int) -> Color { score(Analyzer.clamp(Double(rssi + 85) / 30)) }

    static let networkHues: [Color] = [Theme.violet, Theme.pink, Theme.cyan, .indigo, .mint, .teal, .orange, .yellow, .purple]

    static func network(_ id: String) -> Color {
        networkHues[abs(id.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }) % networkHues.count]
    }
}

// MARK: - Snapshot support

private struct SnapshotModeKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var snapshotMode: Bool {
        get { self[SnapshotModeKey.self] }
        set { self[SnapshotModeKey.self] = newValue }
    }
}

/// ScrollView that steps aside when rendering offscreen snapshots (ImageRenderer can't draw scroll content).
struct SnapshotScroll<Content: View>: View {
    @Environment(\.snapshotMode) private var snapshot
    @ViewBuilder var content: Content

    var body: some View {
        if snapshot { content } else { ScrollView { content }.scrollIndicators(.never) }
    }
}

// MARK: - Surfaces

struct GlassSurface: ViewModifier {
    var radius: CGFloat = 18
    var fill: Color = Theme.card

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Theme.strokeGradient, lineWidth: 1))
    }
}

extension View {
    func glass(radius: CGFloat = 18, fill: Color = Theme.card) -> some View { modifier(GlassSurface(radius: radius, fill: fill)) }
}

struct Eyebrow: View {
    var text: String
    var icon: String?
    var tint: Color = Theme.text2

    var body: some View {
        HStack(spacing: 6) {
            if let icon { Image(systemName: icon).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent) }
            Text(text.uppercased()).font(Theme.eyebrow).tracking(1.1).foregroundStyle(tint)
        }
    }
}

struct Card<Content: View>: View {
    var title: String?
    var icon: String?
    var hint: Hint?
    var trailing: AnyView?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, icon: String? = nil, hint: Hint? = nil, trailing: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.hint = hint
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if title != nil || trailing != nil {
                HStack(spacing: 6) {
                    if let title { Eyebrow(text: title, icon: icon) }
                    if let hint { HintButton(hint: hint) }
                    Spacer()
                    trailing
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass()
    }
}

// MARK: - Controls

struct PremiumButtonStyle: ButtonStyle {
    var primary = true
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(primary ? Color.white : Theme.text)
            .background {
                if primary {
                    Capsule().fill(Theme.accentGradient)
                        .shadow(color: Theme.accent.opacity(0.35), radius: 10, y: 3)
                } else {
                    Capsule().fill(Color.white.opacity(0.07))
                }
            }
            .overlay(Capsule().strokeBorder(Color.white.opacity(primary ? 0.18 : 0.1)))
            .opacity(enabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == PremiumButtonStyle {
    static var premium: PremiumButtonStyle { PremiumButtonStyle(primary: true) }
    static var premiumSecondary: PremiumButtonStyle { PremiumButtonStyle(primary: false) }
}

struct SegmentedControl<T: Hashable>: View {
    var options: [T]
    @Binding var selection: T
    var label: (T) -> String
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { o in
                let on = o == selection
                Text(label(o))
                    .font(.system(size: 12, weight: on ? .semibold : .medium))
                    .foregroundStyle(on ? Theme.text : Theme.text2)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background {
                        if on {
                            Capsule().fill(Color.white.opacity(0.12))
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.14)))
                                .matchedGeometryEffect(id: "seg", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                    .onTapGesture { withAnimation(.spring(duration: 0.3)) { selection = o } }
            }
        }
        .padding(3)
        .background(Color.white.opacity(0.05), in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.stroke))
    }
}

/// Thin bar with coloured fill and optional threshold ticks.
struct GaugeBar: View {
    var value: Double
    var tint: Color
    var ticks: [Double] = []
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                Capsule()
                    .fill(LinearGradient(colors: [tint.opacity(0.55), tint], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(height, g.size.width * Analyzer.clamp(value)))
                ForEach(ticks, id: \.self) { t in
                    Rectangle().fill(Color.white.opacity(0.25)).frame(width: 1, height: height + 4).offset(x: g.size.width * t)
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - Data display

struct ScoreRing: View {
    var score: Int
    var size: CGFloat = 150
    var lineWidth: CGFloat = 12
    var showCaption = true

    var body: some View {
        let v = Double(score) / 100
        let tint = Palette.score(v)
        ZStack {
            Circle().stroke(Color.white.opacity(0.07), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: v)
                .stroke(LinearGradient(colors: [tint, tint.opacity(0.6)], startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.9), value: score)
            VStack(spacing: 0) {
                Text("\(score)")
                    .font(Theme.number(size * 0.34, .bold))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
                    .animation(.default, value: score)
                if showCaption { Text("из 100").font(.system(size: max(9, size * 0.075), weight: .medium)).foregroundStyle(Theme.text3) }
            }
        }
        .frame(width: size, height: size)
    }
}

struct MetricCard: View {
    var title: String
    var value: String
    var unit: String = ""
    var caption: String
    var icon: String
    var tint: Color
    var progress: Double? = nil
    var ticks: [Double] = []
    var hint: Hint? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(title.uppercased()).font(Theme.eyebrow).tracking(1).foregroundStyle(Theme.text2)
                Spacer()
                if let hint { HintButton(hint: hint) }
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value).font(Theme.number(28)).foregroundStyle(Theme.text).lineLimit(1).minimumScaleFactor(0.6)
                if !unit.isEmpty { Text(unit).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text3) }
            }
            if let progress { GaugeBar(value: progress, tint: tint, ticks: ticks) }
            Spacer(minLength: 0)
            Text(caption).font(.system(size: 12)).foregroundStyle(tint.opacity(0.9)).lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 136, alignment: .topLeading)
        .glass(radius: 16)
    }
}

struct Badge: View {
    var text: String
    var icon: String? = nil
    var tint: Color = Theme.accent

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 9, weight: .bold)) }
            Text(text)
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .foregroundStyle(tint)
        .background(tint.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.25)))
    }
}

struct SignalBars: View {
    var rssi: Int

    var body: some View {
        let level = rssi >= -55 ? 4 : rssi >= -67 ? 3 : rssi >= -75 ? 2 : rssi >= -85 ? 1 : 0
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i < level ? Palette.rssi(rssi) : Color.white.opacity(0.14))
                    .frame(width: 4, height: CGFloat(5 + i * 3))
            }
        }
    }
}

struct RecommendationRow: View {
    var rec: Recommendation
    @State var expanded = false
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: rec.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(rec.severity.color)
                    .frame(width: 36, height: 36)
                    .background(rec.severity.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(rec.severity.color.opacity(0.25)))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(rec.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                        Spacer()
                        Text(rec.severity.label.uppercased()).font(.system(size: 9.5, weight: .bold)).tracking(0.8)
                            .foregroundStyle(rec.severity.color)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(rec.severity.color.opacity(0.12), in: Capsule())
                    }
                    Text(rec.detail).font(.system(size: 13)).foregroundStyle(Theme.text2).fixedSize(horizontal: false, vertical: true).lineSpacing(2)
                    if !rec.steps.isEmpty {
                        HStack(spacing: 4) {
                            Text(expanded ? "Скрыть инструкцию" : "Как сделать · шагов: \(rec.steps.count)")
                            Image(systemName: "chevron.down").rotationEffect(.degrees(expanded ? 180 : 0))
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 4)
                    }
                }
            }
            if expanded && !rec.steps.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(rec.steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(i + 1)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 20, height: 20)
                                .background(Theme.accent.opacity(0.14), in: Circle())
                            Text(.init(step)).font(.system(size: 13)).foregroundStyle(Theme.text).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.leading, 50)
                .padding(.top, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(hover ? Color.white.opacity(0.03) : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { if !rec.steps.isEmpty { withAnimation(.spring(duration: 0.35)) { expanded.toggle() } } }
    }
}
