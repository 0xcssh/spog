import Testing
import UIKit
@testable import Spog

/// Le détourage du sujet, par Vision, sur l'appareil.
///
/// Il décide de tout l'aspect d'une carte scannée : détourage réussi, la voiture est
/// isolée sur une scène néon et ressemble aux illustrations du catalogue ; détourage
/// raté, la photo entière est simplement teintée et la carte fait pauvre.
///
/// Ce test existe surtout pour répondre à une question qu'on ne peut pas trancher en
/// lisant le code : `VNGenerateForegroundInstanceMaskRequest` fonctionne-t-il dans le
/// simulateur ? Il ne le faisait pas sur les versions antérieures d'iOS, ce qui donnait
/// un aperçu trompeur — on jugeait le repli en croyant juger la mise en scène.
struct SubjectLifterTests {

    @Test("Vision détoure un sujet sur cette plateforme")
    func visionLiftsASubject() async {
        // Une illustration embarquée : voiture nette sur fond sombre, le cas le plus
        // favorable qui soit. Si Vision échoue ici, il échoue partout.
        guard let photo = CarArt.image(for: "renault-clio") else {
            Issue.record("illustration de référence absente du bundle")
            return
        }

        let lifted = await SubjectLifter.lift(photo)

        #if targetEnvironment(simulator)
        // Défaut connu du simulateur, pas de l'app : il n'embarque pas le modèle
        // d'inférence de Vision. `withKnownIssue` l'inscrit au compte rendu sans
        // teindre la suite en rouge — et **préviendra le jour où ça se mettra à
        // marcher**, ce qui voudra dire qu'on peut enfin juger un rendu sans iPhone.
        withKnownIssue("Vision ne détoure pas dans le simulateur : les cartes scannées y tombent sur le repli, et la mise en scène ne peut se juger que sur un appareil réel.") {
            #expect(lifted != nil)
        }
        #else
        #expect(lifted != nil, "Vision devrait détourer sur un appareil réel")
        #endif
    }
}
