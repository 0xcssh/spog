import Testing
import UIKit
@testable import Spog

/// Le sens de la photo, de la capture à la carte.
///
/// Faute silencieuse par excellence : l'image s'affiche droite partout où UIKit lit son
/// étiquette d'orientation, et couchée partout où CoreImage ou Vision lisent les pixels.
/// Une Mercedes prise en paysage est ainsi arrivée debout sur sa carte, le ciel à gauche.
struct PhotoOrientationTests {

    // MARK: Image d'essai

    private static let rawWidth = 40, rawHeight = 20

    /// Image brute 40 × 20, bleue, avec un carré rouge de 10 px **en haut à gauche** des
    /// pixels tels que le capteur les écrit.
    private static func sensorImage() -> CGImage {
        let context = CGContext(data: nil, width: rawWidth, height: rawHeight,
                                bitsPerComponent: 8, bytesPerRow: rawWidth * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: rawWidth, height: rawHeight))
        // CoreGraphics compte depuis le bas : le haut de l'image est à y = hauteur - 10.
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: rawHeight - 10, width: 10, height: 10))
        return context.makeImage()!
    }

    /// Le pixel (x, y) d'une image, y compté depuis le haut : vrai s'il est rouge.
    private static func isRed(_ image: CGImage, x: Int, y: Int) -> Bool {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: width * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        // La mémoire d'un contexte bitmap commence par la ligne du haut.
        let offset = (y * width + x) * 4
        return bytes[offset] > 200 && bytes[offset + 2] < 60
    }

    // MARK: Redressement

    /// Une orientation, la taille droite attendue, et où le carré rouge doit se retrouver.
    struct Case: Sendable, CustomTestStringConvertible {
        let orientation: UIImage.Orientation
        let width: Int, height: Int
        let redX: Int, redY: Int
        var testDescription: String { "orientation \(orientation.rawValue)" }
    }

    @Test("Les pixels sont tournés selon l'étiquette, et l'étiquette devient « droite »",
          arguments: [
            Case(orientation: .up, width: 40, height: 20, redX: 5, redY: 5),
            // Tenu en portrait : le capteur écrit couché, l'étiquette dit « tourner à droite ».
            Case(orientation: .right, width: 20, height: 40, redX: 15, redY: 5),
            Case(orientation: .left, width: 20, height: 40, redX: 5, redY: 35),
            // Paysage dans l'autre sens, ou téléphone à l'envers.
            Case(orientation: .down, width: 40, height: 20, redX: 35, redY: 15),
            Case(orientation: .upMirrored, width: 40, height: 20, redX: 35, redY: 5),
          ])
    func normalizesEveryOrientation(_ sample: Case) throws {
        let tagged = UIImage(cgImage: Self.sensorImage(), scale: 1, orientation: sample.orientation)
        let upright = UprightPhoto.normalize(tagged)

        #expect(upright.imageOrientation == .up)
        let pixels = try #require(upright.cgImage)
        #expect(pixels.width == sample.width)
        #expect(pixels.height == sample.height)
        #expect(Self.isRed(pixels, x: sample.redX, y: sample.redY))
        // Et le coin opposé est resté bleu : l'image a tourné, elle n'a pas bavé.
        #expect(!Self.isRed(pixels, x: pixels.width - 1 - sample.redX,
                            y: pixels.height - 1 - sample.redY))
    }

    @Test("Une image déjà droite et assez petite est rendue telle quelle")
    func uprightImageIsUntouched() {
        let image = UIImage(cgImage: Self.sensorImage())
        #expect(UprightPhoto.normalize(image) === image)
    }

    @Test("Le plus long côté est borné, après rotation")
    func downscalesLongestSide() throws {
        let tagged = UIImage(cgImage: Self.sensorImage(), scale: 1, orientation: .right)
        let upright = UprightPhoto.normalize(tagged, maxDimension: 20)
        let pixels = try #require(upright.cgImage)
        #expect(pixels.width == 10)
        #expect(pixels.height == 20)
    }

    // MARK: Cadrage de la carte

    @Test("Sans sujet connu, la carte est découpée au centre, sans bandes")
    func centeredFillWithoutSubject() {
        let framing = CardArtStylizer.framing(imageSize: CGSize(width: 4000, height: 3000),
                                              subject: nil, aspect: 1)
        #expect(framing.crop == CGRect(x: 500, y: 0, width: 3000, height: 3000))
        #expect(framing.canvas == CGSize(width: 3000, height: 3000))
    }

    @Test("Le cadre suit la voiture, même excentrée, sans sortir de la photo")
    func followsTheSubject() {
        // Photo en portrait, voiture dans le bas de l'image.
        let framing = CardArtStylizer.framing(imageSize: CGSize(width: 3000, height: 4000),
                                              subject: CGRect(x: 0.1, y: 0.6, width: 0.6, height: 0.2),
                                              aspect: 1)
        let box = CGRect(x: 300, y: 2400, width: 1800, height: 800)
        #expect(framing.crop.contains(box))
        #expect(framing.canvas.width == framing.canvas.height)
        #expect(framing.crop.minX >= 0 && framing.crop.maxX <= 3000)
        #expect(framing.crop.minY >= 0 && framing.crop.maxY <= 4000)
        // Centré verticalement sur la voiture, pas au milieu de la photo.
        #expect(abs(framing.crop.midY - box.midY) < 2)
    }

    @Test("Une voiture prise en paysage reste entière : on complète en hauteur plutôt que de la couper")
    func wideCarGetsBands() {
        let framing = CardArtStylizer.framing(imageSize: CGSize(width: 4000, height: 3000),
                                              subject: CGRect(x: 0.15, y: 0.3, width: 0.7, height: 0.4),
                                              aspect: 1)
        let box = CGRect(x: 600, y: 900, width: 2800, height: 1200)
        #expect(framing.crop.minX <= box.minX && framing.crop.maxX >= box.maxX)
        #expect(framing.crop.height == 3000)
        #expect(framing.canvas.height > framing.crop.height)
        #expect(framing.canvas.height <= 3000 * 1.2)
    }

    // MARK: Mesure du sujet

    @Test("Le plus grand sujet l'emporte, avec sa boîte et son remplissage")
    func measuresLargestInstance() throws {
        // Grille 10 × 10 : un petit sujet « 1 » de 2 pixels, un grand « 2 » de 3 × 4.
        var grid = [UInt8](repeating: 0, count: 100)
        grid[0] = 1; grid[1] = 1
        for y in 5..<9 { for x in 4..<7 { grid[y * 10 + x] = 2 } }

        let measure = try #require(SubjectLifter.measureLargest(width: 10, height: 10) { x, y in
            grid[y * 10 + x]
        })
        #expect(measure.label == 2)
        #expect(abs(measure.bounds.minX - 0.4) < 0.0001)
        #expect(abs(measure.bounds.minY - 0.5) < 0.0001)
        #expect(abs(measure.bounds.width - 0.3) < 0.0001)
        #expect(abs(measure.bounds.height - 0.4) < 0.0001)
        #expect(measure.fill == 1)
    }
}
