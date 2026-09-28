#!/usr/bin/env swift
// Aperçu de la mise en scène d'une photo scannée, hors de l'app.
//
// POURQUOI CET OUTIL EXISTE
// Vision ne détoure pas dans le simulateur iOS : `VNGenerateForegroundInstanceMaskRequest`
// n'y trouve pas de modèle d'inférence. Une carte scannée y tombe donc toujours sur le
// repli — photo entière teintée — et l'on juge le repli en croyant juger la mise en scène.
// Sur macOS, Vision fonctionne. Cet outil fait tourner la même chaîne sur une vraie photo
// et écrit le résultat, sans iPhone et sans le moindre appel réseau.
//
// ATTENTION : la chaîne est **recopiée** depuis Spog/Cards/CardArtStylizer.swift, parce
// que celui-ci importe UIKit et ne compile pas sur macOS. Toute retouche de l'un doit être
// reportée sur l'autre, sans quoi l'aperçu cesse de dire la vérité.
//
//   swift tools/preview-stylizer.swift test-photos/peugeot-3008.webp
//   swift tools/preview-stylizer.swift <photo> --glow F5B942 --out /tmp/apercu.png

import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

// MARK: Arguments

let arguments = Array(CommandLine.arguments.dropFirst())
guard let inputPath = arguments.first, !inputPath.hasPrefix("--") else {
    print("""
    Usage : swift tools/preview-stylizer.swift <photo> [--glow RRGGBB] [--out chemin.png]

      --glow   couleur du palier de rareté, en hexadécimal. Défaut A75CF9 (« rare »).
               Quelques paliers : 7A7590 commune · 4C7DF0 régulière · 22D3EE remarquable
               A75CF9 rare · F43F9D exotique · F5B942 légendaire
      --out    fichier de sortie. Défaut : <photo>-carte.png
    """)
    exit(1)
}

func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: "--" + name),
          index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

let glowHex = UInt32(option("glow") ?? "A75CF9", radix: 16) ?? 0xA75CF9
let outputPath = option("out")
    ?? (inputPath as NSString).deletingPathExtension + "-carte.png"

let glow = NSColor(red: CGFloat((glowHex >> 16) & 0xFF) / 255,
                   green: CGFloat((glowHex >> 8) & 0xFF) / 255,
                   blue: CGFloat(glowHex & 0xFF) / 255,
                   alpha: 1)

// MARK: Lecture

guard let data = FileManager.default.contents(atPath: inputPath),
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    print("Photo illisible : \(inputPath)")
    exit(1)
}

let context = CIContext(options: [.useSoftwareRenderer: false])
let image = CIImage(cgImage: cgImage)
let frame = image.extent

// MARK: Détourage — identique à SubjectLifter

func isolateSubject(_ cgImage: CGImage) -> CIImage? {
    let request = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
    do { try handler.perform([request]) } catch { return nil }
    guard let result = request.results?.first, !result.allInstances.isEmpty,
          let masked = try? result.generateMaskedImage(ofInstances: result.allInstances,
                                                       from: handler,
                                                       croppedToInstancesExtent: true)
    else { return nil }
    return CIImage(cvPixelBuffer: masked)
}

// MARK: Étapes — identiques à CardArtStylizer

func punch(_ image: CIImage, bloom useBloom: Bool = true) -> CIImage {
    let colors = CIFilter.colorControls()
    colors.inputImage = image
    colors.saturation = 1.38
    colors.contrast = 1.22
    colors.brightness = 0.02

    let vibrance = CIFilter.vibrance()
    vibrance.inputImage = colors.outputImage
    vibrance.amount = 0.5

    guard useBloom else { return vibrance.outputImage ?? image }

    let bloom = CIFilter.bloom()
    bloom.inputImage = vibrance.outputImage
    bloom.radius = 5
    bloom.intensity = 0.14
    return bloom.outputImage ?? image
}

func rgba(_ color: NSColor) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    color.usingColorSpace(.sRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
    return (r, g, b, a)
}

