import SwiftUI

/// "Roue chance" — exit-intent reward presented when the user taps
/// the paywall close button for the first time. Six segments: most
/// are losing/light prizes, one (the −25 %) is the actual win. The
/// outcome is rigged: every spin lands on the −25 % slice. The
/// rotation is just smooth choreography to make the win feel earned.
///
/// Light cream background, large central wheel, single big "TOURNER"
/// CTA. After landing, the CTA flips to "Recevoir mon cadeau" which
/// hands off to `ExclusiveOfferView`.
struct GiftWheelView: View {
    let onClose: () -> Void
    /// Called when the user accepts the won discount. Receives the
    /// discount percentage so the host can stamp it on the offer.
    let onClaim: (Int) -> Void

    /// 6 wheel segments. The -25% is at index 0 (top) and is always
    /// the landing slice. The others are pure visual variety.
    private let segments: [GiftWheelSegment] = [
        GiftWheelSegment(label: "−25 %", subLabel: "JACKPOT", color: Color(hex: 0xF59E0B), isJackpot: true),
        GiftWheelSegment(label: "−5 %", subLabel: nil, color: Color(hex: 0xFEE2C8), isJackpot: false),
        GiftWheelSegment(label: "Rien", subLabel: nil, color: Color(hex: 0xE7E1D8), isJackpot: false),
        GiftWheelSegment(label: "−15 %", subLabel: nil, color: Color(hex: 0xFFD9A6), isJackpot: false),
        GiftWheelSegment(label: "Rien", subLabel: nil, color: Color(hex: 0xE7E1D8), isJackpot: false),
        GiftWheelSegment(label: "−10 %", subLabel: nil, color: Color(hex: 0xFCEAD0), isJackpot: false)
    ]

    @State private var rotation: Double = 0   // current visual rotation in degrees
    @State private var phase: Phase = .idle
    @State private var showsConfetti: Bool = false

    private let winningDiscount: Int = 25

    enum Phase {
        case idle           // wheel sits still, "TOURNER" button
        case spinning       // animating the rotation
        case won            // wheel stopped on -25 %, "Recevoir mon cadeau" button
    }

