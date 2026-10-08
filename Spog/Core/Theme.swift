import SwiftUI

/// Palette et typographie. Aucune couleur ne doit etre ecrite ailleurs que dans ce fichier.
enum Theme {

    // MARK: Fonds
    // Sobriété (09/10/2026) : le testeur trouvait que « ça part dans tous les sens ». Les
    // fonds tiraient vers le violet et chaque panneau portait sa lueur. Désormais un noir
    // neutre et des gris anthracite : la couleur ne sert plus qu'à signaler quelque chose.
    static let background    = Color(hex: 0x0A0A0C)
    static let surface       = Color(hex: 0x141417)
    static let surfaceRaised = Color(hex: 0x1C1C20)

    // MARK: Contours
    static let stroke       = Color.white.opacity(0.08)
    static let strokeStrong = Color.white.opacity(0.14)

    // MARK: Texte
    static let textPrimary   = Color(hex: 0xF2F2F4)
    static let textSecondary = Color(hex: 0x9C9CA6)
    static let textMuted     = Color(hex: 0x5F5F69)

    // MARK: Accent
    // **Une seule couleur d'accent**, et rare : le bouton principal, l'onglet actif, la
    // jauge de niveau. Si tout est violet, plus rien ne l'est.
    static let accent       = Color(hex: 0xA75CF9)
    static let accentBright = Color(hex: 0xC98BFF)
    static let accentDeep   = Color(hex: 0x5B21B6)

    // MARK: Signaux
    /// Second ton, neutre : l'adversaire d'un duel, la zone de montée, le crew. C'était un
    /// cyan, qui faisait une deuxième couleur d'accent à côté du violet ; un gris clair
    /// distingue tout aussi bien sans ajouter de teinte.
    static let neutralAccent = Color(hex: 0xC9CCD3)
    /// Ambre des alertes (scans épuisés, zone de descente). Une alerte, pas une décoration.
    static let warning = Color(hex: 0xF5B942)
    /// Lumière blanche des reflets : jamais un aplat, toujours à faible opacité.
    static let highlight = Color.white

    // MARK: Matières
    // Les « matières premium » de la version précédente (dégradés, arêtes violettes,
    // reflets) sont ramenées à presque rien : elles gardent leur nom pour ne pas toucher
    // chaque écran, mais rendent maintenant des aplats discrets.

    /// Remplissage de l'action principale : un violet presque uni, à peine éclairé en haut.
    static let accentGradient = LinearGradient(
        colors: [Color(hex: 0xB070FA), Color(hex: 0xA75CF9)],
        startPoint: .top, endPoint: .bottom
    )
    /// Fond des panneaux : un anthracite uni, sans dégradé visible.
    static let glassFill = LinearGradient(
        colors: [Color(hex: 0x161619), Color(hex: 0x131316)],
        startPoint: .top, endPoint: .bottom
    )
    /// Bord des panneaux : un filet blanc fin, neutre. Plus de violet dans l'arête.
    static let glassEdge = LinearGradient(
        colors: [Color.white.opacity(0.11), Color.white.opacity(0.07)],
        startPoint: .top, endPoint: .bottom
    )
    /// Reflet du haut d'une surface : à peine perceptible.
    static let sheen = LinearGradient(
        colors: [Color.white.opacity(0.03), .clear],
        startPoint: .top, endPoint: .center
    )
    /// Ombre portée des panneaux : courte et sombre, elle détache sans faire flotter.
    static let dropShadow = Color.black.opacity(0.35)

    /// Lueur derrière un élément mis en avant (logo, paywall). Très faible : un relief,
    /// pas un halo.
    static let glow = RadialGradient(
        colors: [Color(hex: 0xA75CF9).opacity(0.08), .clear],
        center: .center, startRadius: 2, endRadius: 260
    )

    // MARK: Studio des modèles
    // Le décor unique sur lequel chaque modèle sans photo est posé (`StudioStage`). Les
    // rendus IA avaient chacun le leur, néons violets ou bleus à des hauteurs différentes :
    // trois cibles côte à côte semblaient venir de trois jeux. Un anthracite profond, une
    // lumière blanche froide venue d'en haut, un sol plus sombre : rien qui concurrence la
    // voiture, et rien de violet — l'accent reste rare.

    /// Haut du fond, là où tombe le projecteur.
    static let studioTop     = Color(hex: 0x23242A)
    /// Bas du mur, juste avant le sol : le point le plus sombre du fond.
    static let studioWall    = Color(hex: 0x111215)
    /// Sol au pied de la voiture, à peine éclairé par le projecteur.
    static let studioGround  = Color(hex: 0x23242A)
    /// Sol au premier plan, qui se perd dans le noir.
    static let studioFloor   = Color(hex: 0x0B0B0E)
    /// Lumière du projecteur : un blanc froid, toujours à très faible opacité.
    static let studioLight   = Color(hex: 0xE4ECFF)

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
