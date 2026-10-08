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
    /// Opacite du filet. Zero : filet neutre, aucune couleur. C'est le défaut depuis la
    /// sobriété du 09/10/2026 : chaque panneau cerclé de violet faisait un écran violet.
    /// Un appelant qui veut une couleur la demande en passant une intensité.
    var intensity: Double = 0
    /// Vrai tube lumineux, avec debordement de lumiere.
    var neon: Bool = false
    /// Etalement du halo, de 0 a 1. A reduire dans une grille : deux halos larges
    /// posés cote a cote se rejoignent et donnent l'illusion d'un seul cadre autour
    /// de la rangee, au lieu d'un cadre par carte.
    var spread: CGFloat = 1
    @ViewBuilder var content: Content

    var body: some View {
        // Plus de trame de points sous le cadre : un aplat anthracite, rien d'autre.
        content
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Theme.surface)
            }
            .modifier(FrameEdge(color: color, radius: radius, intensity: intensity,
                                neon: neon, spread: spread))
    }
}

private struct FrameEdge: ViewModifier {
    let color: Color
    let radius: CGFloat
    let intensity: Double
    let neon: Bool
    var spread: CGFloat = 1

    func body(content: Content) -> some View {
        if intensity <= 0 {
            // Rien a signaler : un filet neutre pour detourer, point.
            content.overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            }
        } else if neon {
            content.neonBorder(color: color, radius: radius, intensity: intensity, spread: spread)
        } else {
            // Un filet teinté, sans lueur : la couleur signale, elle n'éclaire pas.
            content
                .overlay {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(color.opacity(0.35 * intensity), lineWidth: 1)
                }
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
                        .fill(color.opacity(0.85))
                        .frame(width: max(value > 0 ? 6 : 0, geo.size.width * ratio))
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
    /// Blanc par défaut : six badges violets alignés faisaient une rangée de néons.
    var color: Color = Theme.textPrimary

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(unlocked ? color : Theme.textMuted.opacity(0.5))
            .frame(width: 46, height: 46)
            .background(Circle().fill(Theme.surface))
            .overlay(Circle().stroke(unlocked ? color.opacity(0.45) : Theme.stroke, lineWidth: 1))
    }
}

