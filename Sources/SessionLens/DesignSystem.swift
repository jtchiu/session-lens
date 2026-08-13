import AppKit
import SessionLensCore
import SwiftUI

enum SessionLensSpacing {
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xLarge: CGFloat = 24
}

enum SessionLensRadius {
    static let compact: CGFloat = 6
    static let segment: CGFloat = 8
    static let surface: CGFloat = 12
}

enum SessionLensPalette {
    static let separator = Color(nsColor: .separatorColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let tertiaryText = Color(nsColor: .tertiaryLabelColor)
    static let window = Color(nsColor: .windowBackgroundColor)

    static func accent(
        for provider: ProviderID,
        scheme: ColorScheme
    ) -> Color {
        switch (provider, scheme) {
        case (.opencode, .light):
            Color(red: 0.435, green: 0.231, blue: 0.867)
        case (.opencode, .dark):
            Color(red: 0.608, green: 0.447, blue: 0.949)
        case (.claude, .light):
            Color(red: 0.941, green: 0.435, blue: 0.271)
        case (.claude, .dark):
            Color(red: 1, green: 0.541, blue: 0.396)
        case (.codex, .light):
            Color(red: 0.078, green: 0.431, blue: 0.961)
        case (.codex, .dark):
            Color(red: 0.298, green: 0.553, blue: 1)
        @unknown default:
            .accentColor
        }
    }

    static func quotaColor(_ percent: Double?) -> Color {
        guard let percent else { return secondaryText }
        if percent >= 90 { return .red }
        if percent >= 70 { return .orange }
        return .green
    }
}

struct SessionLensMark: View {
    let size: CGFloat
    var colorful = true

    var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { index in
                ApertureBlade(index: index)
                    .fill(index == 0 && colorful ? Color.blue : Color.primary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private struct ApertureBlade: Shape {
    let index: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.35
        let base = Double(index) * (.pi / 3) - .pi / 2

        var path = Path()
        path.move(to: point(center, radius: outer, angle: base + 0.03))
        path.addLine(to: point(center, radius: outer, angle: base + 0.92))
        path.addLine(to: point(center, radius: inner, angle: base + 1.27))
        path.addLine(to: point(center, radius: inner, angle: base + 0.41))
        path.closeSubpath()
        return path
    }

    private func point(
        _ center: CGPoint,
        radius: CGFloat,
        angle: Double
    ) -> CGPoint {
        CGPoint(
            x: center.x + radius * cos(angle),
            y: center.y + radius * sin(angle)
        )
    }
}

extension View {
    func sessionLensHairline() -> some View {
        overlay(alignment: .bottom) {
            Rectangle()
                .fill(SessionLensPalette.separator.opacity(0.7))
                .frame(height: 1 / (NSScreen.main?.backingScaleFactor ?? 2))
        }
    }
}
