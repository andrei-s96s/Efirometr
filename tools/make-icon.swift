// Renders the app icon (1024×1024 PNG). Usage: swift tools/make-icon.swift <out.png>
import SwiftUI
import AppKit

struct Icon: View {
    let accent = Color(red: 1.0, green: 0.26, blue: 0.36)
    let violet = Color(red: 0.85, green: 0.14, blue: 0.44)
    let cyan = Color(red: 1.0, green: 0.52, blue: 0.36)   // warm coral highlight
    let green = Color(red: 0.32, green: 0.87, blue: 0.58)

    var body: some View {
        ZStack {
            // macOS icon grid: 824 pt body inside a 1024 canvas.
            RoundedRectangle(cornerRadius: 186, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.07, blue: 0.10), Color(red: 0.04, green: 0.03, blue: 0.045)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: 186, style: .continuous)
                        .fill(RadialGradient(colors: [accent.opacity(0.35), .clear], center: .init(x: 0.3, y: 0.15), startRadius: 0, endRadius: 520))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 186, style: .continuous)
                        .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 3)
                )
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.45), radius: 24, y: 14)

            // Wi‑Fi arcs
            ZStack {
                ForEach(0..<3) { i in
                    let r = CGFloat(130 + i * 105)
                    Circle()
                        .trim(from: 0.125, to: 0.375)
                        .stroke(LinearGradient(colors: [cyan, accent, violet], startPoint: .leading, endPoint: .trailing),
                                style: StrokeStyle(lineWidth: 58, lineCap: .round))
                        .frame(width: r * 2, height: r * 2)
                        .rotationEffect(.degrees(180))
                        .opacity(1 - Double(i) * 0.12)
                }
                Circle().fill(LinearGradient(colors: [cyan, accent], startPoint: .top, endPoint: .bottom))
                    .frame(width: 92, height: 92)
            }
            .offset(y: 120)
            .shadow(color: accent.opacity(0.7), radius: 30)

            // Pulse line — the "doctor"
            PulseLine()
                .stroke(green, style: StrokeStyle(lineWidth: 26, lineCap: .round, lineJoin: .round))
                .frame(width: 560, height: 170)
                .offset(y: 285)
                .shadow(color: green.opacity(0.8), radius: 18)
        }
        .frame(width: 1024, height: 1024)
    }
}

struct PulseLine: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let mid = r.midY
        p.move(to: CGPoint(x: r.minX, y: mid))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.30, y: mid))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.40, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.52, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.62, y: mid))
        p.addLine(to: CGPoint(x: r.maxX, y: mid))
        return p
    }
}

@MainActor func render() {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    guard let cg = renderer.cgImage else { fatalError("render failed") }
    let rep = NSBitmapImageRep(cgImage: cg)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
}
MainActor.assumeIsolated { render() }
