// Met un rendu studio au format des illustrations de carte.
//
// Recadrage purement géométrique : on prend la plus large bande possible au bon format,
// centrée horizontalement et légèrement sous le milieu — une voiture se pose toujours
// un peu bas dans le cadre. Aucune détection de contour : les néons du décor sont aussi
// contrastés que la carrosserie, et toute tentative de trouver « la voiture » finissait
// par cadrer le décor.
//
// Le format est tenu à la découpe, jamais à l'étirement : une voiture déformée se voit
// immédiatement, et c'est le genre de défaut qu'on ne remarque plus une fois habitué.
//
// Usage: xcrun swift tools/fit-car-art.swift <source> <sortie> [largeur]
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 3 else { fatalError("usage: <source> <sortie> [largeur]") }
let outWidth = args.count > 3 ? Int(args[3]) ?? 660 : 660
let ratio: CGFloat = 660.0 / 290.0
/// La voiture se pose sous le milieu : on descend la bande d'un peu moins d'un dixième.
let verticalBias: CGFloat = 0.06

guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else { fatalError("lecture impossible") }

let width = CGFloat(image.width), height = CGFloat(image.height)
var band = CGSize(width: width, height: width / ratio)
if band.height > height {                       // image déjà plus large que le format
    band = CGSize(width: height * ratio, height: height)
}
let x = (width - band.width) / 2
let y = min(max((height - band.height) / 2 + height * verticalBias, 0), height - band.height)

guard let cropped = image.cropping(to: CGRect(x: x, y: y, width: band.width, height: band.height))
else { fatalError("découpe impossible") }

let outHeight = Int((CGFloat(outWidth) / ratio).rounded())
guard let context = CGContext(data: nil, width: outWidth, height: outHeight,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
else { fatalError("contexte impossible") }
context.interpolationQuality = .high
context.draw(cropped, in: CGRect(x: 0, y: 0, width: outWidth, height: outHeight))

// JPEG quand le nom de sortie le demande. Six cents illustrations en PNG pèseraient
// cent soixante mégaoctets dans le bundle : une photo se compresse, un aplat non.
let isJPEG = args[2].lowercased().hasSuffix(".jpg") || args[2].lowercased().hasSuffix(".jpeg")
let type = (isJPEG ? UTType.jpeg : UTType.png).identifier as CFString
guard let final = context.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL,
                                                 type, 1, nil)
else { fatalError("écriture impossible") }
CGImageDestinationAddImage(dest, final,
                           isJPEG ? [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary
                                  : nil)
CGImageDestinationFinalize(dest)
print("\(args[2]) — \(outWidth)x\(outHeight)")
