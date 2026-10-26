import GestureCore
import SwiftUI

/// icon that shows a gesture as finger dots on a tiny trackpad.
struct GestureGlyph: View {
    let gesture: Gesture
    var highlighted = false

    var body: some View {
        Canvas { context, size in
            let pad = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            let shape = RoundedRectangle(cornerRadius: 7).path(in: pad)
            context.fill(shape, with: .color(highlighted ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05)))
            context.stroke(shape, with: .color(highlighted ? Color.accentColor : Color.primary.opacity(0.25)), lineWidth: 1)

            let ink = highlighted ? Color.accentColor : Color.primary.opacity(0.75)
            let r: CGFloat = 3.6
            let mid = CGPoint(x: pad.midX, y: pad.midY)

            func finger(_ p: CGPoint, tap: Bool = false, radius r: CGFloat = r) {
                context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(ink))
                if tap {
                    let ring = r + 1.8
                    context.stroke(Path(ellipseIn: CGRect(x: p.x - ring, y: p.y - ring, width: ring * 2, height: ring * 2)),
                                   with: .color(ink.opacity(0.55)), lineWidth: 1)
                }
            }

            func row(_ count: Int, center: CGPoint, tap: Bool = false) {
                // shrinks so five fingers fit.
                let radius: CGFloat = count >= 5 ? 2.7 : r
                let spacing: CGFloat = count >= 5 ? 8.6 : (tap ? 10.5 : 9)
                let start = center.x - spacing * CGFloat(count - 1) / 2
                for i in 0..<count {
                    // middle fingers sit a bit higher, like a real hand.
                    let lift: CGFloat = (i == 0 || i == count - 1) ? 0 : -2
                    finger(CGPoint(x: start + spacing * CGFloat(i), y: center.y + lift), tap: tap, radius: radius)
                }
            }

            /// small mark in the top right corner (e.g. "2×", a timer).
            func badge(_ content: Text) {
                context.draw(content.font(.system(size: 8, weight: .bold)).foregroundStyle(ink),
                             at: CGPoint(x: pad.maxX - 7, y: pad.minY + 7))
            }

            func arrow(from a: CGPoint, to b: CGPoint) {
                var line = Path()
                line.move(to: a)
                line.addLine(to: b)
                context.stroke(line, with: .color(ink), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                let angle = atan2(b.y - a.y, b.x - a.x)
                var head = Path()
                for side in [-1.0, 1.0] {
                    head.move(to: b)
                    head.addLine(to: CGPoint(x: b.x - 4.5 * cos(angle + side * .pi / 5),
                                             y: b.y - 4.5 * sin(angle + side * .pi / 5)))
                }
                context.stroke(head, with: .color(ink), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }

            switch gesture {
            case .threeFingerTap:
                row(3, center: mid, tap: true)
            case .fourFingerTap:
                row(4, center: mid, tap: true)
            case .fiveFingerTap:
                row(5, center: CGPoint(x: mid.x, y: mid.y + 1), tap: true)
            case .threeFingerDoubleTap:
                row(3, center: CGPoint(x: mid.x - 2, y: mid.y + 2), tap: true)
                badge(Text(verbatim: "2×"))
            case .fourFingerDoubleTap:
                row(4, center: CGPoint(x: mid.x - 2, y: mid.y + 3), tap: true)
                badge(Text(verbatim: "2×"))
            case .fiveFingerDoubleTap:
                row(5, center: CGPoint(x: mid.x - 2, y: mid.y + 4), tap: true)
                badge(Text(verbatim: "2×"))
            case .threeFingerClick:
                row(3, center: CGPoint(x: mid.x - 3, y: mid.y + 3))
                badge(Text(Image(systemName: "cursorarrow.click")))
            case .fourFingerClick:
                row(4, center: CGPoint(x: mid.x - 3, y: mid.y + 3))
                badge(Text(Image(systemName: "cursorarrow.click")))
            case .threeFingerHold:
                row(3, center: CGPoint(x: mid.x - 3, y: mid.y + 2))
                badge(Text(Image(systemName: "timer")))
            case .tipTapLeft, .tipTapRight:
                let side: CGFloat = gesture == .tipTapRight ? 1 : -1
                finger(CGPoint(x: mid.x - side * 6, y: mid.y + 2))
                finger(CGPoint(x: mid.x + side * 8, y: mid.y - 2), tap: true)
            case .twoAnchorTipTapLeft, .twoAnchorTipTapRight:
                let side: CGFloat = gesture == .twoAnchorTipTapRight ? 1 : -1
                finger(CGPoint(x: mid.x - side * 12, y: mid.y + 2))
                finger(CGPoint(x: mid.x - side * 3, y: mid.y))
                finger(CGPoint(x: mid.x + side * 11, y: mid.y - 2), tap: true)
            case .twoFingerTipTapLeft, .twoFingerTipTapRight:
                let side: CGFloat = gesture == .twoFingerTipTapRight ? 1 : -1
                finger(CGPoint(x: mid.x - side * 11, y: mid.y + 2))
                finger(CGPoint(x: mid.x + side * 2, y: mid.y - 1), tap: true)
                finger(CGPoint(x: mid.x + side * 13, y: mid.y - 2), tap: true)
            case .threeFingerSwipeLeft:
                row(3, center: CGPoint(x: mid.x + 6, y: mid.y - 3))
                arrow(from: CGPoint(x: mid.x + 10, y: mid.y + 8), to: CGPoint(x: mid.x - 14, y: mid.y + 8))
            case .threeFingerSwipeRight:
                row(3, center: CGPoint(x: mid.x - 6, y: mid.y - 3))
                arrow(from: CGPoint(x: mid.x - 10, y: mid.y + 8), to: CGPoint(x: mid.x + 14, y: mid.y + 8))
            case .threeFingerSwipeUp:
                row(3, center: CGPoint(x: mid.x - 5, y: mid.y + 4))
                arrow(from: CGPoint(x: mid.x + 14, y: mid.y + 9), to: CGPoint(x: mid.x + 14, y: mid.y - 9))
            case .threeFingerSwipeDown:
                row(3, center: CGPoint(x: mid.x - 5, y: mid.y - 4))
                arrow(from: CGPoint(x: mid.x + 14, y: mid.y - 9), to: CGPoint(x: mid.x + 14, y: mid.y + 9))
            }
        }
        .frame(width: 54, height: 38)
        .animation(.easeOut(duration: 0.25), value: highlighted)
        .accessibilityLabel(gesture.title)
    }
}
