import SwiftUI

/// Responsive layout tokens used across Cooksy surfaces.
///
/// The app targets a wide device range: iPhone SE / iPhone 8 (375×667pt,
/// no top safe area) up to iPhone Pro Max (430pt wide) and iPad
/// (1024pt+ wide). Hard-coded paddings and heights either pinch SE-class
/// devices or look anemic on iPad — `Layout` centralizes the scaling
/// rules so screens can stay declarative.
enum Layout {

    // MARK: - Device width buckets

    /// Width-based device classification. Keeps "size class" logic in one
    /// place so individual views don't reimplement breakpoints.
    enum DeviceClass {
        /// iPhone SE, iPhone 8, iPhone Mini — width < 360.
        case compact
        /// iPhone 12–15 standard family — 360 ≤ width < 400.
        case regular
        /// iPhone Plus / Pro Max — 400 ≤ width < 500.
        case large
        /// iPad portrait, Stage Manager split — 500 ≤ width < 700.
        case tabletCompact
        /// iPad full-width / landscape — width ≥ 700.
        case tablet

        static func from(width: CGFloat) -> DeviceClass {
            switch width {
            case ..<360:  return .compact
            case ..<400:  return .regular
            case ..<500:  return .large
            case ..<700:  return .tabletCompact
            default:      return .tablet
            }
        }

        var isPhone: Bool {
            switch self {
            case .compact, .regular, .large: return true
            default: return false
            }
        }

        var isTablet: Bool {
            switch self {
            case .tabletCompact, .tablet: return true
            default: return false
            }
        }
    }

    // MARK: - Horizontal padding

    /// Horizontal padding adapted to the available width.
    ///
    /// - 14pt for compact widths (<360pt) — keeps content from
    ///   touching the bezel on SE-class devices.
    /// - 20pt for the iPhone 12/13/14/15 family (360–400pt) — matches
    ///   Apple's HIG default content margin.
    /// - 24pt for Pro Max-class widths (400–500pt).
    /// - 32pt for iPad portrait / Stage Manager (500–700pt).
    /// - 48pt for full-width iPad / landscape (≥700pt).
    static func horizontalPadding(for proxy: GeometryProxy) -> CGFloat {
        horizontalPadding(for: proxy.size.width)
    }

    static func horizontalPadding(for width: CGFloat) -> CGFloat {
        switch DeviceClass.from(width: width) {
        case .compact:        return 14
        case .regular:        return 20
        case .large:          return 24
        case .tabletCompact:  return 32
        case .tablet:         return 48
        }
    }

    // MARK: - Vertical scaling

    /// Top padding adapted to the device. iPhone 8 has no top safe area
    /// (status bar is only 20pt tall vs 47–59pt on notched devices), so
    /// premium screens that put content right against the top look
    /// cramped. This token gives a sensible breathing room.
    static func topPadding(for width: CGFloat) -> CGFloat {
        switch DeviceClass.from(width: width) {
        case .compact:        return 6
        case .regular:        return 10
        case .large:          return 12
        case .tabletCompact:  return 16
        case .tablet:         return 20
        }
    }

    /// Bottom padding for ScrollView content. Anything sitting under the
    /// custom floating button needs extra clearance on devices with no
    /// bottom safe area (iPhone 8 — 0pt) vs notched devices (34pt).
    static func bottomScrollPadding(for width: CGFloat) -> CGFloat {
        switch DeviceClass.from(width: width) {
        case .compact:        return 104
        case .regular:        return 120
        case .large:          return 128
        case .tabletCompact:  return 140
        case .tablet:         return 160
        }
    }

    // MARK: - Hero / illustration heights

    /// Hero image height scaled to the screen's vertical space.
    /// On iPhone 8 (667pt tall) 380pt eats 57 % of the screen — too
    /// much. We cap it as a fraction of the screen height instead.
    static func heroHeight(for size: CGSize) -> CGFloat {
        let h = size.height
        let w = size.width
        // Phones: keep hero ≤ 40 % of screen height, clamp 240–400.
        if DeviceClass.from(width: w).isPhone {
            return min(max(h * 0.40, 240), 400)
        }
        // Tablets: scale with width instead — a portrait iPad has plenty
        // of height but the hero would dominate at 40 %. Width-based.
        return min(max(w * 0.45, 360), 520)
    }

