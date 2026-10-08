import SwiftUI
import UIKit

/// Le studio unique des modèles : un fond, un sol, une lumière, identiques sous chaque
/// voiture de l'app, et la voiture détourée posée dessus avec son reflet et son ombre.
///
/// Retour du testeur du 09/10/2026 sur la chasse de la semaine : « les images sur le
/// background ne sont jamais les mêmes, il faudrait un seul truc ultra premium qui reste
/// et qui soit figé ». Chaque rendu IA apportait son propre décor. On ne régénère rien :
/// la voiture est détourée sur l'appareil (`ModelCutoutService`) et ce décor-ci, dessiné,
/// remplace le sien.
///
/// Le décor est **décrit une fois** (`layers`) et peint par deux interprètes : SwiftUI
/// (`StudioBackdrop`, vectoriel, net à toute taille) et Core Graphics (images exportées :
/// partage, démonstration de l'onboarding). Deux dessins écrits à la main auraient fini
/// par diverger ; ici ils ne peuvent pas.
enum StudioStage {

    // MARK: Le décor

    /// Un aplat de lumière du décor. Coordonnées en part du cadre, origine en haut à gauche.
    enum Layer {
        /// Dégradé vertical sur toute la hauteur.
        case vertical([(Color, CGFloat)])
        /// Halo elliptique : centre, demi-axes (en part de la largeur et de la hauteur).
        case halo(center: CGPoint, radiusX: CGFloat, radiusY: CGFloat, stops: [(Color, CGFloat)])
    }

    static let layers: [Layer] = {
        let ground = StudioStageLayout.groundLine
        return [
            // Le mur s'assombrit en descendant ; le sol, lui, reprend de la lumière juste
            // sous la voiture puis se perd au premier plan. Un sol plus clair que le bas du
            // mur, c'est ce qui donne à l'ombre de contact quelque chose sur quoi se poser :
            // sur un sol aussi sombre qu'elle, la voiture semblait flotter (retour testeur).
            .vertical([(Theme.studioTop, 0), (Theme.studioWall, ground - 0.16),
                       (Theme.studioGround, ground + 0.02), (Theme.studioFloor, 1)]),
            // Le projecteur, au-dessus du cadre : un blanc froid très faible.
            .halo(center: CGPoint(x: 0.5, y: -0.12), radiusX: 0.72, radiusY: 0.9,
                  stops: [(Theme.studioLight.opacity(0.14), 0), (Theme.studioLight.opacity(0), 1)]),
            // La flaque de lumière au sol, sous la voiture : assez nette pour qu'on lise un
            // plan horizontal.
            .halo(center: CGPoint(x: 0.5, y: ground + 0.01), radiusX: 0.6, radiusY: 0.15,
                  stops: [(Theme.studioLight.opacity(0.16), 0), (Theme.studioLight.opacity(0.06), 0.55),
                          (Theme.studioLight.opacity(0), 1)]),
            // Vignettage : les bords tombent dans le noir, l'œil revient au centre.
            .halo(center: CGPoint(x: 0.5, y: 0.45), radiusX: 0.85, radiusY: 0.9,
                  stops: [(Color.black.opacity(0), 0.55), (Color.black.opacity(0.4), 1)]),
        ]
    }()

