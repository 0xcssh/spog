import SwiftUI

/// Palette et typographie. Aucune couleur ne doit etre ecrite ailleurs que dans ce fichier.
enum Theme {

    // MARK: Fonds
    static let background    = Color(hex: 0x07060B)
    static let surface       = Color(hex: 0x100E17)
    static let surfaceRaised = Color(hex: 0x171523)

    // MARK: Contours
    static let stroke       = Color.white.opacity(0.07)
    static let strokeStrong = Color.white.opacity(0.14)

    // MARK: Texte
    static let textPrimary   = Color(hex: 0xF3F1F8)
    static let textSecondary = Color(hex: 0x9A94AE)
    static let textMuted     = Color(hex: 0x5D5872)

    // MARK: Accent
    static let accent       = Color(hex: 0xA75CF9)
    static let accentBright = Color(hex: 0xC98BFF)
    static let accentDeep   = Color(hex: 0x5B21B6)

    /// Lueur violette diffuse posee derriere les elements mis en avant.
    static let glow = RadialGradient(
        colors: [Color(hex: 0xA75CF9).opacity(0.30), .clear],
        center: .center, startRadius: 2, endRadius: 260
    )

    // MARK: Typographie
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    /// Petite etiquette capitales espacees, signature visuelle de l'app.
    static func label(_ size: CGFloat = 10) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >>  8) & 0xFF) / 255,
                  blue:  Double( hex        & 0xFF) / 255,
                  opacity: 1)
    }
}

// MARK: - Composants partages

/// Etiquette capitales espacees.
struct Overline: View {
    let text: LocalizedStringKey
    var color: Color = Theme.textMuted
    var body: some View {
        Text(text)
            .font(Theme.label())
            .tracking(1.6)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }
}

/// Surface sombre a bord fin, brique de base de toutes les cartes de l'interface.
struct Panel<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
    }
}
