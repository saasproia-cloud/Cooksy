import SwiftUI

struct CooksyLogoMark: View {
    let size: CGFloat

    private var outlineWidth: CGFloat {
        max(1.6, size * 0.028)
    }

    var body: some View {
        ZStack {
            Ellipse()
                .fill(CooksyTheme.brandBlue.opacity(0.34))
                .frame(width: size * 1.78, height: size * 1.48)
                .blur(radius: size * 0.24)
                .offset(x: -size * 0.02, y: size * 0.1)

            Ellipse()
                .fill(CooksyTheme.brandBlue.opacity(0.18))
                .frame(width: size * 1.24, height: size * 1.08)
                .blur(radius: size * 0.13)
                .offset(x: -size * 0.06, y: size * 0.07)

            Circle()
                .fill(CooksyTheme.sparkleYellow.opacity(0.36))
                .frame(width: size * 0.86, height: size * 0.86)
                .blur(radius: size * 0.18)
                .offset(x: size * 0.48, y: -size * 0.16)

            ChefHatShape()
                .fill(CooksyTheme.brandBlueDark.opacity(0.14))
                .offset(x: size * 0.018, y: size * 0.055)

            ChefHatShape()
                .fill(.white)
                .overlay {
                    ChefHatShape()
                        .stroke(CooksyTheme.brandBlue, lineWidth: outlineWidth)
                }

            ChefHatFoldShape()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: 0xD7E4F7).opacity(0.94),
                            Color(hex: 0xEDF4FF).opacity(0.38)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .offset(x: -size * 0.008, y: size * 0.02)

            BrimArcShape()
                .stroke(CooksyTheme.brandBlue, style: StrokeStyle(lineWidth: outlineWidth * 1.05, lineCap: .round))
                .frame(width: size * 0.64, height: size * 0.18)
                .offset(y: size * 0.32)

            SparkleMark(size: size * 0.32)
                .offset(x: size * 0.48, y: -size * 0.34)

            SparkleMark(size: size * 0.2)
                .offset(x: size * 0.28, y: -size * 0.06)
        }
        .frame(width: size * 1.5, height: size * 1.18)
        .drawingGroup()
    }
}

private struct SparkleMark: View {
    let size: CGFloat

    var body: some View {
        SparkleShape()
            .fill(CooksyTheme.sparkleYellow)
            .overlay {
                SparkleShape()
                    .stroke(CooksyTheme.ctaOrange, lineWidth: max(1.2, size * 0.08))
            }
            .shadow(color: CooksyTheme.sparkleYellow.opacity(0.3), radius: size * 0.18)
            .frame(width: size, height: size)
    }
}

private struct ChefHatShape: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        var path = Path()
        path.move(to: point(0.27, 0.84))
        path.addCurve(to: point(0.28, 0.55), control1: point(0.27, 0.75), control2: point(0.28, 0.65))
        path.addCurve(to: point(0.13, 0.47), control1: point(0.18, 0.56), control2: point(0.11, 0.56))
        path.addCurve(to: point(0.25, 0.27), control1: point(0.04, 0.31), control2: point(0.12, 0.2))
        path.addCurve(to: point(0.41, 0.26), control1: point(0.31, 0.2), control2: point(0.37, 0.22))
        path.addCurve(to: point(0.47, 0.14), control1: point(0.39, 0.18), control2: point(0.41, 0.1))
        path.addCurve(to: point(0.78, 0.28), control1: point(0.58, 0.02), control2: point(0.78, 0.05))
        path.addCurve(to: point(0.71, 0.43), control1: point(0.82, 0.35), control2: point(0.8, 0.42))
        path.addCurve(to: point(0.88, 0.49), control1: point(0.8, 0.4), control2: point(0.89, 0.39))
        path.addCurve(to: point(0.78, 0.66), control1: point(0.95, 0.6), control2: point(0.89, 0.71))
        path.addCurve(to: point(0.69, 0.61), control1: point(0.74, 0.67), control2: point(0.71, 0.66))
        path.addCurve(to: point(0.64, 0.82), control1: point(0.69, 0.73), control2: point(0.68, 0.81))
        path.addCurve(to: point(0.28, 0.84), control1: point(0.55, 0.9), control2: point(0.38, 0.9))
        path.closeSubpath()
        return path
    }
}

private struct ChefHatFoldShape: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }

        var path = Path()
        path.move(to: point(0.28, 0.57))
        path.addCurve(to: point(0.23, 0.83), control1: point(0.25, 0.64), control2: point(0.22, 0.74))
        path.addCurve(to: point(0.42, 0.63), control1: point(0.31, 0.79), control2: point(0.4, 0.71))
        path.addCurve(to: point(0.35, 0.52), control1: point(0.43, 0.58), control2: point(0.41, 0.54))
        path.closeSubpath()
        return path
    }
}

private struct BrimArcShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.06, y: rect.midY))
        path.addCurve(
            to: CGPoint(x: rect.maxX - rect.width * 0.06, y: rect.midY),
            control1: CGPoint(x: rect.minX + rect.width * 0.28, y: rect.minY + rect.height * 0.08),
            control2: CGPoint(x: rect.minX + rect.width * 0.72, y: rect.minY + rect.height * 0.08)
        )
        return path
    }
}

private struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let top = CGPoint(x: center.x, y: rect.minY)
        let right = CGPoint(x: rect.maxX, y: center.y)
        let bottom = CGPoint(x: center.x, y: rect.maxY)
        let left = CGPoint(x: rect.minX, y: center.y)

        var path = Path()
        path.move(to: top)
        path.addCurve(
            to: right,
            control1: CGPoint(x: rect.maxX * 0.6, y: rect.minY + rect.height * 0.18),
            control2: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.minY + rect.height * 0.38)
        )
        path.addCurve(
            to: bottom,
            control1: CGPoint(x: rect.maxX - rect.width * 0.18, y: rect.maxY - rect.height * 0.38),
            control2: CGPoint(x: rect.maxX * 0.6, y: rect.maxY - rect.height * 0.18)
        )
        path.addCurve(
            to: left,
            control1: CGPoint(x: rect.width * 0.4, y: rect.maxY - rect.height * 0.18),
            control2: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.maxY - rect.height * 0.38)
        )
        path.addCurve(
            to: top,
            control1: CGPoint(x: rect.minX + rect.width * 0.18, y: rect.minY + rect.height * 0.38),
            control2: CGPoint(x: rect.width * 0.4, y: rect.minY + rect.height * 0.18)
        )
        path.closeSubpath()
        return path
    }
}