    /// Le décor peint en Core Graphics, dans un contexte aux coordonnées UIKit (y vers le
    /// bas, comme `UIGraphicsImageRenderer`).
    static func drawBackdrop(in ctx: CGContext, size: CGSize) {
        let space = CGColorSpaceCreateDeviceRGB()
        // Les deux côtés : un halo qui se termine en transparent ne change rien au-delà, et
        // le vignettage, lui, doit rester noir jusqu'aux coins.
        let extend: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        for layer in layers {
            switch layer {
            case .vertical(let stops):
                guard let gradient = cgGradient(stops, space: space) else { continue }
                ctx.drawLinearGradient(gradient, start: .zero,
                                       end: CGPoint(x: 0, y: size.height), options: extend)
            case .halo(let center, let radiusX, let radiusY, let stops):
                guard let gradient = cgGradient(stops, space: space) else { continue }
                let rx = max(1, radiusX * size.width), ry = max(1, radiusY * size.height)
                ctx.saveGState()
                ctx.clip(to: CGRect(origin: .zero, size: size))
                ctx.translateBy(x: center.x * size.width, y: center.y * size.height)
                ctx.scaleBy(x: 1, y: ry / rx)
                ctx.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0,
                                       endCenter: .zero, endRadius: rx, options: extend)
                ctx.restoreGState()
            }
        }
    }

    private static func cgGradient(_ stops: [(Color, CGFloat)], space: CGColorSpace) -> CGGradient? {
        CGGradient(colorsSpace: space,
                   colors: stops.map { UIColor($0.0).cgColor } as CFArray,
                   locations: stops.map { $0.1 })
    }

    // MARK: La voiture

    /// La voiture, son reflet et son ombre de contact, dans un contexte aux coordonnées
    /// UIKit. Le décor n'est pas peint ici : la vue le dessine à part, en vectoriel.
    static func drawCar(_ cutout: UIImage, in ctx: CGContext, size: CGSize) {
        let car = StudioStageLayout.carRect(subject: cutout.size, in: size)
        guard car.width > 0 else { return }
        ctx.interpolationQuality = .high
        drawReflection(cutout, car: car, in: ctx)
        drawContactShadow(car: car, in: ctx)
        cutout.draw(in: car)
    }

    /// Le reflet : la voiture retournée sous la ligne de sol, qui s'efface en s'éloignant.
    /// Doux exprès : un sol miroir franc, c'est précisément le décor clinquant qu'on retire.
    private static func drawReflection(_ cutout: UIImage, car: CGRect, in ctx: CGContext) {
        let area = StudioStageLayout.reflectionRect(for: car)
        let space = CGColorSpaceCreateDeviceRGB()
        let fade = [UIColor.black.withAlphaComponent(0.28).cgColor,
                    UIColor.black.withAlphaComponent(0).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: space, colors: fade, locations: [0, 1]) else { return }

        ctx.saveGState()
        ctx.clip(to: area)
        // Calque isolé : le « destinationIn » qui suit ne doit effacer que le reflet.
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.saveGState()
        // Miroir autour de la ligne de sol : le bas des pneus touche son propre reflet.
        ctx.translateBy(x: 0, y: car.maxY * 2)
        ctx.scaleBy(x: 1, y: -1)
        cutout.draw(in: car)
        ctx.restoreGState()
        ctx.setBlendMode(.destinationIn)
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: area.minY),
                               end: CGPoint(x: 0, y: area.maxY),
                               options: [.drawsAfterEndLocation])
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    /// Trois ombres : une large et diffuse qui pose la voiture, une plus serrée sous la
    /// caisse, et un trait presque noir pile sur la ligne des roues — l'occlusion de
    /// contact, sans laquelle elle semble flotter au-dessus du sol.
    private static func drawContactShadow(car: CGRect, in ctx: CGContext) {
        let space = CGColorSpaceCreateDeviceRGB()
        let shadows: [(rx: CGFloat, ry: CGFloat, lift: CGFloat, alpha: CGFloat)] = [
            (car.width * 0.62, car.height * 0.14, 0.15, 0.6),
            (car.width * 0.5, car.height * 0.06, 0.25, 0.85),
            (car.width * 0.44, car.height * 0.022, 0.1, 0.95),
        ]
        for shadow in shadows {
            let colors = [UIColor.black.withAlphaComponent(shadow.alpha).cgColor,
                          UIColor.black.withAlphaComponent(shadow.alpha * 0.5).cgColor,
                          UIColor.black.withAlphaComponent(0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: space, colors: colors,
                                            locations: [0, 0.5, 1]) else { continue }
            ctx.saveGState()
            // Centrée à peine au-dessus du bas de la boîte (recadré sur les roues, voir
            // `ModelCutoutService.trimmedToGround`) : la moitié haute passe sous la caisse.
            ctx.translateBy(x: car.midX, y: car.maxY - shadow.ry * shadow.lift)
            ctx.scaleBy(x: 1, y: shadow.ry / shadow.rx)
            ctx.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0,
                                   endCenter: .zero, endRadius: shadow.rx, options: [])
            ctx.restoreGState()
        }
    }

    // MARK: Images

    /// Le calque de la voiture (fond transparent), à la taille exacte en pixels de la vue.
    ///
    /// Plutôt que de laisser SwiftUI réduire une découpe de 900 px dans une vignette de
    /// 110 points (crénelage) ou agrandir celle d'un bandeau de 660 px : Core Graphics
    /// rééchantillonne une fois, en haute qualité, à la bonne taille.
    static func carLayer(_ cutout: UIImage, size: CGSize, scale: CGFloat) -> UIImage? {
        guard size.width >= 1, size.height >= 1 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            drawCar(cutout, in: renderer.cgContext, size: size)
        }
    }

    /// Le studio complet, décor compris, pour les images qui quittent l'écran.
    static func render(_ cutout: UIImage, size: CGSize, scale: CGFloat) -> UIImage? {
        guard size.width >= 1, size.height >= 1 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            drawBackdrop(in: renderer.cgContext, size: size)
            drawCar(cutout, in: renderer.cgContext, size: size)
        }
    }

    // MARK: Cache des calques

    /// Un calque par découpe, taille et échelle. Coût en octets : une grille de vingt
    /// vignettes tient en quelques mégaoctets, une carte plein écran en pèse quatre.
    private static let layerCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    static func layerKey(_ cutoutKey: String, size: CGSize, scale: CGFloat) -> String {
        "\(cutoutKey)@\(Int(size.width))x\(Int(size.height))x\(Int(scale * 10))"
    }

    static func cachedLayer(_ key: String) -> UIImage? {
        layerCache.object(forKey: key as NSString)
    }

    static func storeLayer(_ image: UIImage, key: String) {
        let pixels = image.size.width * image.size.height * image.scale * image.scale
        layerCache.setObject(image, forKey: key as NSString, cost: Int(pixels * 4))
    }
}

