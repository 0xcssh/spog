import AVFoundation
import UIKit
import Observation

/// Flux caméra en direct et capture photo.
/// Pas d'import depuis la photothèque : une prise doit venir de la caméra,
/// c'est ce qui donne sa valeur à une carte.
@Observable
final class CameraController: NSObject {

    enum State: Equatable {
        case idle
        case running
        case denied
        /// Aucune caméra sur cet appareil — c'est le cas du simulateur.
        case unavailable
    }

    private(set) var state: State = .idle

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "spog.camera")
    private var captureContinuation: CheckedContinuation<UIImage?, Never>?
    /// Sait comment le téléphone est tenu, d'après la gravité, même quand l'interface
    /// reste verrouillée en portrait. Sans lui, la connexion garde sa rotation par
    /// défaut et une photo prise en paysage sort étiquetée comme un portrait.
    @ObservationIgnored private var rotation: AVCaptureDevice.RotationCoordinator?

    // MARK: Démarrage

    func start() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                await set(.denied); return
            }
        default:
            await set(.denied); return
        }

        guard session.inputs.isEmpty else { resume(); return }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input), session.canAddOutput(output)
        else { await set(.unavailable); return }

        session.beginConfiguration()
        session.sessionPreset = .photo
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()

        // Créé sur le fil principal par prudence : il observe l'orientation de l'appareil.
        await MainActor.run {
            rotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        }

        resume()
    }

    func stop() {
        queue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func resume() {
        queue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
        Task { await set(.running) }
    }

    @MainActor private func set(_ value: State) { state = value }

    // MARK: Capture

    func capture() async -> UIImage? {
        guard state == .running else { return nil }
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off

        // L'angle « horizon de niveau » : celui qui remet le ciel en haut, que le
        // téléphone soit tenu en portrait, en paysage d'un côté ou de l'autre, ou à
        // l'envers. Il est lu au moment du déclenchement, pas au démarrage : le joueur
        // tourne son téléphone pendant qu'il vise.
        let angle = await MainActor.run { rotation?.videoRotationAngleForHorizonLevelCapture }
        if let angle, let connection = output.connection(with: .video),
           connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }

        return await withCheckedContinuation { continuation in
            captureContinuation = continuation
            output.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        let continuation = captureContinuation
        captureContinuation = nil
        guard error == nil, let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            continuation?.resume(returning: nil); return
        }
        // La rotation n'est qu'une étiquette dans le fichier : on l'applique aux pixels
        // ici, une fois pour toutes, avant que CoreImage ou Vision ne l'ignorent.
        continuation?.resume(returning: UprightPhoto.normalize(image))
    }
}
