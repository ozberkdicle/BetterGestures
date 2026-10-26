import GestureCore
import SwiftUI

/// draws fingers on each trackpad live and lists gesture decisions; the place to look when tuning.
struct LivePane: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            TimelineView(.animation(minimumInterval: 1.0 / 60)) { _ in
                let frames = state.latestFrames()
                HStack(alignment: .top, spacing: 20) {
                    if state.devices.isEmpty {
                        ContentUnavailableView("Trackpad bulunamadı", systemImage: "rectangle.dashed")
                    }
                    ForEach(state.devices) { device in
                        TrackpadView(device: device, frame: frames[device.id])
                    }
                }
            }
            .frame(height: 250)
            .padding(20)

            Divider()
            HistoryView(state: state)
        }
    }
}

private struct TrackpadView: View {
    let device: TouchSource.Device
    let frame: TouchFrame?

    private var touches: [TouchPoint] { frame?.touches ?? [] }
    private var fingerCount: Int { touches.filter { $0.phase == .making || $0.phase == .touching }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(device.name).font(.headline)
                Spacer()
                Text(fingerCount == 0 ? "boş" : "\(fingerCount) parmak")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Canvas { context, size in
                let pad = RoundedRectangle(cornerRadius: 14).path(in: CGRect(origin: .zero, size: size))
                context.fill(pad, with: .color(.primary.opacity(0.05)))
                context.stroke(pad, with: .color(.primary.opacity(0.18)), lineWidth: 1)

                for t in touches {
                    let p = CGPoint(x: t.x * size.width, y: (1 - t.y) * size.height)
                    let pressed = t.phase == .making || t.phase == .touching
                    let r: CGFloat = pressed ? 15 : 11
                    let circle = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                    if pressed {
                        context.fill(circle, with: .color(.accentColor.opacity(0.85)))
                        // velocity vector (where it'll be in 0.15 s).
                        var v = Path()
                        v.move(to: p)
                        v.addLine(to: CGPoint(x: p.x + t.vx * size.width * 0.15, y: p.y - t.vy * size.height * 0.15))
                        context.stroke(v, with: .color(.accentColor), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    } else {
                        context.stroke(circle, with: .color(.secondary.opacity(0.7)),
                                       style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                    }
                    context.draw(Text(verbatim: "\(t.id)").font(.caption2.monospacedDigit()).foregroundStyle(pressed ? .white : .secondary),
                                 at: p)
                }
            }
            .aspectRatio(device.width / max(device.height, 1), contentMode: .fit)
        }
        .frame(maxWidth: 360)
    }
}

private struct HistoryView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Jest geçmişi").font(.headline)
                Text("tanınan ve reddedilen (gerekçesiyle)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Temizle") { state.clearHistory() }
                    .disabled(state.history.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)

            if state.history.isEmpty {
                ContentUnavailableView("Henüz jest yok", systemImage: "hand.tap",
                                       description: Text("Trackpad'de bir jest deneyin."))
                    .frame(maxHeight: .infinity)
            } else {
                List(state.history) { entry in
                    HistoryRow(entry: entry)
                }
                .listStyle(.inset)
            }
        }
    }
}

private struct HistoryRow: View {
    let entry: AppState.LogEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.recognized ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(entry.recognized ? .green : .orange)
            Text(entry.gesture.title)
                .frame(width: 150, alignment: .leading)
            Text(detail)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text(entry.date, format: .dateTime.hour().minute().second())
                .monospacedDigit()
                .foregroundStyle(.tertiary)
        }
    }

    private var detail: String {
        guard entry.recognized else { return entry.detail }
        guard let shortcut = try? KeyShortcut(parsing: entry.detail) else { return entry.detail }
        let keys = KeyGlyphs.display(shortcut)
        return entry.sent ? "→ \(keys)" : String(localized: "\(keys) · gönderilmedi")
    }
}