/// En-tete de section : etiquette capitales + valeur mise en avant.
struct SectionHeader: View {
    let overline: LocalizedStringKey
    let title: String
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .center) {
            // Titre plus grand et plus gras qu'à l'origine : à 24 points, la hiérarchie de
            // l'écran ne se lisait pas, tout avait à peu près la même taille.
            VStack(alignment: .leading, spacing: 4) {
                Overline(text: overline)
                Text(title)
                    .font(Theme.display(32, .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).minimumScaleFactor(0.7)
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
    /// Étalement du halo, de 0 à 1. Le tube lui-même ne bouge pas — seule la
    /// diffusion se resserre, pour qu'une carte en grille garde **son** cadre.
    var spread: CGFloat = 1

    @State private var breath: Double = 0.82

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
    /// Le coeur d'un tube allumé tire vers le blanc, pas vers sa propre couleur.
    private var core: Color { color.mix(with: .white, amount: 0.3) }

    func body(content: Content) -> some View {
        // Sobriété (09/10/2026) : le tube à trois couches et ses deux débordements de
        // lumière faisaient de chaque carte rare une guirlande. Il reste un filet fin à la
        // couleur du palier, éclairci au coeur, et une ombre très courte : la carte se
        // distingue d'un coup d'oeil sans éclairer l'écran.
        let level = intensity * (breathing ? breath : 1)
        return content
            .overlay {
                shape.stroke(core.opacity(0.55 * level), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: color.opacity(0.12 * level), radius: 6 * spread)
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
                    breathing: Bool = false,
                    spread: CGFloat = 1) -> some View {
        modifier(NeonBorder(color: color, radius: radius, intensity: intensity,
                            breathing: breathing, spread: spread))
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

// MARK: - Matières premium

/// Panneau de verre fumé : dégradé vertical, reflet en haut, arête qui accroche la lumière
/// et ombre portée. Remplace l'aplat gris des premières versions, que le testeur trouvait
/// plat et « cheap ». `tint` pose une lueur colorée dans un coin, pour signaler sans crier.
struct GlassCard<Content: View>: View {
    var radius: CGFloat = 20
    var tint: Color? = nil
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                // La lueur de coin (`tint`) est réduite à un soupçon : avec un panneau
                // violet, un cyan et un doré sur le même écran, rien ne se hiérarchisait.
                ZStack {
                    shape.fill(Theme.glassFill)
                    if let tint {
                        RadialGradient(colors: [tint.opacity(0.05), .clear],
                                       center: .topTrailing, startRadius: 4, endRadius: 200)
                            .clipShape(shape)
                    }
                }
                .shadow(color: Theme.dropShadow, radius: 10, y: 6)
            }
            .overlay(shape.strokeBorder(Theme.glassEdge, lineWidth: 1))
    }
}

/// Bouton principal : capsule au dégradé violet, reflet, lueur, et un léger enfoncement
/// sous le doigt. Un seul style pour toutes les actions principales de l'app, pour
/// qu'elles se reconnaissent d'un écran à l'autre.
struct NeonButtonStyle: ButtonStyle {
    /// Faux : variante secondaire, verre et filet violet, pour l'action d'à côté.
    var prominent: Bool = true
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.label(12)).tracking(1.2)
            .textCase(.uppercase)
            // Le violet est réservé au bouton principal ; le secondaire passe au neutre,
            // filet fin et texte clair, pour que l'œil sache tout de suite où appuyer.
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .padding(.horizontal, 22)
            .padding(.vertical, 15)
            .background {
                if prominent {
                    Capsule().fill(Theme.accentGradient)
                        .opacity(configuration.isPressed ? 0.85 : 1)
                } else {
                    Capsule().fill(Theme.surface)
                        .overlay(Capsule().strokeBorder(Theme.strokeStrong, lineWidth: 1))
                }
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Enfoncement léger d'une carte ou d'une tuile sous le doigt : le retour visuel qui
/// manquait aux boutons `.plain`.
struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? 0.04 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Fond des écrans principaux. Il portait deux lueurs dérivantes, violette et cyan, et une
/// trame de points : c'est la première chose que le testeur citait dans « trop de
/// couleurs ». Il reste un noir neutre, éclairci d'un rien vers le haut pour que l'écran
/// ne paraisse pas mort quand le contenu ne le remplit pas.
struct AmbientBackground: View {
    var body: some View {
        Theme.background
            .overlay {
                LinearGradient(colors: [Theme.highlight.opacity(0.025), .clear],
                               startPoint: .top, endPoint: .center)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}

/// Bande de lumière qui balaie la vue en diagonale, à intervalle régulier. Réservée à ce
/// qui attend un geste (le pack scellé, un emplacement vide) : partout, elle fatiguerait.
struct ShimmerSweep: ViewModifier {
    var active: Bool = true
    var duration: Double = 2.8
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if active {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, Theme.highlight.opacity(0.10), .clear],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.45, height: geo.size.height * 1.6)
                            .rotationEffect(.degrees(18))
                            .offset(x: phase * geo.size.width * 1.4, y: -geo.size.height * 0.3)
                    }
                    .mask { content }
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                guard active else { return }
                withAnimation(.linear(duration: duration).delay(0.6).repeatForever(autoreverses: false)) {
                    phase = 1.2
                }
            }
    }
}

extension View {
    /// Balayage lumineux (voir ShimmerSweep).
    func shimmer(_ active: Bool = true, duration: Double = 2.8) -> some View {
        modifier(ShimmerSweep(active: active, duration: duration))
    }
}

/// Puce en capsule : une icône, un texte court. Compte à rebours, pays, état.
struct InfoChip: View {
    let icon: String
    let text: Text
    var color: Color = Theme.textSecondary

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold))
            text.font(Theme.mono(10, .semibold)).lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9).padding(.vertical, 5)
        // Fond neutre et filet fin : la couleur reste dans le texte, la capsule ne s'allume pas.
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

/// Cellule de statistique : un chiffre fort, un libellé discret. Le chiffre s'anime quand
/// il change — une prise de plus se voit.
struct MetricCell: View {
    let value: Int
    let label: LocalizedStringKey
    var color: Color = Theme.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value.formatted())
                .font(Theme.hero(20))
                .monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText(value: Double(value)))
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label)
                .font(Theme.label(9)).tracking(1.1)
                .textCase(.uppercase)
                .foregroundStyle(Theme.textMuted)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Fin séparateur vertical entre deux cellules d'une même rangée.
struct HairlineDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.strokeStrong)
            .frame(width: 1, height: 30)
    }
}


