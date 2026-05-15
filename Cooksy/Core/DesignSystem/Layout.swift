import SwiftUI

/// Responsive layout tokens shared across the redesigned premium
/// surfaces (Welcome, Paywall, Gift Offer).
///
/// Why this exists: most of the original onboarding screens used a
/// hard-coded `padding(.horizontal, 22)`. That value is fine on the
/// iPhone 15 family (393–430pt wide) but pinches the iPhone SE (375pt)
/// and looks anemic on iPad split screen / Stage Manager. Pass through
/// `Layout.horizontalPadding(for:)` instead and the screen scales.
enum Layout {
    /// Horizontal padding adapted to the available width.
    ///
    /// - 16pt for compact widths (<360pt) — keeps content from
    ///   touching the bezel on SE-class devices.
    /// - 20pt for the iPhone 12/13/14/15 family (360–400pt) — matches
    ///   Apple's HIG default content margin.
    /// - 24pt for Pro Max and iPad-class widths (≥400pt) — gives the
    ///   editorial layout some breathing room.
    static func horizontalPadding(for proxy: GeometryProxy) -> CGFloat {
        horizontalPadding(for: proxy.size.width)
    }

    /// Width-based variant. Useful when you've already pulled the
    /// width out of a parent `GeometryReader` or `UIScreen`.
    static func horizontalPadding(for width: CGFloat) -> CGFloat {
        switch width {
        case ..<360: return 16
        case ..<400: return 20
        default:     return 24
        }
    }

    /// Maximum content width on very large devices. Premium surfaces
    /// look cheap when a paragraph stretches to 1000pt of unused
    /// canvas — clip at ~520pt and let the breathing layout fill the
    /// rest with `Spacer()`.
    static let maxContentWidth: CGFloat = 520
}

// MARK: - Convenience view modifier

extension View {
    /// Applies responsive horizontal padding (see {@link Layout}).
    /// Prefer this to a raw `padding(.horizontal, X)` on the new
    /// premium screens.
    func cooksyHorizontalPadding(for proxy: GeometryProxy) -> some View {
        padding(.horizontal, Layout.horizontalPadding(for: proxy))
    }

    /// Width-based variant for contexts where the proxy isn't handy.
    func cooksyHorizontalPadding(for width: CGFloat) -> some View {
        padding(.horizontal, Layout.horizontalPadding(for: width))
    }
}
