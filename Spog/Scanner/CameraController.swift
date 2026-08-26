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
        continuation?.resume(returning: image)
    }
}
