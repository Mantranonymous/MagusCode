import MagusCore
import CoreGraphics
import Foundation

/// Squelette pour le fallback VLM (Qwen2.5-VL via MLX Swift).
/// **Non activé en Phase 1.** Implémentation réelle en Phase 8.
///
/// Quand activé, ce moteur sera utilisé en fallback sur les régions où Vision
/// retourne une confidence trop basse (chiffres flous, petits caractères).
public struct VLMFallback: OCREngine {

    public let identifier = "vlm"

    public init() {}

    public func recognize(image: CGImage, options: OCROptions) async throws -> [OCRResult] {
        throw OCREngineError.notImplemented
    }
}
