import SwiftUI

/// Data that changes every second. Kept apart from `WiFiMonitor` so only the views
/// that show live numbers re-render each tick; everything else updates every few seconds.
@MainActor
final class LiveData: ObservableObject {
    static let shared = LiveData()
    static let capacity = 120

    @Published var link: LinkSnapshot?
    @Published var downRate: Double = 0
    @Published var upRate: Double = 0
    @Published var history: [SignalSample] = []
    @Published var throughput: [ThroughputSample] = []

    func append(_ s: SignalSample) {
        history.append(s)
        if history.count > Self.capacity { history.removeFirst(history.count - Self.capacity) }
    }

    func append(_ s: ThroughputSample) {
        throughput.append(s)
        if throughput.count > Self.capacity { throughput.removeFirst(throughput.count - Self.capacity) }
    }
}

/// Lightweight scrolling line chart drawn with Canvas — far cheaper than Swift Charts for 1 Hz updates.
struct LiveChart: View {
    struct Series {
        var values: [Double]
        var color: Color
        var fill = false
        var dashed = false
        var width: CGFloat = 2
    }

    var series: [Series]
    var capacity = LiveData.capacity
    /// Fixed y range; nil means 0...nice max of the data.
    var range: ClosedRange<Double>? = nil
    var minTop: Double = 1
    var gridLines = 4
    var label: (Double) -> String = { String(format: "%.0f", $0) }
    var threshold: (value: Double, text: String, color: Color)? = nil

    var body: some View {
        Canvas { ctx, size in
            let labelW: CGFloat = 34
            let plot = CGRect(x: 0, y: 6, width: size.width - labelW, height: size.height - 12)
            let r = range ?? 0...niceCeil(max(minTop, series.flatMap(\.values).max() ?? minTop))
            let span = max(r.upperBound - r.lowerBound, 0.0001)
            func y(_ v: Double) -> CGFloat { plot.maxY - CGFloat((min(max(v, r.lowerBound), r.upperBound) - r.lowerBound) / span) * plot.height }

            for i in 0...gridLines {
                let v = r.lowerBound + span * Double(i) / Double(gridLines)
                let yy = y(v)
                var p = Path(); p.move(to: CGPoint(x: plot.minX, y: yy)); p.addLine(to: CGPoint(x: plot.maxX, y: yy))
                ctx.stroke(p, with: .color(.white.opacity(0.06)), lineWidth: 0.5)
                ctx.draw(Text(label(v)).font(.system(size: 9.5).monospacedDigit()).foregroundStyle(Theme.text3),
                         at: CGPoint(x: plot.maxX + 6, y: yy), anchor: .leading)
            }

            if let t = threshold {
                let yy = y(t.value)
                var p = Path(); p.move(to: CGPoint(x: plot.minX, y: yy)); p.addLine(to: CGPoint(x: plot.maxX, y: yy))
                ctx.stroke(p, with: .color(t.color.opacity(0.55)), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                ctx.draw(Text(t.text).font(.system(size: 10)).foregroundStyle(t.color), at: CGPoint(x: plot.minX + 4, y: yy - 3), anchor: .bottomLeading)
            }

            let step = plot.width / CGFloat(max(capacity - 1, 1))
            for s in series where s.values.count > 1 {
                let offset = capacity - s.values.count
                var line = Path()
                for (i, v) in s.values.enumerated() {
                    let pt = CGPoint(x: plot.minX + CGFloat(offset + i) * step, y: y(v))
                    i == 0 ? line.move(to: pt) : line.addLine(to: pt)
                }
                if s.fill {
                    var area = line
                    area.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
                    area.addLine(to: CGPoint(x: plot.minX + CGFloat(offset) * step, y: plot.maxY))
                    area.closeSubpath()
                    ctx.fill(area, with: .linearGradient(Gradient(colors: [s.color.opacity(0.35), s.color.opacity(0)]),
                                                         startPoint: CGPoint(x: 0, y: plot.minY), endPoint: CGPoint(x: 0, y: plot.maxY)))
                }
                ctx.stroke(line, with: .color(s.color),
                           style: StrokeStyle(lineWidth: s.width, lineCap: .round, lineJoin: .round, dash: s.dashed ? [3, 3] : []))
            }
        }
    }

    private func niceCeil(_ v: Double) -> Double {
        let mag = pow(10, floor(log10(v)))
        for m in [1.0, 2, 2.5, 5, 10] where m * mag >= v { return m * mag }
        return 10 * mag
    }
}

/// Live speed tiles and charts reused by Overview, Monitor and the menu bar panel.
struct LiveSignalChart: View {
    @EnvironmentObject var live: LiveData

    var body: some View {
        LiveChart(series: [
            .init(values: live.history.map { Double($0.rssi) }, color: Theme.accent, fill: true),
            .init(values: live.history.map { Double($0.noise) }, color: Theme.text3, dashed: true, width: 1),
        ], range: -100 ... -20, label: { "\(Int($0))" }, threshold: (-67, "−67 dBm — минимум для видео", Theme.warn))
    }
}

struct LiveThroughputChart: View {
    @EnvironmentObject var live: LiveData
    var showLabels = true

    var body: some View {
        LiveChart(series: [
            .init(values: live.throughput.map { $0.down * 8 / 1e6 }, color: Theme.cyan, fill: true),
            .init(values: live.throughput.map { $0.up * 8 / 1e6 }, color: Theme.pink),
        ], minTop: 1, gridLines: showLabels ? 4 : 2, label: { $0 >= 10 ? String(format: "%.0f", $0) : String(format: "%.1f", $0) })
    }
}