/// Une image en remplissage, rééchantillonnée à la taille exacte en pixels de la vue.
///
/// Sert au repli du studio : le rendu HD tel quel, quand le détourage a échoué. SwiftUI
/// affiche l'image tout de suite (interpolation haute), puis la version réduite par Core
/// Graphics la remplace dès qu'elle est prête — un 1024² réduit par le GPU dans une
/// vignette de 110 points scintille sur les jantes et les arêtes.
struct SharpFill: View {
    let image: UIImage
    /// Identifie l'image dans le cache : jamais l'adresse de l'objet, qu'iOS réutilise.
    let key: String

    @Environment(\.displayScale) private var displayScale
    @State private var resampled: (key: String, image: UIImage)?

    var body: some View {
        GeometryReader { proxy in
            let size = CGSize(width: proxy.size.width.rounded(), height: proxy.size.height.rounded())
            let id = StudioStage.layerKey("fill-" + key, size: size, scale: displayScale)
            let sharp = resampled?.key == id ? resampled?.image : StudioStage.cachedLayer(id)
            Image(uiImage: sharp ?? image)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .task(id: id) { await resample(id: id, size: size) }
        }
    }

    private func resample(id: String, size: CGSize) async {
        if let hit = StudioStage.cachedLayer(id) {
            resampled = (id, hit)
            return
        }
        // Agrandir ne gagne rien : seule une réduction mérite le détour.
        let pixels = image.size.width * image.scale
        guard size.width > 0, size.height > 0, image.size.width > 0, image.size.height > 0 else { return }
        let fill = max(size.width / image.size.width, size.height / image.size.height)
        guard pixels > image.size.width * fill * displayScale * 1.2 else { return }
        let image = image, scale = displayScale
        let result = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            format.opaque = true
            let drawn = CGSize(width: image.size.width * fill, height: image.size.height * fill)
            let output = UIGraphicsImageRenderer(size: size, format: format).image { renderer in
                renderer.cgContext.interpolationQuality = .high
                image.draw(in: CGRect(x: (size.width - drawn.width) / 2,
                                      y: (size.height - drawn.height) / 2,
                                      width: drawn.width, height: drawn.height))
            }
            StudioStage.storeLayer(output, key: id)
            return output
        }.value
        guard let result, !Task.isCancelled else { return }
        resampled = (id, result)
    }
}

