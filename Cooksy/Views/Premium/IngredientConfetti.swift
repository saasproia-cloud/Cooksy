import SwiftUI

/// Lightweight ingredient-confetti burst — used on plan selection and on
/// scroll-in animations across the paywall. Uses TimelineView for a single
/// 700 ms animation, then disappears.
struct IngredientConfetti: View {
    let trigger: Int  // bump to fire a new burst

    @State private var firedAt: Date?

    private let symbols = [
        "leaf.fill",
        "carrot.fill",
        "flame.fill",
        "drop.fill",
        "fork.knife"
    ]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas { context, size in
                guard let firedAt else { return }
                let elapsed = timeline.date.timeIntervalSince(firedAt)
                guard elapsed < 0.75 else { return }
                let progress = CGFloat(elapsed / 0.75)
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for i in 0..<8 {
                    let angle = Double(i) / 8 * 2 * .pi
                    let radius = 80 * progress
                    let x = center.x + radius * cos(angle)
                    let y = center.y + radius * sin(angle) - progress * 60
                    let opacity = 1.0 - progress
                    let symbol = symbols[i % symbols.count]
                    let glyph = Text(Image(systemName: symbol))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(CooksyTheme.primaryAccent)
                    context.opacity = opacity
                    context.draw(glyph, at: CGPoint(x: x, y: y))
                }
            }
        }
        .allowsHitTesting(false)
        .onChange(of: trigger) { _, _ in
            firedAt = Date()
        }
    }
}