func rimLight(_ subject: CIImage, color: NSColor, in frame: CGRect) -> CIImage {
    let silhouette = CIFilter.colorMatrix()
    silhouette.inputImage = subject
    let c = rgba(color)
    // Un liseré, pas un néon de plus : à pleine puissance il cerne la voiture d'un
    // trait lumineux qui la détache du fond au lieu de l'y poser.
    let force: CGFloat = 0.45
    // **Les composantes suivent l'alpha.** CoreImage travaille en alpha prémultiplié :
    // une couleur laissée à pleine intensité sous un alpha de 0,45 vaut, une fois
    // démultipliée, plus de 1 — donc du blanc après écrêtage. C'était l'origine du
    // halo blafard autour de la voiture, que j'ai longtemps pris pour un défaut du
    // découpage de Vision.
    silhouette.rVector = CIVector(x: 0, y: 0, z: 0, w: c.r * force)
    silhouette.gVector = CIVector(x: 0, y: 0, z: 0, w: c.g * force)
    silhouette.bVector = CIVector(x: 0, y: 0, z: 0, w: c.b * force)
    silhouette.aVector = CIVector(x: 0, y: 0, z: 0, w: force)

    // Flou serre : un liseré, pas une aura. A 0.045 le halo débordait si loin qu'il
    // virait au blanc et noyait la voiture dans une brume.
    let blur = CIFilter.gaussianBlur()
    blur.inputImage = silhouette.outputImage
    blur.radius = Float(min(frame.width, frame.height) * 0.012)
    guard let blurred = blur.outputImage else { return CIImage.empty() }

    let box = subject.extent
    let scale: CGFloat = 1.02
    let grown = CGAffineTransform(translationX: -box.midX, y: -box.midY)
        .concatenating(CGAffineTransform(scaleX: scale, y: scale))
        .concatenating(CGAffineTransform(translationX: box.midX, y: box.midY))
    return blurred.transformed(by: grown).cropped(to: frame)
}

func groundShadow(_ subject: CIImage, in frame: CGRect) -> CIImage {
    let dark = CIFilter.colorMatrix()
    dark.inputImage = subject
    dark.rVector = CIVector(x: 0, y: 0, z: 0, w: 0)
    dark.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
    dark.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
    dark.aVector = CIVector(x: 0, y: 0, z: 0, w: 0.55)

    let blur = CIFilter.gaussianBlur()
    blur.inputImage = dark.outputImage
    blur.radius = Float(min(frame.width, frame.height) * 0.03)
    guard let blurred = blur.outputImage else { return CIImage.empty() }

    // Écrasée **sur la base du sujet**, pas décalée d'une fraction de l'image : c'est
    // ce décalage aveugle qui faisait flotter la voiture au-dessus de son ombre.
    let box = subject.extent
    let squash = CGAffineTransform(translationX: 0, y: -box.minY)
        .concatenating(CGAffineTransform(scaleX: 1.04, y: 0.13))
        .concatenating(CGAffineTransform(translationX: 0, y: box.minY + frame.height * 0.012))
    return blurred.transformed(by: squash).cropped(to: frame)
}

