import SwiftUI
import AppKit

/// Shared visual language for the main GrokBuild surface.
///
/// The app stays neutral and warm across System, Light, and Dark appearances.
/// NSColor dynamic providers keep the existing dark graphite treatment while
/// giving light mode real boundaries instead of a dark palette pasted on white.
enum AppTheme {
    enum Palette {
        static let canvas = adaptive(
            dark: NSColor(red: 0.129, green: 0.129, blue: 0.129, alpha: 1),
            light: NSColor(red: 0.985, green: 0.985, blue: 0.98, alpha: 1)
        )
        static let sidebar = adaptive(
            dark: NSColor(red: 0.105, green: 0.105, blue: 0.105, alpha: 1),
            light: NSColor(red: 0.95, green: 0.95, blue: 0.945, alpha: 1)
        )
        static let chrome = canvas
        static let surface = adaptive(
            dark: NSColor(red: 0.165, green: 0.165, blue: 0.165, alpha: 1),
            light: NSColor.white
        )
        static let surfaceHover = adaptive(
            dark: NSColor(red: 0.205, green: 0.205, blue: 0.205, alpha: 1),
            light: NSColor(red: 0.92, green: 0.92, blue: 0.91, alpha: 1)
        )
        static let glassTint = adaptive(
            dark: NSColor.white.withAlphaComponent(0.035),
            light: NSColor.black.withAlphaComponent(0.025)
        )
        static let glassBorder = adaptive(
            dark: NSColor.white.withAlphaComponent(0.085),
            light: NSColor.black.withAlphaComponent(0.13)
        )
        static let glassBorderStrong = adaptive(
            dark: NSColor.white.withAlphaComponent(0.15),
            light: NSColor.black.withAlphaComponent(0.24)
        )
        static let accent = adaptive(
            dark: NSColor.white.withAlphaComponent(0.92),
            light: NSColor.black.withAlphaComponent(0.88)
        )
        static let accentSoft = adaptive(
            dark: NSColor.white.withAlphaComponent(0.075),
            light: NSColor.black.withAlphaComponent(0.06)
        )
        static let textMuted = adaptive(
            dark: NSColor.white.withAlphaComponent(0.62),
            light: NSColor.black.withAlphaComponent(0.62)
        )
        /// One step below `textMuted` for supporting metadata.
        static let textFaint = adaptive(
            dark: NSColor.white.withAlphaComponent(0.42),
            light: NSColor.black.withAlphaComponent(0.48)
        )
        static let shadow = Color.black.opacity(0.18)
        static let richContentBackground = adaptive(
            dark: NSColor.black.withAlphaComponent(0.26),
            light: NSColor.black.withAlphaComponent(0.055)
        )
        static let richTableBackground = adaptive(
            dark: NSColor.black.withAlphaComponent(0.16),
            light: NSColor.black.withAlphaComponent(0.035)
        )

        private static func adaptive(dark: NSColor, light: NSColor) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                let best = appearance.bestMatch(from: [.darkAqua, .aqua])
                return best == .darkAqua ? dark : light
            })
        }
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
        /// Codex-style bottom composer and floating inspector cards.
        static let composer: CGFloat = 14
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
        /// Transcript reading size. Deliberately one point above the 14 pt control
        /// scale: answers are the product, chrome is not.
        static let body = Font.system(size: 15, weight: .regular, design: .default)
        /// Thinking/tool trace text — readable, but visually subordinate to answers.
        static let thinking = Font.system(size: 13, weight: .regular, design: .default)
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
            case 1: return .system(size: 20, weight: .semibold)
            case 2: return .system(size: 17, weight: .semibold)
            default: return .system(size: 15, weight: .semibold)
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
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        reduceTransparency
                            ? AppTheme.Palette.surface
                            : AppTheme.Palette.surface.opacity(0.98)
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        emphasized
                            ? AppTheme.Palette.glassBorderStrong
                            : (differentiateWithoutColor || colorSchemeContrast == .increased
                                ? AppTheme.Palette.glassBorderStrong
                                : AppTheme.Palette.glassBorder),
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
