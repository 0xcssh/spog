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

    // MARK: Accents secondaires
    // Le cyan et l'or existaient déjà, mais écrits en dur dans les vues (crew, scans
    // épuisés) : ils deviennent des jetons, pour que l'écran reste une seule palette.
    static let cyan    = Color(hex: 0x22D3EE)
    static let warning = Color(hex: 0xF5B942)
    /// Lumière blanche des reflets : jamais un aplat, toujours à faible opacité.
    static let highlight = Color.white

    // MARK: Matières premium
    // Le testeur trouvait l'app « cheap » : des aplats gris sur du noir, sans relief.
    // Trois matières, utilisées avec parcimonie, donnent la profondeur qui manquait.

    /// Dégradé de l'action principale : un violet qui s'allume vers le haut.
    static let accentGradient = LinearGradient(
        colors: [Color(hex: 0xD3A1FF), Color(hex: 0xA75CF9), Color(hex: 0x7C3AED)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    /// Verre fumé des panneaux : un peu plus clair en haut, comme éclairé d'au-dessus.
    static let glassFill = LinearGradient(
        colors: [Color(hex: 0x1B1828), Color(hex: 0x0E0C16)],
        startPoint: .top, endPoint: .bottom
    )
    /// Arête du verre : le bord supérieur accroche la lumière, le bas prend l'accent.
    static let glassEdge = LinearGradient(
        colors: [Color.white.opacity(0.20), Color.white.opacity(0.05), Color(hex: 0xA75CF9).opacity(0.22)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    /// Reflet du haut d'une surface, posé par-dessus le contenu.
    static let sheen = LinearGradient(
        colors: [Color.white.opacity(0.09), .clear],
        startPoint: .top, endPoint: .center
    )
    /// Ombre portée des panneaux : ils flottent au-dessus du fond au lieu d'y être collés.
    static let dropShadow = Color.black.opacity(0.55)

    /// Lueurs d'ambiance du fond, l'une violette en haut, l'autre cyan en bas.
    static let ambientViolet = Color(hex: 0x7C3AED)
    static let ambientCyan   = Color(hex: 0x0E7490)

    /// Lueur violette diffuse posee derriere les elements mis en avant.
    static let glow = RadialGradient(
        colors: [Color(hex: 0xA75CF9).opacity(0.30), .clear],
        center: .center, startRadius: 2, endRadius: 260
    )

    /// Teinte du blason d'une ligue. Les identifiants viennent du serveur ; un palier
    /// inconnu (ajouté côté serveur avant l'app) prend l'accent plutôt que de disparaître.
    static func leagueColor(_ tier: String) -> Color {
        switch tier {
        case "bronze":   return Color(hex: 0xCD8A55)
        case "silver":   return Color(hex: 0xC7CCD6)
        case "gold":     return Color(hex: 0xF5B942)
        case "sapphire": return Color(hex: 0x4C7DF0)
        case "ruby":     return Color(hex: 0xF43F5E)
        case "diamond":  return Color(hex: 0x8FE3FF)
        default:         return accent
        }
    }

    // MARK: Typographie
    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static func mono(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
    /// Chiffre héros : le compteur du garage, le score d'un duel. Gras et serré, il doit
    /// se lire d'un coup d'œil, à bout de bras.
    static func hero(_ size: CGFloat) -> Font {
        .system(size: size, weight: .heavy, design: .rounded)
    }
    /// Texte courant. Le monospace partout donnait un air de terminal : on le garde pour
    /// les chiffres et les codes, le reste se lit dans la police du système.
    static func body(_ size: CGFloat = 13, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
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
