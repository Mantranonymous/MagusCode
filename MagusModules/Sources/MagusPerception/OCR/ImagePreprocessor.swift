import CoreGraphics
import CoreImage
import Foundation

/// Pré-processing d'image avant OCR — améliore drastiquement la précision Vision
/// sur du texte fin (typique de la table FM Dofus où les chiffres font 12-14px).
///
/// 3 transforms disponibles :
/// 1. **Upscale Lanczos** : redimensionne ×N avec interpolation Lanczos (préserve les bords)
/// 2. **Binarize** : convertit en noir & blanc pur via seuil de luminance
/// 3. **Contrast boost** : augmente le contraste pour mieux séparer texte/fond
public struct ImagePreprocessor: Sendable {

    public struct Settings: Sendable {
        public let upscaleFactor: CGFloat   // 1.0 = pas d'upscale
        public let binarize: Bool
        public let contrastBoost: Bool

        public init(upscaleFactor: CGFloat = 2.0, binarize: Bool = false, contrastBoost: Bool = false) {
            self.upscaleFactor = upscaleFactor
            self.binarize = binarize
            self.contrastBoost = contrastBoost
        }

        public static let none = Settings(upscaleFactor: 1.0, binarize: false, contrastBoost: false)
        public static let standard = Settings(upscaleFactor: 2.0, binarize: false, contrastBoost: false)
        public static let aggressive = Settings(upscaleFactor: 3.0, binarize: true, contrastBoost: true)
    }

    private let context = CIContext(options: [.useSoftwareRenderer: false])
    public let settings: Settings

    public init(settings: Settings = .standard) {
        self.settings = settings
    }

    /// Applique les transforms configurés. Retourne le CGImage transformé.
    /// Si toutes les options sont à neutre, retourne l'original (no-op).
    public func process(_ source: CGImage) -> CGImage {
        if settings.upscaleFactor == 1.0 && !settings.binarize && !settings.contrastBoost {
            return source
        }

        var image = CIImage(cgImage: source)

        // 1. Upscale via Lanczos (préserve les bords nets, idéal pour du texte)
        if settings.upscaleFactor != 1.0 {
            let lanczos = CIFilter(name: "CILanczosScaleTransform")!
            lanczos.setValue(image, forKey: kCIInputImageKey)
            lanczos.setValue(settings.upscaleFactor, forKey: kCIInputScaleKey)
            lanczos.setValue(1.0, forKey: kCIInputAspectRatioKey)
            if let out = lanczos.outputImage {
                image = out
            }
        }

        // 2. Contrast boost (avant binarize si les deux)
        if settings.contrastBoost {
            let controls = CIFilter(name: "CIColorControls")!
            controls.setValue(image, forKey: kCIInputImageKey)
            controls.setValue(1.6, forKey: kCIInputContrastKey)     // boost contraste
            controls.setValue(0.0, forKey: kCIInputSaturationKey)   // désature (N&B)
            controls.setValue(0.0, forKey: kCIInputBrightnessKey)
            if let out = controls.outputImage {
                image = out
            }
        }

        // 3. Binarisation (seuil simple, garde le texte clair sur fond sombre)
        if settings.binarize {
            // Convert grayscale puis seuillage via CIColorThreshold (iOS 14+/macOS 11+)
            let threshold = CIFilter(name: "CIColorThreshold")
            if let threshold = threshold {
                threshold.setValue(image, forKey: kCIInputImageKey)
                threshold.setValue(0.5, forKey: "inputThreshold")
                if let out = threshold.outputImage {
                    image = out
                }
            }
        }

        // Convertit le CIImage final en CGImage
        let extent = image.extent
        if let cg = context.createCGImage(image, from: extent) {
            return cg
        }
        return source  // fallback si rendering rate
    }
}