    var body: some View {
        ZStack {
            CooksyTheme.background
                .ignoresSafeArea()

            // Soft warm glow behind the wheel — makes the slice colours
            // pop without resorting to a black background.
            RadialGradient(
                colors: [
                    CooksyTheme.primaryAccentSoft,
                    CooksyTheme.background
                ],
                center: .center,
                startRadius: 40,
                endRadius: 380
            )
            .opacity(0.65)
            .ignoresSafeArea()

            VStack(spacing: 24) {
                topBar

                Spacer(minLength: 0)

                header

                wheel
                    .padding(.vertical, 12)

                Spacer(minLength: 0)

                cta
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 30)

            if showsConfetti {
                IngredientConfetti(trigger: showsConfetti ? 1 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Spacer()
            Button(action: {
                OnboardingHaptics.selection()
                onClose()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CooksyTheme.primaryText)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(CooksyTheme.elevatedSurface)
                            .overlay(Circle().stroke(CooksyTheme.stroke, lineWidth: 1))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 12)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            Text(headerEyebrow)
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(2.0)
                .foregroundStyle(CooksyTheme.ctaOrangeDark)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            // Apple Guideline 4: must wrap correctly on iPad — Apple
            // Review saw "Tente ta chance avan…" truncated to one line.
            // Allow up to 3 lines, shrink to 70%, fix vertical sizing
            // so the explicit `\n` always honours its line break.
            Text(headerTitle)
                .font(.system(size: 30, weight: .bold, design: .serif))
                .foregroundStyle(CooksyTheme.primaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(-2)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)

            // Same fix for the subtitle — Apple Review saw "Une seule
            // chance. La meilleure remise est à ga…" truncated.
            Text(headerSubtitle)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(CooksyTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18)
                .lineSpacing(1)
                .lineLimit(4)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
    }

    private var headerEyebrow: String {
        switch phase {
        case .idle, .spinning:  return "ROUE DE LA CHANCE"
        case .won:              return "TU AS GAGNÉ"
        }
    }

    private var headerTitle: String {
        switch phase {
        case .idle:     return "Tente ta chance avant\nde quitter"
        case .spinning: return "La roue tourne…"
        case .won:      return "−\(winningDiscount) % sur l'annuel"
        }
    }

    private var headerSubtitle: String {
        switch phase {
        case .idle:
            return "Une seule chance. La meilleure remise est à gagner."
        case .spinning:
            return "Croise les doigts !"
        case .won:
            return "Réduction valable 24 h sur ton 1ᵉʳ paiement annuel."
        }
    }

    // MARK: - Wheel

    private var wheel: some View {
        GeometryReader { geo in
            let outerSize = min(geo.size.width - 8, 312)
            let innerSize = outerSize * (280.0 / 312.0)
            let hubSize = outerSize * (76.0 / 312.0)
            let labelRadius = outerSize * (92.0 / 312.0)
            let pointerWidth = outerSize * (28.0 / 312.0)
            let pointerHeight = outerSize * (22.0 / 312.0)
            let pointerOffset = -outerSize / 2

            ZStack {
                // Outer ring — gives the wheel a polished frame.
                Circle()
                    .fill(CooksyTheme.elevatedSurface)
                    .shadow(color: .black.opacity(0.08), radius: 24, y: 12)
                    .frame(width: outerSize, height: outerSize)
                    .overlay(
                        Circle()
                            .stroke(CooksyTheme.stroke, lineWidth: 6)
                    )

                // Six pie slices.
                ZStack {
                    ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                        GiftWheelSliceShape(
                            startAngle: angle(for: index),
                            endAngle: angle(for: index + 1)
                        )
                        .fill(segment.color)
                        .overlay(
                            GiftWheelSliceShape(
                                startAngle: angle(for: index),
                                endAngle: angle(for: index + 1)
                            )
                            .stroke(.white.opacity(0.95), lineWidth: 2)
                        )

                        sliceLabel(segment, at: index, radius: labelRadius)
                    }
                }
                .frame(width: innerSize, height: innerSize)
                .clipShape(Circle())
                .rotationEffect(.degrees(rotation))

                // Center hub — anchors the wheel and hosts the spin button
                // when idle.
                Circle()
                    .fill(CooksyTheme.background)
                    .frame(width: hubSize, height: hubSize)
                    .overlay(
                        Circle()
                            .stroke(CooksyTheme.stroke, lineWidth: 2)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
                    .overlay(
                        Image(systemName: phase == .won ? "sparkles" : "gift.fill")
                            .font(.system(size: hubSize * 0.32, weight: .bold))
                            .foregroundStyle(CooksyTheme.ctaOrangeDark)
                    )

                // Pointer at the top of the wheel — fixed (not rotating).
                // Slice 0 (the −25 %) sits centred at the top, so the
                // pointer always lands on it once the rotation settles.
                Triangle()
                    .fill(CooksyTheme.ctaOrangeDark)
                    .frame(width: pointerWidth, height: pointerHeight)
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                    .offset(y: pointerOffset + pointerHeight / 2)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: 312)
    }

    private func angle(for index: Int) -> Angle {
        // Slice 0 should be centred at the top (12 o'clock). With 6
        // slices, each is 60°. Slice 0 spans -30° to +30° from the
        // top. We start drawing from -90° (which is 12 o'clock in
        // SwiftUI's coordinate system, where 0° is 3 o'clock).
        let perSlice = 360.0 / Double(segments.count)
        let degrees = -90.0 - perSlice / 2 + perSlice * Double(index)
        return .degrees(degrees)
    }

    private func sliceLabel(_ segment: GiftWheelSegment, at index: Int, radius: CGFloat) -> some View {
        let perSlice = 360.0 / Double(segments.count)
        let centreDegrees = -90.0 + perSlice * Double(index)

        return VStack(spacing: 2) {
            if let sub = segment.subLabel {
                Text(sub)
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(.white.opacity(0.85))
            }
            Text(segment.label)
                .font(.system(size: segment.isJackpot ? 16 : 14,
                              weight: .bold,
                              design: .rounded))
                .foregroundStyle(segment.isJackpot ? .white : CooksyTheme.heroDark)
        }
        .rotationEffect(.degrees(centreDegrees + 90)) // align to slice
        .offset(
            x: cos(CGFloat(centreDegrees) * .pi / 180) * radius,
            y: sin(CGFloat(centreDegrees) * .pi / 180) * radius
        )
    }

    // MARK: - CTA

    private var cta: some View {
        VStack(spacing: 10) {
            Button(action: handlePrimaryAction) {
                Text(ctaLabel)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        Capsule(style: .continuous)
                            .fill(CooksyTheme.accentGradient)
                    )
                    .shadow(color: CooksyTheme.primaryAccent.opacity(0.4), radius: 18, y: 10)
            }
            .buttonStyle(CooksyTheme.pressScale())
            .disabled(phase == .spinning)

            if phase == .won {
                Text("Cadeau valable 24 h. Cumulable avec l'essai 7 jours.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(CooksyTheme.secondaryText)
            } else if phase == .idle {
                Button(action: {
                    OnboardingHaptics.selection()
                    onClose()
                }) {
                    Text("Plus tard")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(CooksyTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var ctaLabel: String {
        switch phase {
        case .idle:     return "Tourner la roue"
        case .spinning: return "La roue tourne…"
        case .won:      return "Recevoir mon cadeau"
        }
    }

    private func handlePrimaryAction() {
        switch phase {
        case .idle:    spinWheel()
        case .spinning: break
        case .won:
            OnboardingHaptics.medium()
            onClaim(winningDiscount)
        }
    }

    // MARK: - Spinning logic

    /// Animates the wheel from its current rotation to a final
    /// rotation that lands slice 0 (-25 %) under the pointer. We add
    /// 6 full revolutions on top so the spin feels deliberate but
    /// not exhausting (≈ 4.5 s with the easing curve below).
    private func spinWheel() {
        OnboardingHaptics.selection()
        phase = .spinning

        // Slice 0 is already centred at the top, so a final rotation
        // multiple of 360° puts it back under the pointer. We add a
        // tiny random jitter (±4°) so subsequent spins look slightly
        // different even though the outcome is identical.
        let jitter = Double.random(in: -4...4)
        let target = rotation + 360 * 6 + jitter

        withAnimation(.timingCurve(0.18, 0.85, 0.32, 1.0, duration: 4.4)) {
            rotation = target
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 4.4) {
            OnboardingHaptics.success()
            phase = .won
            showsConfetti = true
        }
    }
}

// MARK: - Slice geometry

private struct GiftWheelSegment {
    let label: String
    let subLabel: String?
    let color: Color
    let isJackpot: Bool
}

private struct GiftWheelSliceShape: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.move(to: centre)
        path.addArc(
            center: centre,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
