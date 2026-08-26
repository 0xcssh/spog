import SwiftUI
import SceneKit

/// Voiture en trois dimensions, construite par le code a partir du type de carrosserie
/// et de la couleur. Peinture metallisee, vitrage teinte, jantes, sol reflechissant.
/// Aucun modele 3D a acquerir : la geometrie est generee, donc valable pour les 510 vehicules.
struct Car3DView: UIViewRepresentable {

    let body: CarBody
    let paint: UIColor
    /// Rotation imposee par le doigt, en degres.
    var yaw: Double
    var pitch: Double
    var accent: UIColor

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.isUserInteractionEnabled = false
        view.scene = CarSceneBuilder.scene(body: body, paint: paint, accent: accent)
        view.pointOfView = view.scene?.rootNode.childNode(withName: "camera", recursively: true)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        guard let rig = view.scene?.rootNode.childNode(withName: "rig", recursively: false) else { return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0
        rig.eulerAngles = SCNVector3(Float(pitch * .pi / 180),
                                     Float(yaw * .pi / 180),
                                     0)
        SCNTransaction.commit()
    }
}

/// Types de carrosserie. Correspond au champ `body` du catalogue.
enum CarBody: String {
    case hatch, sedan, suv, sport, pickup, van

    init(_ raw: String) { self = CarBody(rawValue: raw) ?? .sedan }

    struct Spec {
        let length, width, sill, wheel, frontAxle, rearAxle: CGFloat
        let cabinLength, cabinHeight, cabinX, cabinY: CGFloat
        /// Profil de la carrosserie, de l'arriere bas jusqu'a l'avant bas.
        let roof: [CGPoint]
    }

    private static func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

    var spec: Spec {
        switch self {
        case .hatch:
            return Spec(length: 3.70, width: 1.70, sill: 0.55, wheel: 0.33,
                        frontAxle: 3.00, rearAxle: 0.80,
                        cabinLength: 1.85, cabinHeight: 0.34, cabinX: 1.62, cabinY: 1.33,
                        roof: [Self.p(0.02, 0.62), Self.p(0.05, 1.18), Self.p(0.55, 1.52),
                               Self.p(1.55, 1.58), Self.p(2.35, 1.55), Self.p(2.85, 1.14),
                               Self.p(3.45, 1.04), Self.p(3.65, 0.92), Self.p(3.70, 0.70)])
        case .sedan:
            return Spec(length: 4.60, width: 1.82, sill: 0.55, wheel: 0.36,
                        frontAxle: 3.75, rearAxle: 0.95,
                        cabinLength: 1.55, cabinHeight: 0.36, cabinX: 2.65, cabinY: 1.39,
                        roof: [Self.p(0.02, 0.62), Self.p(0.02, 1.00), Self.p(0.45, 1.10),
                               Self.p(1.30, 1.16), Self.p(1.85, 1.58), Self.p(2.85, 1.62),
                               Self.p(3.45, 1.14), Self.p(4.15, 1.06), Self.p(4.50, 0.98),
                               Self.p(4.60, 0.72)])
        case .sport:
            return Spec(length: 4.30, width: 1.92, sill: 0.42, wheel: 0.36,
                        frontAxle: 3.50, rearAxle: 0.85,
                        cabinLength: 1.10, cabinHeight: 0.24, cabinX: 2.15, cabinY: 1.02,
                        roof: [Self.p(0.02, 0.48), Self.p(0.05, 0.82), Self.p(0.60, 0.92),
                               Self.p(1.25, 1.02), Self.p(1.80, 1.16), Self.p(2.45, 1.20),
                               Self.p(3.05, 0.92), Self.p(3.90, 0.80), Self.p(4.20, 0.72),
                               Self.p(4.30, 0.55)])
        case .suv:
            return Spec(length: 4.50, width: 1.92, sill: 0.72, wheel: 0.44,
                        frontAxle: 3.60, rearAxle: 1.00,
                        cabinLength: 2.45, cabinHeight: 0.42, cabinX: 1.92, cabinY: 1.66,
                        roof: [Self.p(0.03, 0.80), Self.p(0.05, 1.55), Self.p(0.45, 1.90),
                               Self.p(1.50, 1.96), Self.p(2.90, 1.94), Self.p(3.35, 1.55),
                               Self.p(4.05, 1.42), Self.p(4.40, 1.30), Self.p(4.50, 0.95)])
        case .van:
            return Spec(length: 5.00, width: 1.90, sill: 0.62, wheel: 0.38,
                        frontAxle: 4.00, rearAxle: 1.05,
                        cabinLength: 2.95, cabinHeight: 0.50, cabinX: 2.35, cabinY: 1.80,
                        roof: [Self.p(0.03, 0.70), Self.p(0.03, 1.95), Self.p(0.40, 2.15),
                               Self.p(3.60, 2.18), Self.p(4.20, 1.55), Self.p(4.75, 1.35),
                               Self.p(5.00, 1.05)])
        case .pickup:
            return Spec(length: 5.30, width: 1.98, sill: 0.72, wheel: 0.46,
                        frontAxle: 4.20, rearAxle: 1.10,
                        cabinLength: 1.15, cabinHeight: 0.40, cabinX: 3.00, cabinY: 1.72,
                        roof: [Self.p(0.03, 0.82), Self.p(0.03, 1.35), Self.p(2.30, 1.38),
                               Self.p(2.35, 1.95), Self.p(3.60, 1.98), Self.p(4.05, 1.55),
                               Self.p(4.85, 1.45), Self.p(5.15, 1.35), Self.p(5.30, 1.00)])
        }
    }
}

