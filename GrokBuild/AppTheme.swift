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
        static let textMuted = Color.white.opacity(0.62)
        /// One step below `textMuted` for supporting metadata.
        static let textFaint = Color.white.opacity(0.42)
        static let shadow = Color.black.opacity(0.18)
    }

    /// The app ships three card radii plus one for floating overlays.
    /// Anything outside this set is drift — use the nearest token.
    enum Radius {
        /// Chips, badges, inline markers.
        static let small: CGFloat = 4
        /// Controls and compact rows.
        static let medium: CGFloat = 6
        /// Cards, banners, panels — the default card treatment.
        static let large: CGFloat = 8
        /// Floating modal cards that sit above the canvas.
        static let overlay: CGFloat = 18
    }

    enum Layout {
        static let conversationMaxWidth: CGFloat = 760
        static let composerMaxWidth: CGFloat = 820
        static let settingsSidebarWidth: CGFloat = 168
        static let settingsContentMaxWidth: CGFloat = 760
        static let settingsControlWidth: CGFloat = 180
        static let settingsRuleEditorHeight: CGFloat = 96
    }

    /// Text roles. `Font.system(size:)` applied to `Image(systemName:)` is
    /// glyph sizing inside a fixed frame, not a member of this ladder —
    /// those stay local to their view on purpose.
    enum Typography {
        static let body = Font.system(size: 14, weight: .regular, design: .default)
        static let composer = Font.system(size: 14, weight: .regular, design: .default)
        static let heading = Font.system(size: 17, weight: .semibold, design: .default)
        static let section = Font.system(size: 11, weight: .semibold, design: .default)
        /// Pill and tab labels.
        static let label = Font.system(size: 11, weight: .medium, design: .default)
        static let caption = Font.system(size: 12, weight: .regular, design: .default)
        static let captionStrong = Font.system(size: 12, weight: .semibold, design: .default)
        /// Count badges rendered inside small circles.
        static let badge = Font.system(size: 9, weight: .semibold, design: .default)
        /// Inline code and command output.
        static let code = Font.system(size: 13, weight: .regular, design: .monospaced)

        /// Markdown heading ladder (H1 → H3+), deliberately tighter than the
        /// system scale so transcript headings do not shout.
        static func markdownHeading(level: Int) -> Font {
            switch level {
            case 1: return .system(size: 19, weight: .semibold)
            case 2: return .system(size: 16, weight: .semibold)
            default: return .system(size: 14, weight: .semibold)
            }
        }
    }
}

/// Consistent desktop chrome control: forgiving hit area, hover/press feedback, keyboard focus,
/// and restrained disabled treatment without changing the graphite visual language.
struct GrokChromeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GrokChromeButtonBody(configuration: configuration)
    }

    private struct GrokChromeButtonBody: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .frame(minWidth: 32, minHeight: 32)
                .padding(.horizontal, 2)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                        .fill(backgroundColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                        .stroke(isHovering && isEnabled ? AppTheme.Palette.glassBorder : .clear)
                )
                .opacity(isEnabled ? 1 : 0.42)
                .onHover { isHovering = $0 }
        }

        private var backgroundColor: Color {
            if configuration.isPressed { return AppTheme.Palette.accentSoft.opacity(1.5) }
            if isHovering && isEnabled { return AppTheme.Palette.surfaceHover }
            return .clear
        }
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
