import CoreGraphics
import CoreImage
import Foundation
import MagusCommon
import MagusCore
import MLX
import MLXLMCommon
import MLXVLM

/// Fallback OCR via VLM (Qwen2.5-VL 3B) avec MLX Swift.
///
/// **Activé uniquement si l'option `vlmFallbackEnabled` est cochée dans Préférences**.
/// Le modèle est téléchargé au premier usage (~2 GB) puis caché dans `~/.cache/huggingface/`.
///
/// Stratégie : Vision tente d'abord, et si la confidence moyenne est sous le seuil,
/// VLM prend le relais sur la même image. VLM est beaucoup plus précis sur les
/// chiffres flous mais ~1-2s d'inférence vs <100ms pour Vision.
///
/// **Limitation** : le VLM ne donne pas de boundingBox réelle. On synthétise des
/// bbox line-based (chaque ligne occupe sa portion verticale de l'image).
/// Donc le VLM est OK pour PARSING mais pas pour POSITIONNEMENT précis du click.
public actor VLMFallback: OCREngine {

    /// Singleton : on garde une seule instance du modèle chargé en mémoire,
    /// sinon on rechargerait 2 GB à chaque création d'OCRPipeline.
    public static let shared = VLMFallback()

    public nonisolated let identifier = "vlm-qwen2.5-vl"
    private let logger = MagusLogger.perception

    /// Modèle utilisé. Qwen2.5-VL 3B 4-bit ≈ 2 GB. Bon compromis qualité/RAM.
    private let modelConfig = VLMRegistry.qwen2_5VL3BInstruct4Bit

    private enum LoadState {
        case idle
        case loading
        case loaded(ModelContainer)
        case failed(String)
    }
    private var state: LoadState = .idle

    public init() {}

    /// Charge le modèle si pas déjà chargé. Lance le download au premier appel.
    private func loadModel() async throws -> ModelContainer {
        switch state {
        case .loaded(let container):
            return container
        case .loading:
            // Une autre tâche est en train de loader → attendre puis retry
            try await Task.sleep(nanoseconds: 500_000_000)
            return try await loadModel()
        case .failed(let reason):
            throw OCREngineError.recognitionFailed(underlying: "VLM load failed: \(reason)")
        case .idle:
            state = .loading
            do {
                MLX.GPU.set(cacheLimit: 20 * 1024 * 1024)
                let container = try await VLMModelFactory.shared.loadContainer(
                    configuration: modelConfig
                ) { progress in
                    let pct = Int(progress.fractionCompleted * 100)
                    Task { @MainActor in
                        MagusLogger.perception.info("VLM download: \(pct)%")
                    }
                }
                state = .loaded(container)
                logger.info("VLM model loaded: \(String(describing: self.modelConfig.id), privacy: .public)")
                return container
            } catch {
                state = .failed(error.localizedDescription)
                throw OCREngineError.recognitionFailed(underlying: "VLM load: \(error.localizedDescription)")
            }
        }
    }

    public nonisolated func recognize(image: CGImage, options: OCROptions) async throws -> [OCRResult] {
        let container = try await loadModel()
        let ciImage = CIImage(cgImage: image)

        let prompt = """
        Tu es un OCR. Lis tout le texte visible dans cette image (tableau de forgemagie Dofus).
        Retourne UNIQUEMENT le texte brut, **une ligne par stat visible**, dans l'ordre vertical.
        Pas de commentaire, pas de formatage markdown, pas d'explication.
        Format : "<valeur> <nom de stat>" ex: "96 Vitalité" ou "1 Portée".
        """

        let generated: String = try await container.perform { (context: ModelContext) -> String in
            let images: [UserInput.Image] = [.ciImage(ciImage)]
            let chat: [Chat.Message] = [
                .system("You are an OCR. Return only the raw text visible in the image."),
                .user(prompt, images: images, videos: []),
            ]
            var userInput = UserInput(chat: chat)
            userInput.processing.resize = .init(width: 448, height: 448)
            let lmInput = try await context.processor.prepare(input: userInput)
            let params = MLXLMCommon.GenerateParameters(maxTokens: 400, temperature: 0.0)
            let stream = try MLXLMCommon.generate(
                input: lmInput, parameters: params, context: context
            )
            var output = ""
            for await item in stream {
                if case .chunk(let text) = item { output += text }
            }
            return output
        }

        return parseTextToObservations(generated, imageSize: CGSize(width: image.width, height: image.height))
    }

    /// Parse la réponse texte en observations OCR avec bbox synthétiques (line-based).
    private nonisolated func parseTextToObservations(_ text: String, imageSize: CGSize) -> [OCRResult] {
        let lines = text.split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty, imageSize.height > 0 else { return [] }
        let lineHeight = imageSize.height / CGFloat(lines.count)
        return lines.enumerated().map { i, line in
            let y = CGFloat(i) * lineHeight
            return OCRResult(
                text: line.trimmingCharacters(in: .whitespaces),
                confidence: 0.85,  // VLM ne fournit pas de confidence per-line
                boundingBox: CGRect(x: 0, y: y, width: imageSize.width, height: lineHeight)
            )
        }
    }

    /// Indicateur état chargement pour l'UI.
    public var loadStatus: String {
        switch state {
        case .idle: return "Non chargé"
        case .loading: return "Téléchargement en cours…"
        case .loaded: return "Prêt"
        case .failed(let r): return "Erreur : \(r)"
        }
    }
}