/// Fabrique la scene : voiture, lumieres, sol, camera.
enum CarSceneBuilder {

    static func scene(body: CarBody, paint: UIColor, accent: UIColor) -> SCNScene {
        let scene = SCNScene()
        // Fond de studio : une nappe grise, plus claire derriere la voiture,
        // qui s'assombrit vers les bords. C'est ce halo qui fait le "posee en studio".
        scene.background.contents = UIColor(white: 0.03, alpha: 1)
        scene.lightingEnvironment.contents = environmentImage()
        scene.lightingEnvironment.intensity = 1.15

        let rig = SCNNode()
        rig.name = "rig"
        rig.addChildNode(carNode(body: body, paint: paint))
        rig.addChildNode(contactShadow(body.spec))
        scene.rootNode.addChildNode(rig)

        scene.rootNode.addChildNode(backdropNode(accent: accent))
        scene.rootNode.addChildNode(floorNode())
        for light in lights(accent: accent) { scene.rootNode.addChildNode(light) }

        let camera = SCNCamera()
        camera.fieldOfView = 23
        camera.wantsHDR = true
        camera.bloomIntensity = 0.08
        camera.bloomThreshold = 0.92
        camera.wantsDepthOfField = false
        let cameraNode = SCNNode()
        cameraNode.name = "camera"
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 1.0, 12)
        cameraNode.look(at: SCNVector3(0, 0.82, 0))
        scene.rootNode.addChildNode(cameraNode)

