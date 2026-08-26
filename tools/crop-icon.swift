// Decoupe un carre dans une image et produit un PNG opaque a la taille voulue.
// Usage: xcrun swift crop-icon.swift <source> <x> <y> <cote> <taille> <sortie>
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let a = CommandLine.arguments
guard a.count == 7,
      let x = Double(a[2]), let y = Double(a[3]),
      let side = Double(a[4]), let out = Int(a[5])
else { fatalError("arguments invalides") }

guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(src, 0, nil)
else { fatalError("source illisible") }

guard let cropped = image.cropping(to: CGRect(x: x, y: y, width: side, height: side))
else { fatalError("decoupe hors limites") }

// Sans canal alpha : exigence Apple pour l'icone d'app.
guard let ctx = CGContext(data: nil, width: out, height: out,
                          bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
else { fatalError("contexte impossible") }
ctx.interpolationQuality = .high
ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: out, height: out))

guard let result = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[6]) as CFURL,
                                                 UTType.png.identifier as CFString, 1, nil)
else { fatalError("ecriture impossible") }
CGImageDestinationAddImage(dest, result, nil)
CGImageDestinationFinalize(dest)
print("ecrit \(a[6]) — \(out)x\(out)")