/// Le décor du studio, en vectoriel : net à toute taille, identique partout.
struct StudioBackdrop: View {
    var body: some View {
        Canvas { context, size in
            let frame = CGRect(origin: .zero, size: size)
            for layer in StudioStage.layers {
                switch layer {
                case .vertical(let stops):
                    context.fill(Path(frame), with: .linearGradient(
                        gradient(stops), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                case .halo(let center, let radiusX, let radiusY, let stops):
                    let rx = max(1, radiusX * size.width), ry = max(1, radiusY * size.height)
                    let squash = ry / rx
                    let origin = CGPoint(x: center.x * size.width, y: center.y * size.height)
                    var halo = context
                    halo.translateBy(x: origin.x, y: origin.y)
                    halo.scaleBy(x: 1, y: squash)
                    // Le cadre entier, ramené dans le repère aplati du halo.
                    let cover = CGRect(x: -origin.x, y: -origin.y / squash,
                                       width: size.width, height: size.height / squash)
                    // Sans option, le dégradé prolonge sa dernière teinte au-delà du rayon :
                    // c'est ce qui garde les coins du vignettage dans le noir.
                    halo.fill(Path(cover), with: .radialGradient(
                        gradient(stops), center: .zero, startRadius: 0, endRadius: rx))
                }
            }
        }
    }

    private func gradient(_ stops: [(Color, CGFloat)]) -> Gradient {
        Gradient(stops: stops.map { Gradient.Stop(color: $0.0, location: $0.1) })
    }
}

/// Une voiture détourée posée sur le studio, au cadrage commun à toute l'app.
///
/// Le calque de la voiture est rendu hors du fil principal, à la taille exacte en pixels
/// de la vue ; le décor, lui, est toujours là, et la voiture s'y pose en fondu.
struct StagedCar: View {
    let cutout: UIImage
    /// Identifie la découpe (modèle, source, teinte) dans le cache des calques.
    let cutoutKey: String
    /// Faux quand l'appelant dessine déjà le décor dessous (`ModelArt`).
    var showsBackdrop: Bool = true

    @Environment(\.displayScale) private var displayScale
    @State private var rendered: (key: String, image: UIImage)?

    var body: some View {
        GeometryReader { proxy in
            let size = CGSize(width: proxy.size.width.rounded(), height: proxy.size.height.rounded())
            let key = StudioStage.layerKey(cutoutKey, size: size, scale: displayScale)
            let layer = rendered?.key == key ? rendered?.image : StudioStage.cachedLayer(key)
            ZStack {
                if showsBackdrop { StudioBackdrop() }
                if let layer {
                    Image(uiImage: layer)
                        .resizable()
                        .interpolation(.high)
                        .transition(.opacity)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(.easeOut(duration: 0.2), value: layer != nil)
            .task(id: key) { await render(key: key, size: size) }
        }
    }

    private func render(key: String, size: CGSize) async {
        if let hit = StudioStage.cachedLayer(key) {
            rendered = (key, hit)
            return
        }
        let cutout = cutout, scale = displayScale
        let image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let layer = StudioStage.carLayer(cutout, size: size, scale: scale) else { return nil }
            StudioStage.storeLayer(layer, key: key)
            return layer
        }.value
        guard let image, !Task.isCancelled else { return }
        rendered = (key, image)
    }
}