        return scene
    }

    // MARK: Voiture

    /// La caisse est un vrai profil de carrosserie extrude sur la largeur :
    /// capot, pare-brise incline, ligne de toit, custode, passages de roue.
    /// Bien plus juste qu'un empilement de boites.
    private static func carNode(body: CarBody, paint: UIColor) -> SCNNode {
        let s = body.spec
        let node = SCNNode()

        let paintMaterial = SCNMaterial()
        paintMaterial.lightingModel = .physicallyBased
        paintMaterial.diffuse.contents = paint
        paintMaterial.metalness.contents = 0.7
        paintMaterial.roughness.contents = 0.2
        paintMaterial.clearCoat.contents = 1.0
        paintMaterial.clearCoatRoughness.contents = 0.05
        paintMaterial.isDoubleSided = true

        let shape = SCNShape(path: profile(s), extrusionDepth: s.width)
        shape.chamferRadius = 0.06
        shape.materials = [paintMaterial]
        let shell = SCNNode(geometry: shape)
        shell.position = SCNVector3(-s.length / 2, 0, 0)   // centrer sur l'origine
        node.addChildNode(shell)

        // Vitrage : une plaque sombre glissee dans l'ouverture de l'habitacle
        let glass = SCNMaterial()
        glass.lightingModel = .physicallyBased
        glass.diffuse.contents = UIColor(white: 0.04, alpha: 1)
        glass.metalness.contents = 0.35
        glass.roughness.contents = 0.06
        let window = SCNBox(width: s.cabinLength, height: s.cabinHeight,
                            length: s.width * 1.02, chamferRadius: 0.05)
        window.materials = [glass]
        let windowNode = SCNNode(geometry: window)
        windowNode.position = SCNVector3(s.cabinX - s.length / 2, s.cabinY, 0)
        node.addChildNode(windowNode)

        // Roues
        for xPos in [s.frontAxle, s.rearAxle] {
            for zSign in [1.0, -1.0] {
                let wheel = wheelNode(radius: s.wheel, width: s.width * 0.13)
                wheel.position = SCNVector3(xPos - s.length / 2,
                                            s.wheel,
                                            CGFloat(zSign) * (s.width / 2 - 0.11))
                node.addChildNode(wheel)
            }
        }

        // Feux
        node.addChildNode(lightBar(width: s.width * 0.92, x: s.length / 2 - 0.08,
                                   y: s.sill + 0.22,
                                   color: UIColor(white: 0.95, alpha: 1)))
        node.addChildNode(lightBar(width: s.width * 0.92, x: -s.length / 2 + 0.08,
                                   y: s.sill + 0.22,
                                   color: UIColor(red: 1, green: 0.12, blue: 0.15, alpha: 1)))
        return node
    }

    /// Profil vu de cote, dessine dans le sens des Y croissants vers le haut.
    /// L'avant est a droite (x = longueur).
    private static func profile(_ s: CarBody.Spec) -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: CGPoint(x: s.roof[0].x, y: s.roof[0].y))
        for point in s.roof.dropFirst() { path.addLine(to: point) }

        // Descente vers le bas de caisse a l'avant
        path.addLine(to: CGPoint(x: s.length, y: s.sill))

        // Retour vers l'arriere, en contournant les deux passages de roue
        for axle in [s.frontAxle, s.rearAxle] {
            let arch = s.wheel * 1.12
            path.addLine(to: CGPoint(x: axle + arch, y: s.sill))
            // demi-cercle vers le haut, echantillonne a la main pour eviter
            // toute ambiguite de sens de rotation entre UIKit et SceneKit
            for step in 0...12 {
                let angle = Double(step) / 12 * Double.pi
                path.addLine(to: CGPoint(x: axle + arch * cos(angle),
                                         y: s.sill + arch * 0.72 * sin(angle)))
            }
        }
        path.addLine(to: CGPoint(x: 0, y: s.sill))
        path.close()
        path.flatness = 0.01
        return path
    }

    private static func wheelNode(radius: CGFloat, width: CGFloat) -> SCNNode {
        let tyre = SCNCylinder(radius: radius, height: width)
        let rubber = SCNMaterial()
        rubber.lightingModel = .physicallyBased
        rubber.diffuse.contents = UIColor(white: 0.05, alpha: 1)
        rubber.roughness.contents = 0.9
        rubber.metalness.contents = 0.0
        tyre.materials = [rubber]

        let node = SCNNode(geometry: tyre)
        node.eulerAngles = SCNVector3(Float.pi / 2, 0, 0)   // axe en travers de la voiture

        let rim = SCNCylinder(radius: radius * 0.6, height: width * 1.08)
        let metal = SCNMaterial()
        metal.lightingModel = .physicallyBased
        metal.diffuse.contents = UIColor(white: 0.68, alpha: 1)
        metal.metalness.contents = 1.0
        metal.roughness.contents = 0.2
        rim.materials = [metal]
        node.addChildNode(SCNNode(geometry: rim))
        return node
    }

    private static func lightBar(width: CGFloat, x: CGFloat, y: CGFloat, color: UIColor) -> SCNNode {
        let bar = SCNBox(width: 0.1, height: 0.12, length: width, chamferRadius: 0.03)
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color
        material.emission.contents = color
        material.emission.intensity = 0.7
        bar.materials = [material]
        let node = SCNNode(geometry: bar)
        node.position = SCNVector3(x, y, 0)
        return node
    }

    // MARK: Decor

    private static func floorNode() -> SCNNode {
        let floor = SCNFloor()
        floor.reflectivity = 0.34
        floor.reflectionFalloffEnd = 3.2
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = UIColor(white: 0.055, alpha: 1)
        material.roughness.contents = 0.30
        material.metalness.contents = 0.0
        floor.materials = [material]
        return SCNNode(geometry: floor)
    }

    private static func lights(accent: UIColor) -> [SCNNode] {
        // Lumiere principale : directionnelle. C'est le seul type sur lequel les ombres
        // de SceneKit sont fiables ; les boites a lumiere servent au modele, pas a l'ombre.
        let key = SCNLight()
        key.type = .directional
        key.intensity = 780
        key.color = UIColor(white: 1.0, alpha: 1)
        key.castsShadow = true
        key.shadowMode = .deferred
        key.shadowRadius = 10
        key.shadowSampleCount = 16
        key.shadowColor = UIColor(white: 0, alpha: 0.5)
        key.orthographicScale = 4
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(-3.5, 7, 5)
        keyNode.look(at: SCNVector3(0, 0.5, 0))

        // Boite a lumiere d'appoint, cote oppose : deboucher sans creer d'ombre.
        let fill = SCNLight()
        fill.type = .area
        fill.areaType = .rectangle
        fill.areaExtents = SIMD3<Float>(8, 5, 1)
        fill.intensity = 300
        fill.color = UIColor(white: 0.96, alpha: 1)
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.position = SCNVector3(5.5, 3.2, 4)
        fillNode.look(at: SCNVector3(0, 0.7, 0))

        // Contre-jour blanc, derriere : detache la voiture du fond.
        // Volontairement neutre — la couleur de rarete vit dans l'habillage de la carte,
        // pas sur la carrosserie, sinon toutes les voitures se ressemblent.
        let rim = SCNLight()
        rim.type = .omni
        rim.intensity = 520
        rim.color = accent
        rim.attenuationStartDistance = 2
        rim.attenuationEndDistance = 7.5      // n'atteint pas le sol au loin
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.position = SCNVector3(-0.8, 3.0, -4.2)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 170
        ambient.color = UIColor(white: 0.45, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient

        return [keyNode, fillNode, rimNode, ambientNode]
    }

    /// Tache sombre posee sous la voiture. Sans elle, l'oeil la voit flotter,
    /// quelle que soit la qualite de l'ombre calculee.
    private static func contactShadow(_ spec: CarBody.Spec) -> SCNNode {
        let plane = SCNPlane(width: spec.length * 1.05, height: spec.width * 1.9)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor.black
        material.transparent.contents = softBlobImage()
        material.transparencyMode = .aOne
        material.writesToDepthBuffer = false
        material.isDoubleSided = true
        plane.materials = [material]

        let node = SCNNode(geometry: plane)
        node.eulerAngles = SCNVector3(-Double.pi / 2, 0, 0)
        node.position = SCNVector3(0, 0.012, 0)
        node.renderingOrder = -1
        return node
    }

    /// Degrade radial doux, du blanc opaque au transparent : sert de masque a l'ombre.
    private static func softBlobImage() -> UIImage {
        let size = CGSize(width: 256, height: 256)
        return UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor(white: 1, alpha: 0.85).cgColor,
                          UIColor(white: 1, alpha: 0.35).cgColor,
                          UIColor(white: 1, alpha: 0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(),
                                            colors: colors, locations: [0, 0.45, 1]) else { return }
            context.cgContext.drawRadialGradient(
                gradient,
                startCenter: CGPoint(x: 128, y: 128), startRadius: 0,
                endCenter: CGPoint(x: 128, y: 128), endRadius: 126, options: [])
        }
    }

    /// Panneau de fond, pose derriere la voiture et immobile quand elle tourne.
    /// Un vrai objet de la scene, pas une image d'environnement : c'est le seul moyen
    /// de maitriser ce qui entre dans le cadre.
    private static func backdropNode(accent: UIColor) -> SCNNode {
        let panel = SCNPlane(width: 11.5, height: 9)
        let material = SCNMaterial()
        material.lightingModel = .constant          // le decor ne recoit pas la lumiere
        material.diffuse.contents = backdropImage(accent: accent)
        material.isDoubleSided = false
        panel.materials = [material]

        let node = SCNNode(geometry: panel)
        node.position = SCNVector3(0, 1.4, -9)
        return node
    }

    /// Fond de garage : noir profond, traverse de barres de neon a la couleur du palier.
    /// C'est la mise en scene de la maquette — pas un studio neutre.
    private static func backdropImage(accent: UIColor) -> UIImage {
        let size = CGSize(width: 1024, height: 512)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext

            // Nuit d'atelier
            cg.setFillColor(UIColor(white: 0.045, alpha: 1).cgColor)
            cg.fill(CGRect(origin: .zero, size: size))

            // Halo diffus derriere la voiture
            let colors = [accent.withAlphaComponent(0.26).cgColor,
                          accent.withAlphaComponent(0.05).cgColor,
                          UIColor(white: 0.025, alpha: 1).cgColor] as CFArray
            if let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors, locations: [0, 0.4, 1]) {
                cg.drawRadialGradient(glow,
                                      startCenter: CGPoint(x: size.width / 2, y: size.height * 0.55),
                                      startRadius: 0,
                                      endCenter: CGPoint(x: size.width / 2, y: size.height * 0.55),
                                      endRadius: size.width * 0.30,
                                      options: [.drawsAfterEndLocation])
            }

            // Barres de neon, obliques, d'epaisseur et d'intensite variables
            cg.setLineCap(.round)
            let bars: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] = [
                (0.06, 0.10, 0.20, 0.62, 5),
                (0.80, 0.06, 0.94, 0.48, 6),
                (0.16, 0.70, 0.30, 0.24, 4),
                (0.66, 0.72, 0.78, 0.30, 5),
                (0.40, 0.04, 0.46, 0.20, 3),
            ]
            for (x1, y1, x2, y2, width) in bars {
                let path = CGMutablePath()
                path.move(to: CGPoint(x: size.width * x1, y: size.height * y1))
                path.addLine(to: CGPoint(x: size.width * x2, y: size.height * y2))
                // Diffusion large, puis coeur lumineux : c'est ce qui fait le neon.
                cg.setShadow(offset: .zero, blur: 18, color: accent.withAlphaComponent(0.75).cgColor)
                cg.setStrokeColor(accent.withAlphaComponent(0.85).cgColor)
                cg.setLineWidth(width)
                cg.addPath(path); cg.strokePath()
                cg.setShadow(offset: .zero, blur: 0, color: nil)
                cg.setStrokeColor(UIColor(white: 1, alpha: 0.85).cgColor)
                cg.setLineWidth(width * 0.34)
                cg.addPath(path); cg.strokePath()
            }

            // Vignettage : on resserre le regard sur la voiture
            let vignette = [UIColor.clear.cgColor, UIColor(white: 0, alpha: 0.92).cgColor] as CFArray
            if let shade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: vignette, locations: [0.22, 1]) {
                cg.drawRadialGradient(shade,
                                      startCenter: CGPoint(x: size.width / 2, y: size.height / 2),
                                      startRadius: 0,
                                      endCenter: CGPoint(x: size.width / 2, y: size.height / 2),
                                      endRadius: size.width * 0.58,
                                      options: [.drawsAfterEndLocation])
            }
        }
    }

    /// Environnement de reflexion : un studio neutre. La peinture doit renvoyer
    /// du gris et du blanc, pas du violet — sinon toutes les voitures se ressemblent.
    private static func environmentImage() -> UIImage {
        let size = CGSize(width: 8, height: 256)
        return UIGraphicsImageRenderer(size: size).image { context in
            let colors = [UIColor(white: 0.78, alpha: 1).cgColor,
                          UIColor(white: 0.26, alpha: 1).cgColor,
                          UIColor(white: 0.05, alpha: 1).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                            colors: colors, locations: [0, 0.5, 1]) else { return }
            context.cgContext.drawLinearGradient(gradient, start: .zero,
                                                 end: CGPoint(x: 0, y: size.height), options: [])
        }
    }
}

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
