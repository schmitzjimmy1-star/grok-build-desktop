import SwiftUI

/// Shared visual language for the main GrokBuild surface.
///
/// The app intentionally stays dark-mode-first and neutral: graphite canvas,
/// matte raised surfaces, faint borders, and a monochrome status system.
enum AppTheme {
    enum Palette {
        static let canvas = Color(red: 0.086, green: 0.086, blue: 0.086)
        static let sidebar = Color(red: 0.078, green: 0.078, blue: 0.078)
        static let chrome = canvas
        static let surface = Color(red: 0.125, green: 0.125, blue: 0.125)
        static let surfaceHover = Color(red: 0.15, green: 0.15, blue: 0.15)
        static let glassTint = Color.white.opacity(0.035)
        static let glassBorder = Color.white.opacity(0.085)
        static let glassBorderStrong = Color.white.opacity(0.15)
        static let accent = Color.white.opacity(0.92)
        static let accentSoft = Color.white.opacity(0.075)
        static let status = Color.white.opacity(0.58)
        static let textMuted = Color.white.opacity(0.62)
        static let shadow = Color.black.opacity(0.18)
    }

    enum Radius {
        static let small: CGFloat = 4
        static let medium: CGFloat = 6
        static let large: CGFloat = 8
    }

    enum Layout {
        static let conversationMaxWidth: CGFloat = 760
        static let composerMaxWidth: CGFloat = 820
        static let settingsSidebarWidth: CGFloat = 168
        static let settingsContentMaxWidth: CGFloat = 760
        static let settingsControlWidth: CGFloat = 180
        static let settingsRuleEditorHeight: CGFloat = 96
    }

    enum Typography {
        static let body = Font.system(size: 14, weight: .regular, design: .default)
        static let composer = Font.system(size: 14, weight: .regular, design: .default)
        static let heading = Font.system(size: 17, weight: .semibold, design: .default)
        static let section = Font.system(size: 11, weight: .semibold, design: .default)
    }
}

private struct GrokGlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let emphasized: Bool
    let shadowed: Bool

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppTheme.Palette.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        emphasized
                            ? AppTheme.Palette.glassBorderStrong
                            : AppTheme.Palette.glassBorder,
                        lineWidth: 1
                    )
            }
            .shadow(
                color: shadowed ? AppTheme.Palette.shadow.opacity(0.38) : .clear,
                radius: shadowed ? 6 : 0,
                y: shadowed ? 2 : 0
            )
    }
}

extension View {
    func grokGlassSurface(
        cornerRadius: CGFloat = AppTheme.Radius.medium,
        emphasized: Bool = false,
        shadowed: Bool = false
    ) -> some View {
        modifier(
            GrokGlassSurfaceModifier(
                cornerRadius: cornerRadius,
                emphasized: emphasized,
                shadowed: shadowed
            )
        )
    }
}
