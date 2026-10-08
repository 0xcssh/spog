#!/usr/bin/env swift
// Aperçu du visuel de carte tiré d'une photo scannée, hors de l'app.
//
// POURQUOI CET OUTIL EXISTE
// Vision ne détoure pas dans le simulateur iOS : `VNGenerateForegroundInstanceMaskRequest`
// n'y trouve pas de modèle d'inférence. Une carte scannée y est donc toujours cadrée au
// centre, sans décor adouci, et l'on juge ce repli en croyant juger la chaîne complète.
// Sur macOS, Vision fonctionne. Cet outil fait tourner la même chaîne sur une vraie photo
// et écrit le résultat, sans iPhone et sans le moindre appel réseau.
//
// ATTENTION : la chaîne est **recopiée** depuis Spog/Cards/CardArtStylizer.swift (et
// SubjectLifter, UprightPhoto), parce que ceux-ci importent UIKit et ne compilent pas sur
// macOS. Toute retouche de l'un doit être reportée sur l'autre, sans quoi l'aperçu cesse
// de dire la vérité.
//
//   swift tools/preview-stylizer.swift test-photos/peugeot-3008.webp
//   swift tools/preview-stylizer.swift <photo> --out /tmp/apercu.png

import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

// MARK: Arguments

let arguments = Array(CommandLine.arguments.dropFirst())
guard let inputPath = arguments.first, !inputPath.hasPrefix("--") else {
    print("""
    Usage : swift tools/preview-stylizer.swift <photo> [--out chemin.png]

      --out    fichier de sortie. Défaut : <photo>-carte.png
    """)
    exit(1)
}

func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: "--" + name),
          index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

let outputPath = option("out")
    ?? (inputPath as NSString).deletingPathExtension + "-carte.png"

let cardAspect: CGFloat = 1.02
let outputMaxDimension: CGFloat = 1600

// MARK: Lecture — redressée comme UprightPhoto

// La vignette « avec transformation » applique l'orientation EXIF aux pixels et borne le
// plus long côté : exactement ce que fait UprightPhoto après la capture.
guard let data = FileManager.default.contents(atPath: inputPath),
      let source = CGImageSourceCreateWithData(data as CFData, nil),
      let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: 2560,
      ] as CFDictionary) else {
    print("Photo illisible : \(inputPath)")
    exit(1)
}

let context = CIContext(options: [.useSoftwareRenderer: false])
let image = CIImage(cgImage: cgImage)
let size = image.extent.size

// MARK: Détourage — identique à SubjectLifter

struct Lifted {
    let bounds: CGRect   // normalisée, origine en haut à gauche
    let fill: Double
    let mask: CIImage
}

func measureLargest(_ buffer: CVPixelBuffer) -> (label: Int, bounds: CGRect, fill: Double)? {
    guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent8 else { return nil }
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
    let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
    let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
    let pixels = base.assumingMemoryBound(to: UInt8.self)

    var count = [Int](repeating: 0, count: 256)
    var minX = [Int](repeating: .max, count: 256), minY = [Int](repeating: .max, count: 256)
    var maxX = [Int](repeating: -1, count: 256), maxY = [Int](repeating: -1, count: 256)
    for y in 0..<height {
        for x in 0..<width {
            let l = Int(pixels[y * rowBytes + x])
            guard l != 0 else { continue }
            count[l] += 1
            minX[l] = min(minX[l], x); maxX[l] = max(maxX[l], x)
            minY[l] = min(minY[l], y); maxY[l] = max(maxY[l], y)
        }
    }
    guard let best = (1..<256).max(by: { count[$0] < count[$1] }), count[best] > 0 else { return nil }
    let bw = maxX[best] - minX[best] + 1, bh = maxY[best] - minY[best] + 1
    return (best,
            CGRect(x: CGFloat(minX[best]) / CGFloat(width), y: CGFloat(minY[best]) / CGFloat(height),
                   width: CGFloat(bw) / CGFloat(width), height: CGFloat(bh) / CGFloat(height)),
            Double(count[best]) / Double(bw * bh))
}

