import SwiftUI
import AppKit

/// Shared visual language for the main GrokBuild surface.
///
/// The app stays cool-neutral across System, Light, and Dark appearances.
/// Dark mode uses a cool soft-black canvas; light mode uses stone gray with a
/// slight blue bias instead of cream. `canvasNSColor` is the same token the
/// AppKit window uses so the transparent titlebar matches the work surface.
enum AppTheme {
    enum Palette {
        static let canvasNSColor = adaptiveNSColor(
            dark: NSColor(red: 0.07, green: 0.07, blue: 0.075, alpha: 1),
            light: NSColor(red: 0.961, green: 0.961, blue: 0.969, alpha: 1)
        )
        static let canvas = Color(nsColor: canvasNSColor)
        static let sidebarNSColor = adaptiveNSColor(
            dark: NSColor(red: 0.045, green: 0.045, blue: 0.05, alpha: 1),
            light: NSColor(red: 0.925, green: 0.925, blue: 0.933, alpha: 1)
        )
        static let sidebar = Color(nsColor: sidebarNSColor)
        static let chrome = canvas
        static let surface = adaptive(
            dark: NSColor(red: 0.155, green: 0.155, blue: 0.165, alpha: 1),
            light: NSColor.white
        )
        static let surfaceHover = adaptive(
            dark: NSColor(red: 0.195, green: 0.195, blue: 0.205, alpha: 1),
            light: NSColor(red: 0.890, green: 0.890, blue: 0.898, alpha: 1)
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
        static let accentNSColor = adaptiveNSColor(
            dark: NSColor.white.withAlphaComponent(0.92),
            light: NSColor.black.withAlphaComponent(0.88)
        )
        static let accent = Color(nsColor: accentNSColor)
        /// Text and symbols placed on the neutral accent fill.
        static let accentForegroundNSColor = adaptiveNSColor(
            dark: NSColor.black.withAlphaComponent(0.90),
            light: NSColor.white
        )
        static let accentForeground = Color(nsColor: accentForegroundNSColor)
        /// Workbench icons. Dark stays a consistent near-white so every
        /// header control matches; Light stays ink on stone.
        static let titlebarControlNSColor = adaptiveNSColor(
            dark: .white,
            light: NSColor(white: 0.22, alpha: 1)
        )
        static let titlebarControl = Color(nsColor: titlebarControlNSColor)
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
        /// Muted amber for stall / attention. Not the system orange accent.
        static let warningNSColor = adaptiveNSColor(
            dark: NSColor(red: 0.86, green: 0.68, blue: 0.36, alpha: 1),
            light: NSColor(red: 0.58, green: 0.40, blue: 0.12, alpha: 1)
        )
        static let warning = Color(nsColor: warningNSColor)
        /// Cool slate for links and interactive emphasis that is not chrome accent.
        static let linkNSColor = adaptiveNSColor(
            dark: NSColor(red: 0.62, green: 0.72, blue: 0.84, alpha: 1),
            light: NSColor(red: 0.28, green: 0.40, blue: 0.55, alpha: 1)
        )
        static let link = Color(nsColor: linkNSColor)

        private static func adaptiveNSColor(dark: NSColor, light: NSColor) -> NSColor {
            NSColor(name: nil) { appearance in
                let best = appearance.bestMatch(from: [.darkAqua, .aqua])
                return best == .darkAqua ? dark : light
            }
        }

        private static func adaptive(dark: NSColor, light: NSColor) -> Color {
            Color(nsColor: adaptiveNSColor(dark: dark, light: light))
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

/// Bakes an SF Symbol into a non-template bitmap. Titlebar vibrancy and
/// `NSMenu` / `NSButton` template tinting both paint SwiftUI
/// `Image(systemName:)` at canvas black on Dark; this keeps the pixels.
enum TitlebarGlyphRaster {
    static func image(
        systemName: String,
        pointSize: CGFloat,
        color: NSColor,
        appearance: NSAppearance
    ) -> NSImage {
        var resolved = NSColor.white
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }

        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        guard let symbol = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else {
            return NSImage(size: NSSize(width: pointSize, height: pointSize))
        }
        symbol.isTemplate = true
        let size = symbol.size.width > 0
            ? symbol.size
            : NSSize(width: pointSize, height: pointSize)
        let raster = NSImage(size: size, flipped: false) { rect in
            appearance.performAsCurrentDrawingAppearance {
                NSColor.white.set()
                symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
                resolved.setFill()
                rect.fill(using: .sourceIn)
            }
            return true
        }
        raster.isTemplate = false
        guard let tiff = raster.tiffRepresentation, let bitmap = NSImage(data: tiff) else {
            return raster
        }
        bitmap.isTemplate = false
        return bitmap
    }
}

/// SF Symbol that stays readable in the transparent titlebar.
struct TitlebarGlyph: View {
    let systemName: String
    var pointSize: CGFloat = 13
    var color: NSColor = AppTheme.Palette.titlebarControlNSColor
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TitlebarGlyphImage(
            systemName: systemName,
            pointSize: pointSize,
            color: color,
            colorScheme: colorScheme
        )
        .frame(width: pointSize + 6, height: pointSize + 6)
        .accessibilityHidden(true)
    }
}

private struct TitlebarGlyphImage: NSViewRepresentable {
    let systemName: String
    let pointSize: CGFloat
    let color: NSColor
    let colorScheme: ColorScheme

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageScaling = .scaleNone
        view.imageAlignment = .alignCenter
        view.isEditable = false
        view.animates = false
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    func updateNSView(_ view: NSImageView, context: Context) {
        let appearance = colorScheme == .dark
            ? NSAppearance(named: .darkAqua)!
            : NSAppearance(named: .aqua)!
        view.appearance = appearance
        view.contentTintColor = nil
        let image = TitlebarGlyphRaster.image(
            systemName: systemName,
            pointSize: pointSize,
            color: color,
            appearance: appearance
        )
        image.isTemplate = false
        view.image = image
    }
}

/// Consistent desktop chrome control: forgiving hit area, hover/press feedback, keyboard focus,
/// and restrained disabled treatment without changing the soft-black visual language.
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

/// App-owned primary action treatment. Native `borderedProminent` inherits the
/// user's macOS accent color, which can turn the cool-neutral workbench orange
/// or brown; this style keeps the same semantic emphasis in Light and Dark.
struct GrokProminentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GrokProminentButtonBody(configuration: configuration)
    }

    private struct GrokProminentButtonBody: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.controlSize) private var controlSize
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(AppTheme.Palette.accentForeground)
                .padding(.horizontal, horizontalPadding)
                .frame(minHeight: minimumHeight)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.medium, style: .continuous)
                        .fill(backgroundColor)
                )
                .opacity(isEnabled ? 1 : 0.42)
                .onHover { isHovering = $0 }
        }

        private var backgroundColor: Color {
            if configuration.isPressed { return AppTheme.Palette.accent.opacity(0.72) }
            if isHovering && isEnabled { return AppTheme.Palette.accent.opacity(0.84) }
            return AppTheme.Palette.accent
        }

        private var horizontalPadding: CGFloat {
            switch controlSize {
            case .mini: return 6
            case .small: return 8
            case .large: return 14
            default: return 10
            }
        }

        private var minimumHeight: CGFloat {
            switch controlSize {
            case .mini: return 20
            case .small: return 24
            case .large: return 36
            default: return 30
            }
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
