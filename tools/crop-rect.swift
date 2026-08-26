// Decoupe un rectangle dans une image et ecrit un PNG.
// Usage: xcrun swift crop-rect.swift <source> <x> <y> <w> <h> <sortie>
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let a = CommandLine.arguments
guard a.count == 7, let x = Double(a[2]), let y = Double(a[3]),
      let w = Double(a[4]), let h = Double(a[5]) else { fatalError("arguments") }
guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: a[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(src, 0, nil),
      let cropped = image.cropping(to: CGRect(x: x, y: y, width: w, height: h)),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: a[6]) as CFURL,
                                                 UTType.png.identifier as CFString, 1, nil)
else { fatalError("decoupe impossible") }
CGImageDestinationAddImage(dest, cropped, nil)
CGImageDestinationFinalize(dest)