    /// Illustration height for onboarding / guide screens. Same idea as
    /// heroHeight but optimised for centered illustrations that need
    /// room for text below.
    static func illustrationHeight(for size: CGSize) -> CGFloat {
        let h = size.height
        let w = size.width
        if DeviceClass.from(width: w).isPhone {
            // iPhone SE/8: tall screens get more room; cap at 50 % of
            // screen height so text fits below.
            return min(max(h * 0.36, 200), 340)
        }
        return min(max(w * 0.4, 280), 460)
    }

    // MARK: - Content width

    /// Maximum content width on very large devices. Premium surfaces
    /// look cheap when a paragraph stretches across an iPad — clip at
    /// ~560pt and let the breathing layout fill the rest with `Spacer()`.
    static let maxContentWidth: CGFloat = 560

    /// Reading-optimal width for long text blocks (recipes, articles).
    static let maxReadingWidth: CGFloat = 680

    // MARK: - Floating button

    /// Diameter of the floating quick-import button, scaled per device.
    static func floatingButtonSize(for width: CGFloat) -> CGFloat {
        switch DeviceClass.from(width: width) {
        case .compact:        return 56
        case .regular:        return 60
        case .large:          return 64
        case .tabletCompact:  return 68
        case .tablet:         return 72
        }
    }

    // MARK: - Card sizing

    /// Width for horizontal-scroll cards (recent imports, trending).
    /// Caps to ~82 % of screen width on phones so the next card peeks,
    /// and locks to a fixed value on iPad where the carousel becomes a
    /// row of cards rather than a single dominant one.
    static func carouselCardWidth(for width: CGFloat, base: CGFloat = 208) -> CGFloat {
        let cls = DeviceClass.from(width: width)
        switch cls {
        case .compact:        return min(base, width - 64)
        case .regular:        return base
        case .large:          return base + 16
        case .tabletCompact:  return 240
        case .tablet:         return 260
        }
    }

    /// Trending card width (used to be `UIScreen.main.bounds.width - 80`).
    static func trendingCardWidth(for width: CGFloat) -> CGFloat {
        let cls = DeviceClass.from(width: width)
        switch cls {
        case .compact:        return max(width - 64, 240)
        case .regular:        return max(width - 80, 260)
        case .large:          return max(width - 96, 280)
        case .tabletCompact:  return 360
        case .tablet:         return 420
        }
    }
}

// MARK: - Convenience view modifiers

extension View {
    /// Responsive horizontal padding driven by a `GeometryProxy`.
    func cooksyHorizontalPadding(for proxy: GeometryProxy) -> some View {
        padding(.horizontal, Layout.horizontalPadding(for: proxy))
    }

    /// Width-based variant for contexts where the proxy isn't handy.
    func cooksyHorizontalPadding(for width: CGFloat) -> some View {
        padding(.horizontal, Layout.horizontalPadding(for: width))
    }

    /// Caps the content to `Layout.maxContentWidth` and centers it. Use
    /// on premium / onboarding / detail screens so iPad doesn't show a
    /// 1024pt-wide column of text.
    func cooksyContentFrame(maxWidth: CGFloat = Layout.maxContentWidth) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }

    /// Reading-optimal width variant — wider than `cooksyContentFrame`,
    /// for screens that display long recipe text.
    func cooksyReadingFrame() -> some View {
        frame(maxWidth: Layout.maxReadingWidth)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - Custom navigation top offset

extension Layout {
    /// Offset to use for custom navigation overlays (back button, share)
    /// drawn over a hero image, when SwiftUI's safe area inset isn't
    /// available (because the hero ignores safe area).
    ///
    /// iPhone SE/8 has a ~20pt status bar; notched devices have 47–59pt.
    /// We add ~8pt breathing room so the button doesn't kiss the bezel.
    @MainActor
    static func customNavTopInset() -> CGFloat {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first(where: { $0.isKeyWindow })
                            ?? scene.windows.first else {
            return 44
        }
        return max(window.safeAreaInsets.top, 20) + 8
    }

    /// Bottom-of-screen safe inset for floating CTAs / toasts.
    @MainActor
    static func bottomSafeInset() -> CGFloat {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first(where: { $0.isKeyWindow })
                            ?? scene.windows.first else {
            return 0
        }
        return window.safeAreaInsets.bottom
    }
}

// MARK: - Screen dimension helper

/// `UIScreen.main` is deprecated in multi-window / Stage Manager
/// contexts. Use this only as a fallback when no `GeometryReader` is
/// available. Returns the bounds of the key window's screen, or a
/// reasonable default.
@MainActor
enum ScreenMetrics {
    static var width: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .screen
            .bounds
            .width ?? 390
    }

    static var height: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .screen
            .bounds
            .height ?? 844
    }
}
