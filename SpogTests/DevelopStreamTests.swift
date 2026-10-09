import Foundation
import CoreGraphics
import Testing
@testable import Spog

/// Le flux du passage en studio : ce que le serveur envoie (backend/functions/identify,
/// `relayDevelopStream`) et ce que l'app en lit. Deux fichiers que rien d'autre ne relie :
/// un nom d'événement changé d'un côté laisserait la carte voilée jusqu'au bout, sans erreur.
struct DevelopStreamTests {

    private func events(_ text: String) -> [SSEEvent] {
        var decoder = SSEDecoder()
        // Les lignes vides comprises : ce sont elles qui closent un événement.
        return text.components(separatedBy: "\n").compactMap { decoder.feed($0) }
    }

    @Test("Le flux du serveur se lit événement par événement, commentaires ignorés")
    func decodesServerFrames() throws {
        let jpeg = Data("partiel".utf8).base64EncodedString()
        let text = ": open\n\n" +
            "event: partial\ndata: {\"image\":\"\(jpeg)\",\"index\":0}\n\n" +
            "event: done\r\ndata: {\"image\":\"\(jpeg)\",\"develops_left\":0,\"resets_at\":\"2026-10-10T00:00:00.000Z\"}\r\n\r\n"
        let decoded = events(text)
        try #require(decoded.map(\.name) == ["partial", "done"])

        #expect(DevelopStreamEvent(decoded[0]) == .partial(Data("partiel".utf8), index: 0))
        guard case .done(let payload)? = DevelopStreamEvent(decoded[1]) else {
            Issue.record("événement done illisible")
            return
        }
        #expect(payload.image == jpeg)
        #expect(payload.develops_left == 0)
    }

    @Test("Un événement sans ligne vide finale n'est pas encore complet")
    func waitsForBlankLine() {
        var decoder = SSEDecoder()
        #expect(decoder.feed("event: partial") == nil)
        #expect(decoder.feed("data: {}") == nil)
        #expect(decoder.feed("") == SSEEvent(name: "partial", data: "{}"))
        #expect(decoder.feed("") == nil)
    }

    @Test("Une erreur du serveur garde son code ; un événement inconnu est ignoré")
    func errorsAndUnknownEvents() {
        let failure = SSEEvent(name: "error", data: "{\"code\":\"identification_failed\",\"error\":\"…\"}")
        #expect(DevelopStreamEvent(failure) == .failure(code: "identification_failed"))
        #expect(DevelopStreamEvent(SSEEvent(name: "progress", data: "{}")) == nil)
        #expect(DevelopStreamEvent(SSEEvent(name: "done", data: "pas du json")) == .failure(code: "unreadable_ai_response"))
    }

    @Test("Les images intermédiaires vont du flou au net")
    func partialsSharpen() {
        #expect(DevelopService.partialBlur(0) > DevelopService.partialBlur(1))
        #expect(DevelopService.partialBlur(1) > DevelopService.partialBlur(2))
        #expect(DevelopService.partialBlur(2) > 0)
    }

    @Test("Un rendu carré remplit la carte ; un ancien rendu 3:2 se montre en entier")
    func squareFillsFrame() {
        #expect(DevelopedArt.fillsFrame(CGSize(width: 1024, height: 1024)))
        #expect(!DevelopedArt.fillsFrame(CGSize(width: 1536, height: 1024)))
        #expect(!DevelopedArt.fillsFrame(.zero))
    }
}