extension CIColor {
    func withAlpha(_ alpha: CGFloat) -> CIColor {
        CIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

func backdrop(color: NSColor, in frame: CGRect) -> CIImage {
    let gradient = CIFilter.radialGradient()
    gradient.center = CGPoint(x: frame.midX, y: frame.midY + frame.height * 0.08)
    gradient.radius0 = Float(frame.width * 0.05)
    gradient.radius1 = Float(frame.width * 0.62)
    // Les deux bornes sont **opaques**. Une couleur à alpha partiel laisse le centre
    // du dégradé translucide ; la scène n'ayant rien derrière elle, ce trou se lit en
    // blanc et forme un halo autour de la voiture, qu'on prend pour un défaut de
    // découpage. La teinte du palier se mélange donc au noir plutôt que de s'y fondre
    // par transparence.
    let nuit = (r: CGFloat(0.02), g: CGFloat(0.015), b: CGFloat(0.035))
    let c = rgba(color)
    let melange: CGFloat = 0.16
    gradient.color0 = CIColor(red: nuit.r + (c.r - nuit.r) * melange,
                              green: nuit.g + (c.g - nuit.g) * melange,
                              blue: nuit.b + (c.b - nuit.b) * melange,
                              alpha: 1)
    gradient.color1 = CIColor(red: nuit.r, green: nuit.g, blue: nuit.b, alpha: 1)
    let base = (gradient.outputImage ?? CIImage(color: .black)).cropped(to: frame)

    let strips: [(y: CGFloat, height: CGFloat, color: CIColor, alpha: CGFloat)] = [
        (0.80, 0.009, CIColor(red: 0.13, green: 0.83, blue: 0.93), 1.0),
        (0.70, 0.006, CIColor(color: color) ?? .gray, 0.85),
        (0.60, 0.007, CIColor(red: 0.96, green: 0.25, blue: 0.62), 0.75),
    ]

    return strips.reduce(base) { scene, strip in
        let bar = CIImage(color: strip.color.withAlpha(strip.alpha))
            .cropped(to: CGRect(x: frame.minX - frame.width * 0.1,
                                y: frame.minY + frame.height * strip.y,
                                width: frame.width * 1.2,
                                height: max(1, frame.height * strip.height)))
        let glowFilter = CIFilter.gaussianBlur()
        glowFilter.inputImage = bar
        glowFilter.radius = Float(frame.height * 0.008)
        guard let blurred = glowFilter.outputImage else { return scene }
        let add = CIFilter.additionCompositing()
        add.inputImage = blurred.cropped(to: frame)
        add.backgroundImage = scene
        return add.outputImage?.cropped(to: frame) ?? scene
    }
}

func grade(_ image: CIImage, color: NSColor, in frame: CGRect) -> CIImage {
    let tint = CIImage(color: CIColor(color: color.withAlphaComponent(0.22)) ?? .gray)
        .cropped(to: frame)
    let blend = CIFilter.softLightBlendMode()
    blend.inputImage = tint
    blend.backgroundImage = image.cropped(to: frame)
    return blend.outputImage ?? image
}

func vignette(_ image: CIImage, in frame: CGRect) -> CIImage {
    let filter = CIFilter.vignetteEffect()
    filter.inputImage = image
    filter.center = CGPoint(x: frame.midX, y: frame.midY)
    filter.radius = Float(min(frame.width, frame.height) * 0.52)
    filter.intensity = 1.35
    filter.falloff = 0.72
    return filter.outputImage ?? image
}

// MARK: Composition

/// Place le sujet dans la scène : mis à l'échelle, centré, posé sur le sol.
///
/// Sans ça, la voiture reste là où elle était sur la photo — souvent collée aux bords,
/// parfois coupée. Les illustrations du catalogue montrent toutes une voiture **centrée,
/// avec de l'air autour et du sol dessous** ; c'est cette composition, plus que les
/// filtres, qui fait qu'une carte a l'air fabriquée plutôt que photographiée.
func stage(_ subject: CIImage, in frame: CGRect) -> CIImage {
    let box = subject.extent
    guard box.width > 0, box.height > 0 else { return subject }

    // La voiture occupe au plus 82 % de la largeur et 58 % de la hauteur : le reste
    // est de l'air au-dessus et du sol en dessous, comme sur les rendus.
    let scale = min(frame.width * 0.82 / box.width, frame.height * 0.58 / box.height)
    let width = box.width * scale, height = box.height * scale

    // Posée au tiers inférieur, pas au milieu : il faut de la place pour le reflet.
    let x = frame.midX - width / 2
    let y = frame.minY + frame.height * 0.30

    return subject
        .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        .transformed(by: CGAffineTransform(translationX: x - box.minX * scale,
                                           y: y - box.minY * scale))
}

/// Le reflet de la voiture sur le sol : retourné, atténué, flou vers le bas.
/// C'est le détail qui transforme un découpage en scène — sans lui, la voiture
/// flotte, et l'oeil le remarque avant même de savoir pourquoi.
func floorReflection(_ staged: CIImage, in frame: CGRect) -> CIImage {
    let box = staged.extent
    let flip = CGAffineTransform(scaleX: 1, y: -1)
        .concatenating(CGAffineTransform(translationX: 0, y: box.minY * 2 + box.height))
    let mirrored = staged.transformed(by: flip)
        .transformed(by: CGAffineTransform(scaleX: 1, y: 0.55)
            .concatenating(CGAffineTransform(translationX: 0, y: box.minY * 0.45)))

    let fade = CIFilter.colorMatrix()
    fade.inputImage = mirrored
    fade.aVector = CIVector(x: 0, y: 0, z: 0, w: 0.22)

    let soften = CIFilter.gaussianBlur()
    soften.inputImage = fade.outputImage
    soften.radius = Float(frame.height * 0.012)
    return (soften.outputImage ?? CIImage.empty()).cropped(to: frame)
}

/// Rogne le bord du sujet de quelques pixels.
///
/// Le masque de Vision suit le contour **au pixel près, celui-ci compris** : sur une
/// photo de rue, ce dernier pixel appartient encore au ciel ou au bitume clair. Composé
/// sur un fond noir, il forme un liseré blanc qui trahit le découpage et donne à la
/// voiture l'air d'un autocollant. Un érodé de quelques pixels le supprime.
func trimEdge(_ subject: CIImage, in frame: CGRect) -> CIImage {
    // On érode **la transparence seule**. Appliquer l'érosion à l'image entière
    // rogne aussi les couleurs : chaque reflet clair de la carrosserie est remplacé
    // par son voisin sombre, et la voiture se couvre de trous. C'est le contour
    // qu'on veut resserrer, pas la peinture.
    let toMask = CIFilter.colorMatrix()
    toMask.inputImage = subject
    toMask.rVector = CIVector(x: 0, y: 0, z: 0, w: 1)
    toMask.gVector = CIVector(x: 0, y: 0, z: 0, w: 1)
    toMask.bVector = CIVector(x: 0, y: 0, z: 0, w: 1)
    toMask.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
    toMask.biasVector = CIVector(x: 0, y: 0, z: 0, w: 1)

    let erode = CIFilter.morphologyMinimum()
    erode.inputImage = toMask.outputImage
    erode.radius = Float(max(1.5, min(frame.width, frame.height) * 0.005))
    guard let tightened = erode.outputImage else { return subject }

    let apply = CIFilter.blendWithMask()
    apply.inputImage = subject
    apply.backgroundImage = CIImage(color: .clear).cropped(to: subject.extent)
    apply.maskImage = tightened
    return apply.outputImage ?? subject
}

let subject = isolateSubject(cgImage).map { trimEdge($0, in: frame) }
let composed: CIImage
if let subject {
    print("Détourage réussi — mise en scène complète, comme sur un iPhone.")
    let staged = stage(subject, in: frame)
    // `bloom: false` — un bloom appliqué à une image détourée déborde dans le vide et
    // cerne la voiture d'une brume blanche qu'on prend pour un défaut de découpage.
    // Sur le sujet isolé, le liseré coloré fait déjà le travail du halo.
    composed = punch(staged, bloom: false)
        .composited(over: rimLight(staged, color: glow, in: frame))
        .composited(over: floorReflection(staged, in: frame))
        .composited(over: groundShadow(staged, in: frame))
        .composited(over: backdrop(color: glow, in: frame))
        .cropped(to: frame)
} else {
    print("Détourage impossible — repli : photo entière étalonnée et vignettée.")
    composed = vignette(grade(punch(image), color: glow, in: frame), in: frame)
        .cropped(to: frame)
}

guard let rendered = context.createCGImage(composed, from: frame) else {
    print("Rendu impossible.")
    exit(1)
}

let bitmap = NSBitmapImageRep(cgImage: rendered)
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    print("Encodage PNG impossible.")
    exit(1)
}
try png.write(to: URL(fileURLWithPath: outputPath))
print("Écrit : \(outputPath)")
