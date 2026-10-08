import SwiftUI

// MARK: - Rarete

struct RarityTier: Decodable, Identifiable, Hashable {
    let id: String
    let rank: Int
    let points: Int
    let key: String

    /// Libelle affiche, traduit. Ne jamais montrer `id` a l'utilisateur.
    var label: LocalizedStringKey { LocalizedStringKey(key) }

    /// Or des cartes remarquables. Une seule et meme teinte pour les trois paliers hauts :
    /// c'est ce qui rend la distinction lisible d'un coup d'oeil.
    static let trophyGold = Color(hex: 0xF5B942)

    /// A partir de "rare", la carte devient un trophee : cadre dore et halo.
    /// En dessous, aucun cadre — une voiture ordinaire ne doit pas briller.
    var isTrophy: Bool { rank >= 3 }

    /// Couleur du cadre de la carte. Nil quand la carte n'en porte pas.
    var frameColor: Color? { isTrophy ? Self.trophyGold : nil }

    /// Intensite du halo, croissante sur les trois paliers hauts.
    var frameIntensity: Double { isTrophy ? 0.55 + 0.22 * Double(rank - 3) : 0 }

    /// Couleur du palier. Sert au texte, aux statistiques et a l'eclairage de la scene 3D.
    /// Elle reste distincte par palier : c'est elle qui donne le violet de la Taycan.
    var color: Color {
        switch id {
        case "common":    return Color(hex: 0x7C7C86)
        case "regular":   return Color(hex: 0x4C7DF0)
        case "notable":   return Color(hex: 0x22D3EE)
        case "rare":      return Theme.accent
        case "exotic":    return Color(hex: 0xF43F9D)
        case "legendary": return Color(hex: 0xF5B942)
        default:          return Theme.textMuted
        }
    }
}

// MARK: - Vehicules

/// `Encodable` autant que `Decodable` : les vehicules appris de l'IA sont reecrits
/// sur le disque, dans exactement le meme format que le catalogue embarque.
struct Vehicle: Codable, Identifiable, Hashable {
    let id: String
    let make: String
    let model: String
    /// Type de carrosserie : choisit la silhouette de repli. Voir CarBody.
    let body: String
    /// Rarete par marche. Cle = code pays, code region, ou "default".
    let rarity: [String: String]
    let aliases: [String]

    var fullName: String { "\(make) \(model)" }
}

// MARK: - Resultat d'une resolution de rarete

struct RarityResolution {
    let tier: RarityTier
    /// D'ou vient la valeur retenue : pays exact, region, ou repli mondial.
    let source: Source
    enum Source { case country(String), region(String), fallback }
}
