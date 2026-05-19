import AppKit
import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import MagusCommon
import ScreenCaptureKit
import os

public enum ScreenCaptureError: Error, Sendable {
    case shareableContentUnavailable(underlying: String)
    case windowNotFound(windowID: CGWindowID)
    case streamStartFailed(underlying: String)
}

/// Capture la fenêtre Dofus via ScreenCaptureKit.
/// Émet un AsyncStream<CaptureFrame> à la fréquence configurée.
public actor ScreenCapture {

    private let logger = MagusLogger.perception
    private var stream: SCStream?
    private var output: StreamOutput?
    private var currentRate: CaptureRate = .idle
    private var currentWindowID: CGWindowID?

    public init() {}

    /// Démarre la capture continue d'une fenêtre. Retourne un AsyncStream<CaptureFrame>.
    public func start(windowID: CGWindowID, rate: CaptureRate = .active) async throws -> AsyncStream<CaptureFrame> {
        await stop()

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        } catch {
            throw ScreenCaptureError.shareableContentUnavailable(underlying: error.localizedDescription)
        }

        guard let target = content.windows.first(where: { $0.windowID == windowID }) else {
            throw ScreenCaptureError.windowNotFound(windowID: windowID)
        }

        let filter = SCContentFilter(desktopIndependentWindow: target)
        let config = SCStreamConfiguration()
        config.width = max(1, Int(target.frame.width * 2))   // Retina-aware
        config.height = max(1, Int(target.frame.height * 2))
        config.minimumFrameInterval = rate.frameInterval
        config.queueDepth = 5
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA

        let (asyncStream, continuation) = AsyncStream<CaptureFrame>.makeStream(bufferingPolicy: .bufferingNewest(2))
        let output = StreamOutput(continuation: continuation)
        let scStream = SCStream(filter: filter, configuration: config, delegate: output)

        do {
            try scStream.addStreamOutput(output, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
            try await scStream.startCapture()
        } catch {
            continuation.finish()
            throw ScreenCaptureError.streamStartFailed(underlying: error.localizedDescription)
        }

        continuation.onTermination = { [weak self] _ in
            Task { await self?.stop() }
        }

        self.stream = scStream
        self.output = output
        self.currentRate = rate
        self.currentWindowID = windowID

        logger.info("ScreenCapture started windowID=\(windowID, privacy: .public) rate=\(rate.fps)fps")
        return asyncStream
    }

    /// Change la fréquence sans recréer le stream.
    public func setRate(_ rate: CaptureRate) async {
        guard let stream = stream, currentRate != rate else { return }
        let newConfig = SCStreamConfiguration()
        newConfig.minimumFrameInterval = rate.frameInterval
        newConfig.showsCursor = false
        newConfig.pixelFormat = kCVPixelFormatType_32BGRA
        try? await stream.updateConfiguration(newConfig)
        currentRate = rate
        logger.debug("ScreenCapture rate updated to \(rate.fps)fps")
    }

    public func stop() async {
        if let stream = stream {
            try? await stream.stopCapture()
        }
        output?.finish()
        stream = nil
        output = nil
        currentWindowID = nil
    }
}

/// Réceptionne les samples SCStream, convertit en CGImage et publie via AsyncStream.
final class StreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {

    private let continuation: AsyncStream<CaptureFrame>.Continuation
    private let ciContext: CIContext
    private let logger = MagusLogger.perception

    init(continuation: AsyncStream<CaptureFrame>.Continuation) {
        self.continuation = continuation
        self.ciContext = CIContext()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              sampleBuffer.isValid,
              let imageBuffer = sampleBuffer.imageBuffer else { return }

        // Vérifie que la frame est complète (sinon on l'ignore)
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]]
        if let rawStatus = attachments?.first?[.status] as? Int,
           let frameStatus = SCFrameStatus(rawValue: rawStatus),
           frameStatus != .complete {
            return
        }

        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

        let bounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let frame = CaptureFrame(image: cgImage, windowBounds: bounds)
        continuation.yield(frame)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        logger.error("SCStream stopped with error: \(error.localizedDescription, privacy: .public)")
        continuation.finish()
    }

    func finish() {
        continuation.finish()
    }
}
