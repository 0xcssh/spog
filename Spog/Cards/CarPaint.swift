import UIKit

/// Teintes de carrosserie plausibles. La couleur reelle viendra de l'IA au moment du scan.
enum CarPaint {
    static let palette: [UInt32] = [
        0xE9EAEC, 0x17171B, 0xB4B8BE, 0x63686F, 0xB4231F, 0x1E4FA3,
        0x16233F, 0x1F5F45, 0xDCB01B, 0xC9560F, 0x5B2E8C, 0x2A6E7A,
        0x5A3A28, 0xC9B79A
    ]
    static func random() -> UInt32 { palette.randomElement() ?? 0xB4B8BE }

    /// Nom lisible de la teinte, utilise pour retrouver le rendu correspondant
    /// et pour demander sa generation.
    static func name(_ hex: UInt32) -> String {
        switch hex {
        case 0xE9EAEC: return "pearl white"
        case 0x17171B: return "gloss black"
        case 0xB4B8BE: return "metallic silver"
        case 0x63686F: return "nardo grey"
        case 0xB4231F: return "racing red"
        case 0x1E4FA3: return "electric blue"
        case 0x16233F: return "midnight navy"
        case 0x1F5F45: return "racing green"
        case 0xDCB01B: return "signal yellow"
        case 0xC9560F: return "sunset orange"
        case 0x5B2E8C: return "deep purple"
        case 0x2A6E7A: return "petrol teal"
        case 0x5A3A28: return "chocolate brown"
        case 0xC9B79A: return "sand beige"
        default:       return "metallic silver"
        }
    }
    /// Teinte renvoyee par le serveur (liste fermee, en anglais) ramenee a la palette.
    /// Nil si le serveur n'a pas su donner de couleur : la carte tire alors au sort.
    static func fromServer(_ name: String) -> UInt32? {
        switch name.lowercased() {
        case "white":     return 0xE9EAEC
        case "black":     return 0x17171B
        case "silver":    return 0xB4B8BE
        case "grey":      return 0x63686F
        case "red":       return 0xB4231F
        case "blue":      return 0x1E4FA3
        case "dark blue": return 0x16233F
        case "green":     return 0x1F5F45
        case "yellow":    return 0xDCB01B
        case "orange":    return 0xC9560F
        case "purple":    return 0x5B2E8C
        case "teal":      return 0x2A6E7A
        case "brown":     return 0x5A3A28
        case "beige":     return 0xC9B79A
        default:          return nil
        }
    }

    static func slug(_ hex: UInt32) -> String {
        name(hex).replacingOccurrences(of: " ", with: "-")
    }
    static func uiColor(_ hex: UInt32) -> UIColor {
        UIColor(red:   CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >>  8) & 0xFF) / 255,
                blue:  CGFloat( hex        & 0xFF) / 255,
                alpha: 1)
    }
}