func lift(_ cgImage: CGImage) -> Lifted? {
    let request = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up)
    do { try handler.perform([request]) } catch { return nil }
    guard let result = request.results?.first, !result.allInstances.isEmpty,
          let largest = measureLargest(result.instanceMask),
          let mask = try? result.generateScaledMaskForImage(forInstances: IndexSet(integer: largest.label),
                                                            from: handler)
    else { return nil }
    return Lifted(bounds: largest.bounds, fill: largest.fill, mask: CIImage(cvPixelBuffer: mask))
}

// MARK: Cadrage — identique à CardArtStylizer.framing

struct Framing { let crop: CGRect; let canvas: CGSize }

func framing(imageSize: CGSize, subject: CGRect?, aspect: CGFloat = cardAspect) -> Framing {
    let width = imageSize.width, height = imageSize.height
    guard let subject, subject.width > 0, subject.height > 0 else {
        let w = min(width, height * aspect).rounded(.down)
        let h = min(height, (w / aspect).rounded(.down))
        return Framing(crop: CGRect(x: ((width - w) / 2).rounded(.down), y: ((height - h) / 2).rounded(.down),
                                    width: w, height: h),
                       canvas: CGSize(width: w, height: h))
    }
    let box = CGRect(x: subject.minX * width, y: subject.minY * height,
                     width: subject.width * width, height: subject.height * height)
    var w = max(box.width * 1.24, box.height * 1.5 * aspect)
    w = max(w, min(width, height * aspect) * 0.5)
    w = min(w, width)
    var h = w / aspect
    if h > height * 1.2 { h = height * 1.2; w = h * aspect }
    w = w.rounded(.down); h = h.rounded(.down)
    let visible = min(h, height)
    let x = min(max(box.midX - w / 2, 0), width - w).rounded(.down)
    let y = min(max(box.midY - visible / 2, 0), height - visible).rounded(.down)
    return Framing(crop: CGRect(x: x, y: y, width: w, height: visible), canvas: CGSize(width: w, height: h))
}

func compose(_ image: CIImage, framing: Framing, imageHeight: CGFloat) -> CIImage {
    let crop = CGRect(x: framing.crop.minX, y: imageHeight - framing.crop.maxY,
                      width: framing.crop.width, height: framing.crop.height)
    let canvas = CGRect(origin: .zero, size: framing.canvas)
    let band = ((canvas.height - crop.height) / 2).rounded(.down)
    let strip = image.cropped(to: crop)
        .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY + band))
    guard band >= 1 else { return strip.cropped(to: canvas) }

    let cover = canvas.height / crop.height
    let backdrop = strip
        .transformed(by: CGAffineTransform(translationX: 0, y: -band))
        .transformed(by: CGAffineTransform(scaleX: cover, y: cover))
        .transformed(by: CGAffineTransform(translationX: (canvas.width - crop.width * cover) / 2, y: 0))
    let blur = CIFilter.gaussianBlur()
    blur.inputImage = backdrop.clampedToExtent()
    blur.radius = Float(canvas.height * 0.04)
    let dim = CIFilter.exposureAdjust()
    dim.inputImage = blur.outputImage
    dim.ev = -1.3
    let background = (dim.outputImage ?? backdrop).cropped(to: canvas)

    let feather = max(2, crop.height * 0.04)
    let bottom = CIFilter.linearGradient()
    bottom.point0 = CGPoint(x: 0, y: band)
    bottom.point1 = CGPoint(x: 0, y: band + feather)
    bottom.color0 = CIColor(red: 0, green: 0, blue: 0)
    bottom.color1 = CIColor(red: 1, green: 1, blue: 1)
    let top = CIFilter.linearGradient()
    top.point0 = CGPoint(x: 0, y: band + crop.height)
    top.point1 = CGPoint(x: 0, y: band + crop.height - feather)
    top.color0 = CIColor(red: 0, green: 0, blue: 0)
    top.color1 = CIColor(red: 1, green: 1, blue: 1)
    let both = CIFilter.multiplyCompositing()
    both.inputImage = top.outputImage
    both.backgroundImage = bottom.outputImage

    let blend = CIFilter.blendWithMask()
    blend.inputImage = strip
    blend.backgroundImage = background
    blend.maskImage = both.outputImage?.cropped(to: canvas)
    return blend.outputImage?.cropped(to: canvas) ?? strip
}

