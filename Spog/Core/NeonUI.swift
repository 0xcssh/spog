import SwiftUI

/// Briques visuelles communes, dans le style neon sombre de l'app.
/// Toute la couleur vient de Theme : ne jamais ecrire une couleur ici.

/// Fond texture en points, tres discret, repris du logo.
struct DotGrid: View {
    var spacing: CGFloat = 14
    var body: some View {
        Canvas { context, size in
            let dot = Path(ellipseIn: CGRect(x: 0, y: 0, width: 1.2, height: 1.2))
            var y: CGFloat = 0
            while y < size.height {
                var x: CGFloat = 0
                while x < size.width {
                    context.fill(dot.offsetBy(dx: x, dy: y), with: .color(Color.white.opacity(0.035)))
                    x += spacing
                }
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

/// Cadre a contour lumineux. La brique de base des tuiles et panneaux.
/// Par defaut un simple filet colore ; le vrai neon est reserve aux cartes rares,
/// sinon tout l'ecran brille et plus rien ne se distingue.
struct NeonFrame<Content: View>: View {
    var color: Color = Theme.accent
    var radius: CGFloat = 16
    /// Opacite du filet. Zero : filet neutre, aucune couleur.
    var intensity: Double = 1
    /// Vrai tube lumineux, avec debordement de lumiere.
    var neon: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(DotGrid().clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous)))
            }
            .modifier(FrameEdge(color: color, radius: radius, intensity: intensity, neon: neon))
    }
}

private struct FrameEdge: ViewModifier {
    let color: Color
    let radius: CGFloat
    let intensity: Double
    let neon: Bool

    func body(content: Content) -> some View {
        if intensity <= 0 {
            // Rien a signaler : un filet neutre pour detourer, point.
            content.overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            }
        } else if neon {
            content.neonBorder(color: color, radius: radius, intensity: intensity)
        } else {
            content
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(color.opacity(0.55 * intensity), lineWidth: 1)
                }
                .shadow(color: color.opacity(0.26 * intensity), radius: 12)
        }
    }
}

/// Petite tuile carree : icone en contour lumineux, valeur, libelle.
struct NeonTile: View {
    let icon: String
    let value: String
    let label: LocalizedStringKey
    var color: Color = Theme.accent

    var body: some View {
        NeonFrame(color: color, radius: 14) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(color)
                    .shadow(color: color.opacity(0.8), radius: 6)
                Text(value)
                    .font(Theme.display(19))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(label)
                    .font(Theme.label(9)).tracking(1).textCase(.uppercase)
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
    }
}

/// Barre de progression segmentee, facon jauge de jeu.
struct SegmentedBar: View {
    let progress: Double        // 0...1
    var color: Color = Theme.accent
    var segments: Int = 22
    var height: CGFloat = 9

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<segments, id: \.self) { index in
                let filled = Double(index) / Double(segments) < progress
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(filled ? color : Theme.textMuted.opacity(0.18))
                    .shadow(color: filled ? color.opacity(0.9) : .clear, radius: 4)
            }
        }
        .frame(height: height)
    }
}

/// Ligne de statistique : libelle, barre proportionnelle, valeur.
struct StatRow: View {
    let label: LocalizedStringKey
    let value: Int
    let total: Int
    let color: Color

    private var ratio: Double { total > 0 ? Double(value) / Double(total) : 0 }

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(Theme.label(10)).tracking(1).textCase(.uppercase)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 96, alignment: .leading)
                .lineLimit(1).minimumScaleFactor(0.7)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.textMuted.opacity(0.14))
                    Capsule()
                        .fill(LinearGradient(colors: [color.opacity(0.5), color],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(value > 0 ? 6 : 0, geo.size.width * ratio))
                        .shadow(color: color.opacity(0.7), radius: 5)
                }
            }
            .frame(height: 7)

            Text("\(value)")
                .font(Theme.mono(11, .semibold))
                .foregroundStyle(value > 0 ? color : Theme.textMuted)
                .frame(width: 26, alignment: .trailing)
        }
    }
}

/// Pastille de badge circulaire.
struct BadgeChip: View {
    let icon: String
    let unlocked: Bool
    var color: Color = Theme.accent

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(unlocked ? color : Theme.textMuted.opacity(0.5))
            .frame(width: 46, height: 46)
            .background(Circle().fill(Theme.surface))
            .overlay(Circle().stroke(unlocked ? color.opacity(0.6) : Theme.stroke, lineWidth: 1))
            .shadow(color: unlocked ? color.opacity(0.45) : .clear, radius: 9)
    }
}

/// En-tete de section : etiquette capitales + valeur mise en avant.
struct SectionHeader: View {
    let overline: LocalizedStringKey
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Overline(text: overline)
                Text(title)
                    .font(Theme.display(24))
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            if let trailing { trailing }
        }
    }
}

// MARK: - Néon

/// Cerne une forme d'un vrai tube de néon : un coeur clair presque blanc,
/// un halo serré à la couleur choisie, puis une diffusion large.
/// Un simple trait coloré ne suffit pas — c'est l'empilement qui fait le néon.
struct NeonBorder: ViewModifier {
    var color: Color = RarityTier.trophyGold
    var radius: CGFloat = 22
    /// 0 = éteint, 1 = pleine puissance.
    var intensity: Double = 1
    /// Respiration lente. À réserver aux écrans où une seule carte est visible.
    var breathing: Bool = false

    @State private var breath: Double = 0.82

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
    /// Le coeur d'un tube allumé tire vers le blanc, pas vers sa propre couleur.
    private var core: Color { color.mix(with: .white, amount: 0.6) }

    func body(content: Content) -> some View {
        let level = intensity * (breathing ? breath : 1)
        return content
            .overlay {
                ZStack {
                    shape.stroke(color.opacity(0.42 * level), lineWidth: 7).blur(radius: 11)
                    shape.stroke(color.opacity(0.85 * level), lineWidth: 2.6).blur(radius: 3)
                    shape.stroke(core.opacity(0.95 * level), lineWidth: 1.1)
                }
                .allowsHitTesting(false)
            }
            // Débordement de lumière au-delà de la carte
            .shadow(color: color.opacity(0.50 * level), radius: 16)
            .shadow(color: color.opacity(0.26 * level), radius: 34)
            .onAppear {
                guard breathing else { return }
                withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
                    breath = 1.0
                }
            }
    }
}

extension View {
    /// Néon autour de la vue. `intensity` à 0 n'affiche rien.
    func neonBorder(color: Color = RarityTier.trophyGold,
                    radius: CGFloat = 22,
                    intensity: Double = 1,
                    breathing: Bool = false) -> some View {
        modifier(NeonBorder(color: color, radius: radius,
                            intensity: intensity, breathing: breathing))
    }
}

private extension Color {
    /// Mélange vers une autre couleur, pour éclaircir le coeur du tube.
    func mix(with other: Color, amount: Double) -> Color {
        let a = UIColor(self), b = UIColor(other)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = CGFloat(amount)
        return Color(.sRGB,
                     red: Double(r1 + (r2 - r1) * t),
                     green: Double(g1 + (g2 - g1) * t),
                     blue: Double(b1 + (b2 - b1) * t),
                     opacity: 1)
    }
}


