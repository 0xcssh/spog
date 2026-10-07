import SwiftUI

/// Types de carrosserie. Correspond au champ `body` du catalogue, et à la liste fermée
/// que renvoie `identify` (épinglée par ServerContractTests).
enum CarBody: String {
    case hatch, sedan, suv, sport, pickup, van

    init(_ raw: String) { self = CarBody(rawValue: raw) ?? .sedan }

    /// Silhouette de profil, prise dans SF Symbols : disponible pour tout le catalogue,
    /// sans un octet d'image embarquée.
    var symbol: String {
        switch self {
        case .hatch, .sedan, .sport: return "car.side.fill"
        case .suv:                   return "suv.side.fill"
        case .pickup:                return "truck.pickup.side.fill"
        case .van:                   return "box.truck.fill"
        }
    }
}

/// Dernier repli du visuel d'une carte : ni photo du joueur, ni rendu studio.
///
/// Remplace le volume 3D que SceneKit générait pour chaque carrosserie. Ce volume
/// coûtait 500 lignes de géométrie, une vue UIKit par carte de la grille et une capture
/// hors écran au partage, pour montrer une voiture qui n'était aucune voiture : depuis
/// que la photo du joueur prime, il n'apparaît plus que sur les cartes du Spogdex pas
/// encore attrapées, où une silhouette dit exactement ce qu'il faut — « il reste
/// celle-là à trouver ».
struct CarSilhouette: View {
    let carBody: CarBody
    let paint: UInt32
    let tint: Color

    init(body: CarBody, paint: UInt32, tint: Color) {
        self.carBody = body
        self.paint = paint
        self.tint = tint
    }

    var body: some View {
        Image(systemName: carBody.symbol)
            .resizable()
            .scaledToFit()
            .foregroundStyle(
                LinearGradient(colors: [Color(uiColor: CarPaint.uiColor(paint)), tint.opacity(0.9)],
                               startPoint: .top, endPoint: .bottom))
            .shadow(color: tint.opacity(0.6), radius: 14)
            .padding(.horizontal, 28)
    }
}