// MARK: Étapes — identiques à CardArtStylizer

func isClean(_ lifted: Lifted) -> Bool {
    let area = lifted.bounds.width * lifted.bounds.height
    return lifted.fill >= 0.45 && (0.04...0.8).contains(area)
}

func softenBackground(_ image: CIImage, mask: CIImage) -> CIImage {
    let extent = image.extent
    let side = min(extent.width, extent.height)
    var matte = mask
    if mask.extent.width > 0, mask.extent.height > 0, mask.extent.size != extent.size {
        matte = mask.transformed(by: CGAffineTransform(scaleX: extent.width / mask.extent.width,
                                                       y: extent.height / mask.extent.height))
    }
    let soft = CIFilter.gaussianBlur()
    soft.inputImage = matte.clampedToExtent()
    soft.radius = Float(max(1.5, side * 0.002))
    let blur = CIFilter.gaussianBlur()
    blur.inputImage = image.clampedToExtent()
    blur.radius = Float(side * 0.006)
    let dim = CIFilter.exposureAdjust()
    dim.inputImage = blur.outputImage
    dim.ev = -0.45
    let blend = CIFilter.blendWithMask()
    blend.inputImage = image
    blend.backgroundImage = dim.outputImage?.cropped(to: extent)
    blend.maskImage = soft.outputImage?.cropped(to: extent)
    return blend.outputImage?.cropped(to: extent) ?? image
}

func grade(_ image: CIImage) -> CIImage {
    let colors = CIFilter.colorControls()
    colors.inputImage = image
    colors.saturation = 1.04
    colors.contrast = 1.06
    colors.brightness = 0
    return colors.outputImage ?? image
}

func vignette(_ image: CIImage, in frame: CGRect) -> CIImage {
    let filter = CIFilter.vignetteEffect()
    filter.inputImage = image
    filter.center = CGPoint(x: frame.midX, y: frame.midY)
    filter.radius = Float(min(frame.width, frame.height) * 0.5)
    filter.intensity = 0.4
    filter.falloff = 0.65
    return filter.outputImage ?? image
}

// MARK: Composition

let lifted = lift(cgImage)
let cadre = framing(imageSize: size, subject: lifted?.bounds)
var scene = image
if let lifted {
    let clean = isClean(lifted)
    print(String(format: "Sujet trouvé — boîte %.2f × %.2f, remplissage %.2f : %@", lifted.bounds.width,
                 lifted.bounds.height, lifted.fill, clean ? "décor adouci" : "détourage jugé imprécis, photo seule"))
    if clean { scene = softenBackground(image, mask: lifted.mask) }
} else {
    print("Aucun sujet détouré — cadrage au centre, photo seule.")
}

let canvas = CGRect(origin: .zero, size: cadre.canvas)
var card = vignette(compose(grade(scene), framing: cadre, imageHeight: size.height), in: canvas)
    .cropped(to: canvas)
var outputRect = canvas
let longest = max(canvas.width, canvas.height)
if longest > outputMaxDimension {
    let scale = outputMaxDimension / longest
    let resize = CIFilter.lanczosScaleTransform()
    resize.inputImage = card
    resize.scale = Float(scale)
    resize.aspectRatio = 1
    outputRect = CGRect(x: 0, y: 0, width: (canvas.width * scale).rounded(.down),
                        height: (canvas.height * scale).rounded(.down))
    card = (resize.outputImage ?? card).cropped(to: outputRect)
}

guard let rendered = context.createCGImage(card, from: outputRect) else {
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
