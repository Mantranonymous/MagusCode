import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers
import MagusCommon
import MagusCore
import MagusDecision
import MagusExecution
import MagusNetwork
import MagusPerception
import MagusPersistence
import MagusReferenceData
import SwiftUI
import os

private let logger = Logger(subsystem: "com.magus.app", category: "appstate")

@MainActor
@Observable
public final class AppState {

    public enum Mode: Hashable {
        case home
        case calibration
    }

    public enum FlowStep: Hashable {
        case checkingPermissions
        case missingPermissions
        case searchingDofus
        case capturingFirstFrame
        case calibrating
        case ready
        case error(String)
    }

    // Services
    public let permissions: PermissionManager
    public let windowFinder: WindowFinder
    public let screenCapture: ScreenCapture
    public let regionRepository: RegionRepository
    public let referenceRepository: ReferenceRepository
    public let referenceSync: ReferenceDataSync
    public let presetRepository: PresetRepository
    public let settings = AppSettings.shared

    /// Observation passive du trafic réseau Dofus (module MagusNetwork).
    /// Source d'état complémentaire à l'OCR : quand actif, certains champs
    /// de `lastParsedSnapshot` (item, history, reliquat) peuvent venir du
    /// réseau au lieu de l'OCR. Le `ClickEngine` reste responsable des
    /// actions — ce module est purement observation.
    public let networkObserver = NetworkObserver()
    private var networkConsumerTask: Task<Void, Never>?
    /// True si on a déjà loggué qu'un snapshot réseau a été reçu (évite spam).
    private var networkSnapshotReceived: Bool = false
    /// Dernier snapshot reçu via le réseau, prioritaire sur l'OCR pour les
    /// champs qu'il fournit.
    public var lastNetworkSnapshot: GameStateSnapshot?
    /// Statut UI : décrit l'erreur réseau si présente.
    public var networkLastError: String?

    // State
    public var mode: Mode = .home
    public var flowStep: FlowStep = .checkingPermissions
    public var detectedWindow: WindowInfo?
    public var calibrationFrame: CGImage?
    public var currentProfile: ResolutionProfile?
    public var savedProfiles: [ResolutionProfile] = []

    // OCR test
    public var lastOCRSnapshot: RawOCRSnapshot?
    public var lastParsedSnapshot: GameStateSnapshot?
    public var lastStateDiff: StateDiff?
    public var isRunningOCR = false

    // Fixture capture
    public var lastFixturePath: URL?

    // Item selection (DofusDB)
    public var selectedItem: ItemSpec?
    public var itemSearchResults: [RefItem] = []
    public var isSearchingItems = false

    // Decision engine
    public var sessionMode: SessionMode = .maging
    public var currentScenario: PresetScenario = .jetParfait
    public var currentStatsPreset: StatsPreset?
    public var currentConfigPreset: ConfigPreset = .bundledFast
    public var currentDecision: Decision?
    public var savedPresets: [StatsPreset] = []
    private let decisionEngine = DecisionEngine()

    // File d'attente d'items
    public var queue: [QueueItem] = []
    public var isQueueActive = false

    // Continuous session monitoring
    public var isSessionActive = false
    public var sessionFps: Double = 0
    private var sessionTask: Task<Void, Never>?
    private var isProcessingFrame = false
    private var lastProcessedAt: Date = .distantPast
    private var sessionThrottleSeconds: TimeInterval {
        settings.turboMode ? 0.25 : 0.5
    }
    private var sessionStartedAt: Date = .distantPast

    // Route de navigation
    public enum Route: String, Sendable, CaseIterable {
        case activite
        case bibliotheque
        case reglages

        public var displayName: String {
            switch self {
            case .activite: return "Activité"
            case .bibliotheque: return "Bibliothèque"
            case .reglages: return "Réglages"
            }
        }

        public var iconName: String {
            switch self {
            case .activite: return "wand.and.stars"
            case .bibliotheque: return "books.vertical"
            case .reglages: return "gearshape"
            }
        }
    }
    public var currentRoute: Route = .activite
    public var showOnboarding: Bool = !UserDefaults.standard.bool(forKey: "magus.onboardingDone")

    /// Relance le wizard d'onboarding.
    public func replayOnboarding() {
        settings.resetOnboarding()
        showOnboarding = true
    }

    // Mode session
    public enum SessionAutomation: String, Sendable, CaseIterable {
        case guided     // overlay seulement, l'utilisateur clique
        case demo       // simule + log les clicks SANS exécuter (debug)
        case auto       // Magus clique réellement
    }
    public var automation: SessionAutomation = .guided
    public var showAutoConfirm = false  // contrôle l'affichage de la popup

    // Auto-click safety
    public var autoClickCount = 0
    public var demoClickCount = 0  // clicks simulés en mode démo
    public var lastAutoClickAt: Date = .distantPast
    public var lastAutoClickDecision: Decision?
    public var lastClickedStatKind: StatKind?
    public var lastClickedStatValueBefore: Int?
    public var consecutiveRegressions = 0
    public var consecutiveNoChange = 0  // OCR successifs sans changement de stat
    public var autoClickError: String?
    /// True pendant qu'un click auto est en cours (mouvement + click + propagation).
    /// Pendant ce temps : pas de re-décision, pas de check de régression.
    private var isAutoClickInFlight = false

    // Workflow multi-étapes (ExoFast-style)
    public var currentStepIndex: Int = 0

    // Toast / banner UI feedback
    public var toastMessage: String?
    public var toastIsError: Bool = false
    private var toastTask: Task<Void, Never>?

    /// Affiche un toast (banner) en haut de l'UI pendant `duration` secondes.
    public func showToast(_ message: String, isError: Bool = false, duration: TimeInterval = 4) {
        toastMessage = message
        toastIsError = isError
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            await MainActor.run { self?.toastMessage = nil }
        }
    }

    // MARK: - Network observation (MagusNetwork)

    /// Démarre l'observation passive du trafic Dofus.
    /// Spawn Dofus.app via Frida + listener TCP local. **Ne forge aucun
    /// paquet** : c'est juste un proxy forward-only avec inspection.
    public func startNetworkObservation() async {
        networkLastError = nil
        let dofusPathStr = settings.networkDofusPath.isEmpty
            ? nil
            : URL(fileURLWithPath: settings.networkDofusPath)
        do {
            try await networkObserver.start(
                port: settings.networkProxyPort,
                dofusPath: dofusPathStr
            )
            networkConsumerTask?.cancel()
            let stream = await networkObserver.snapshotStream()
            networkConsumerTask = Task { [weak self] in
                for await snapshot in stream {
                    await MainActor.run {
                        guard let self else { return }
                        self.lastNetworkSnapshot = snapshot
                        self.mergeNetworkSnapshotIntoState(snapshot)
                        if !self.networkSnapshotReceived {
                            self.networkSnapshotReceived = true
                            logger.info("First network snapshot received")
                        }
                    }
                }
            }
            showToast("Observation réseau active", isError: false)
            logger.info("Network observation started on port \(self.settings.networkProxyPort, privacy: .public)")
        } catch {
            networkLastError = String(describing: error)
            settings.networkObservationEnabled = false
            showToast("Observation réseau : \(error)", isError: true, duration: 8)
            logger.error("Network observation failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Arrête l'observation réseau et clean up le consumer.
    public func stopNetworkObservation() {
        networkConsumerTask?.cancel()
        networkConsumerTask = nil
        networkObserver.stop()
        networkSnapshotReceived = false
        lastNetworkSnapshot = nil
        logger.info("Network observation stopped")
    }

    /// Diagnostic rapide : spawn Frida + check READY, puis coupe.
    public func runNetworkDiagnostic() async {
        let dofusPathStr = settings.networkDofusPath.isEmpty
            ? nil
            : URL(fileURLWithPath: settings.networkDofusPath)
        do {
            let report = try await networkObserver.runDiagnostic(
                port: settings.networkProxyPort,
                dofusPath: dofusPathStr
            )
            showToast(report, isError: false, duration: 10)
            logger.info("Network diagnostic OK: \(report, privacy: .public)")
        } catch {
            networkLastError = String(describing: error)
            showToast("Diagnostic réseau : \(error)", isError: true, duration: 10)
            logger.error("Network diagnostic failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Fusionne un snapshot réseau dans `lastParsedSnapshot`. Le réseau est
    /// prioritaire sur l'OCR pour les champs qu'il fournit, l'OCR reste source
    /// unique pour les champs vides côté réseau.
    private func mergeNetworkSnapshotIntoState(_ network: GameStateSnapshot) {
        // Scaffolding : tant que NetworkStateBuilder ne hydrate pas vraiment les
        // champs (faute de .pb.swift générés), on ne fait que tracer la
        // réception. Une fois `protoc` lancé et NetworkStateBuilder complété,
        // remplacer ce corps par une vraie fusion item/history/reliquat.
        guard network.item != nil
            || !network.history.isEmpty
            || network.reliquat != nil
        else { return }

        let base = lastParsedSnapshot ?? GameStateSnapshot()
        let merged = GameStateSnapshot(
            timestamp: network.timestamp,
            item: network.item ?? base.item,
            history: network.history.isEmpty ? base.history : network.history,
            reliquat: network.reliquat ?? base.reliquat,
            jobLevel: base.jobLevel,
            jobName: base.jobName
        )
        self.lastParsedSnapshot = merged
        logger.debug("Merged network snapshot into state (network=\(network.item != nil ? "item" : "—", privacy: .public)/\(network.history.count, privacy: .public)hist)")
    }

    // Pauses anti-detect (pattern ExoFast : pause 5-15s toutes les 20-40s)
    public var isPausing: Bool = false
    public var pauseUntil: Date = .distantPast
    private var nextPauseAt: Date = .distantFuture
    private let pauseEveryRange: ClosedRange<TimeInterval> = 20...40
    private let pauseDurationRange: ClosedRange<TimeInterval> = 5...15

    // Détection runes épuisées via historique FM
    public var depletedRunes: Set<Rune> = []
    private var lastHistoryCount: Int = 0
    private var noHistoryGrowthCount: [Rune: Int] = [:]
    /// 5 clics sans historique → marqué épuisé. Augmenté de 3 → 5 pour tolérer
    /// les clics ratés en cas de léger décalage de calibration ou de lag Dofus.
    private let maxNoHistoryGrowthBeforeDeplete = 5
    /// Compteur d'auto-récupération depletion : si TOUT est bloqué uniquement
    /// à cause des runes épuisées, on tente un reset une fois avant d'abandonner.
    private var depletionRecoveryAttempts = 0

    // Compteurs session FM (lus depuis l'historique du jeu)
    public var sessionScCount: Int = 0
    public var sessionSnCount: Int = 0
    public var sessionEcCount: Int = 0

    // Probabilités et risques de la décision courante (calculés à chaque recomputeDecision)
    public var currentProbabilities: SuccessProbabilityModel.Probabilities?
    public var currentRiskDrops: [RiskSimulator.PredictedDrop] = []

    private let probaModel = SuccessProbabilityModel()
    private let riskSim = RiskSimulator()

    /// Dictionnaire de stats partagé entre les pipelines OCR et le ClickTargetResolver.
    /// Évite de le reconstruire à chaque click. Rebuilt après chaque sync DofusDB.
    private var cachedDictionary: StatDictionary?
    private var autoClickMinIntervalSeconds: TimeInterval {
        settings.turboMode ? 0.8 : 1.5
    }
    private let autoClickMaxPerSession = 600
    private let autoClickMaxSessionMinutes: TimeInterval = 30
    private let maxConsecutiveRegressions = 2
    private let maxConsecutiveNoChange = 8
    /// Délai à attendre après un click avant de juger no-change/regression.
    /// Sans ça, on lit la stat avant que Dofus ait propagé la nouvelle valeur
    /// → faux no-change → safety stop alors que le click a fonctionné.
    private var postClickJudgmentDelaySeconds: TimeInterval {
        settings.turboMode ? 0.8 : 1.5
    }

    // Overlay
    private let overlay = OverlayWindow()
    private let clickMarker = ClickMarkerWindow()
    private let clickEngine = ClickEngine()
    private let clickResolver = ClickTargetResolver()

    // Panic stop hotkey
    private let panicHotkey = GlobalHotkey()
    private let diagnosticsHotkey = GlobalHotkey()
    let diagnostics = DiagnosticsController()

    // DofusDB sync
    public var syncProgress: SyncProgress = SyncProgress(stage: .idle)
    public var lastSyncAt: Date?
    public var dofusDBVersion: String?
    public var refStats: (chars: Int, items: Int, effects: Int) = (0, 0, 0)
    public var isSyncingReference = false
    public var lastSyncError: String?
    public var characteristicsByID: [Int: RefCharacteristic] = [:]

    private var windowTrackingTask: Task<Void, Never>?

    public init() {
        self.permissions = PermissionManager()
        self.windowFinder = WindowFinder()
        self.screenCapture = ScreenCapture()
        let db: DatabaseManager
        do {
            db = try DatabaseManager.makeDefault()
        } catch {
            logger.error("DatabaseManager init failed: \(error.localizedDescription, privacy: .public)")
            db = try! DatabaseManager.makeInMemory()
        }
        self.regionRepository = RegionRepository(database: db)
        self.referenceRepository = ReferenceRepository(database: db)
        self.presetRepository = PresetRepository(database: db)
        self.referenceSync = ReferenceDataSync(
            client: DofusDBClient(),
            repository: self.referenceRepository
        )
        self.savedProfiles = (try? regionRepository.allProfiles()) ?? []
        self.savedPresets = (try? presetRepository.allPresets()) ?? []
        loadReferenceMeta()
        bootstrap()

        // Lance la sync DofusDB en arrière-plan si nécessaire
        Task { await self.checkAndSyncReference() }

        // Hotkey panic stop ⌘⌥. (Cmd+Opt+.)
        panicHotkey.register { [weak self] in
            self?.emergencyStop()
        }

        // Hotkey diagnostics ⌘⌥D (D = kVK_ANSI_D = 2)
        diagnosticsHotkey.register(
            keyCode: 2,
            modifiers: 256 | 2048  // cmdKey | optionKey (Carbon)
        ) { [weak self] in
            guard let self = self else { return }
            self.diagnostics.toggle(appState: self)
        }

        // Re-check des permissions à chaque retour au foreground.
        // macOS ne propage pas une permission accordée pendant que l'app tourne
        // sans que le processus la re-query explicitement.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.retryPermissions()
            }
        }
    }

    private func loadReferenceMeta() {
        dofusDBVersion = try? referenceRepository.getMeta(.dofusDBVersion)
        if let s = try? referenceRepository.getMeta(.lastSyncAt) {
            lastSyncAt = ISO8601DateFormatter().date(from: s)
        }
        refStats = (
            chars: (try? referenceRepository.characteristicCount()) ?? 0,
            items: (try? referenceRepository.itemCount()) ?? 0,
            effects: (try? referenceRepository.effectCount()) ?? 0
        )
        if let all = try? referenceRepository.allCharacteristics() {
            characteristicsByID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
            // Rebuild le dictionnaire partagé pour le ClickTargetResolver
            let entries: [(kind: StatKind, displayName: String)] = all.compactMap { c in
                guard let name = c.nameFR, !name.isEmpty, c.visible else { return nil }
                return (StatKind(characteristicId: c.id), name)
            }
            cachedDictionary = StatDictionary(referenceEntries: entries)
        }
    }

    /// Met à jour un champ d'une stat dans le preset courant.
    /// Tous les paramètres sauf `kind` sont optionnels : seuls les non-nil sont appliqués.
    public func updateStat(
        for kind: StatKind,
        target: Int? = nil,
        minimum: Int?? = nil,    // double optional pour distinguer "ne pas toucher" et "set à nil"
        priority: Int? = nil,
        enabled: Bool? = nil
    ) {
        guard var preset = currentStatsPreset else { return }
        let existing = preset.targets[kind]
        let newMin: Int? = {
            if let minimum = minimum { return minimum }
            return existing?.minimum
        }()
        preset.targets[kind] = StatTarget(
            target: target.map { max(0, $0) } ?? existing?.target ?? 0,
            minimum: newMin,
            priority: priority ?? existing?.priority ?? 100,
            enabled: enabled ?? existing?.enabled ?? true
        )
        preset.updatedAt = Date()
        currentStatsPreset = preset
        recomputeDecision()
    }

    public func updateTarget(for kind: StatKind, newTarget: Int) {
        updateStat(for: kind, target: newTarget)
    }

    public func toggleEnabled(for kind: StatKind) {
        let current = currentStatsPreset?.targets[kind]?.enabled ?? true
        updateStat(for: kind, enabled: !current)
    }

    /// Exporte le preset courant vers un fichier JSON (.magus.json) via NSSavePanel.
    public func exportCurrentPreset() {
        guard let preset = currentStatsPreset else {
            autoClickError = "Aucun preset à exporter."
            return
        }
        let io = PresetIO()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = io.suggestedFilename(for: preset)
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.title = "Exporter le preset"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try io.encode(stats: preset, config: self.currentConfigPreset)
                try data.write(to: url)
                logger.info("Preset exporté : \(url.path, privacy: .public)")
            } catch {
                logger.error("Export preset failed: \(error.localizedDescription, privacy: .public)")
                Task { @MainActor in self.autoClickError = "Export échoué : \(error.localizedDescription)" }
            }
        }
    }

    /// Importe un preset depuis un fichier .efitem (format ExoFast).
    /// Extrait le nom de l'item + targets best-effort, puis matche dans DofusDB.
    public func importEfitem() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Importer un .efitem (ExoFast)"
        // .efitem n'a pas de UTI, on autorise tous les fichiers
        panel.allowsOtherFileTypes = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try Data(contentsOf: url)
                let parsed = try EfitemImporter().parse(data)
                Task { @MainActor in
                    // Cherche l'item dans DofusDB par nom
                    let matches = (try? self.referenceRepository.searchItems(query: parsed.itemName, limit: 5)) ?? []
                    guard let firstMatch = matches.first,
                          let spec = try? self.referenceRepository.itemSpec(id: firstMatch.id) else {
                        self.autoClickError = "Item « \(parsed.itemName) » introuvable dans DofusDB."
                        return
                    }
                    self.selectedItem = spec
                    // Construit un preset jet parfait + override des targets parsés
                    var preset = StatsPreset.perfectJet(for: spec)
                    var applied = 0
                    var unapplied: [Int] = []
                    for (charId, target) in parsed.targets {
                        let kind = StatKind(characteristicId: charId)
                        if let t = preset.targets[kind] {
                            preset.targets[kind] = StatTarget(
                                target: target,
                                minimum: t.minimum,
                                priority: t.priority,
                                enabled: t.enabled
                            )
                            applied += 1
                            logger.info("Efitem target appliqué: char=\(charId, privacy: .public) target=\(target, privacy: .public)")
                        } else {
                            // Stat parsée du .efitem mais absente du spec DofusDB → on l'ajoute quand même
                            preset.targets[kind] = StatTarget(target: target, minimum: nil, priority: 100, enabled: true)
                            unapplied.append(charId)
                            logger.warning("Efitem target ajouté hors spec: char=\(charId, privacy: .public) target=\(target, privacy: .public) (stat pas dans le spec DofusDB)")
                        }
                    }
                    preset.name = "Importé — \(spec.name)"
                    self.currentStatsPreset = preset
                    self.recomputeDecision()
                    self.showToast("Preset « \(spec.name) » importé (\(applied)/\(parsed.targets.count) targets appliqués, \(unapplied.count) hors spec)")
                    logger.info("Efitem importé : \(parsed.itemName, privacy: .public) (\(applied) appliqués, \(unapplied.count) ajoutés)")
                }
            } catch {
                logger.error("Import efitem failed: \(error.localizedDescription, privacy: .public)")
                Task { @MainActor in self.showToast("Import .efitem échoué : \(error.localizedDescription)", isError: true) }
            }
        }
    }

    /// Importe un preset depuis un fichier JSON et le charge comme preset courant.
    public func importPreset() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Importer un preset"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try Data(contentsOf: url)
                let payload = try PresetIO().decode(data)
                Task { @MainActor in
                    self.currentStatsPreset = payload.stats
                    self.currentConfigPreset = payload.config
                    // Charger l'item du preset si on a accès à son spec
                    if let id = payload.stats.itemSpecId,
                       let spec = try? self.referenceRepository.itemSpec(id: id) {
                        self.selectedItem = spec
                    }
                    self.recomputeDecision()
                    self.showToast("Preset « \(payload.stats.name) » importé")
                    logger.info("Preset importé : \(payload.stats.name, privacy: .public)")
                }
            } catch {
                logger.error("Import preset failed: \(error.localizedDescription, privacy: .public)")
                Task { @MainActor in self.showToast("Import échoué : \(error.localizedDescription)", isError: true) }
            }
        }
    }

    /// Remplit le preset courant depuis les valeurs OCR actuelles de l'item.
    /// Si une stat est déjà au max → target = max (sera skip).
    /// Si une stat a une valeur < max → target = max (Magus poussera).
    /// Inspiré d'ExoFast "Remplir depuis l'item".
    public func fillPresetFromCurrentItem() {
        guard let item = lastParsedSnapshot?.item, !item.stats.isEmpty else {
            autoClickError = "Aucun item parsé — lance un OCR d'abord."
            return
        }
        guard let spec = selectedItem else {
            autoClickError = "Sélectionne un item dans le picker d'abord."
            return
        }
        var targets: [StatKind: StatTarget] = [:]
        for stat in item.stats {
            guard let max = stat.maxValue else { continue }
            targets[stat.kind] = StatTarget(
                target: max,
                minimum: stat.minValue,
                priority: 100,
                enabled: true
            )
        }
        let preset = StatsPreset(
            name: "Depuis l'item — \(spec.name)",
            scenario: .jetParfait,
            itemSpecId: spec.id,
            targets: targets
        )
        currentStatsPreset = preset
        recomputeDecision()
        logger.info("Preset rempli depuis l'item (\(targets.count) stats)")
    }

    /// Bouton manuel : retire toutes les runes blacklistées (si l'user a rechargé son stock).
    public func resetDepletedRunes() {
        depletedRunes.removeAll()
        noHistoryGrowthCount.removeAll()
    }

    /// Nombre total de combines FM cette session.
    public var sessionCombineCount: Int {
        sessionScCount + sessionSnCount + sessionEcCount
    }

    /// Cadence moyenne en combines/min depuis le début de session.
    public var sessionCombinesPerMinute: Double {
        guard isSessionActive, sessionCombineCount > 0 else { return 0 }
        let minutes = Date().timeIntervalSince(sessionStartedAt) / 60.0
        guard minutes > 0 else { return 0 }
        return Double(sessionCombineCount) / minutes
    }

    /// Estimation du temps restant pour atteindre les targets (en minutes).
    /// Basé sur la distance totale restante et la cadence actuelle.
    public var estimatedMinutesRemaining: Int? {
        guard isSessionActive, sessionCombinesPerMinute > 0,
              let preset = currentStatsPreset,
              let item = lastParsedSnapshot?.item else { return nil }
        var totalDistance = 0
        for (kind, target) in preset.targets {
            guard target.enabled else { continue }
            let current = item.stat(matching: kind)?.value ?? 0
            totalDistance += max(0, target.target - current)
        }
        guard totalDistance > 0 else { return 0 }
        // Estime nombre de combines nécessaires : distance / bonus moyen × proba SC moyenne
        let avgBonus = 6.0  // moyenne base/Pa/Ra
        let avgScRate = 0.4  // estimation conservative
        let neededCombines = Double(totalDistance) / (avgBonus * avgScRate)
        return Int((neededCombines / sessionCombinesPerMinute).rounded())
    }

    /// Helper UI : résout le nom FR d'une stat depuis le cache, en l'embellissant
    /// pour les cas où DofusDB stocke un nom ambigu (ex: "Terre" = dommage Terre).
    public func displayName(for kind: StatKind) -> String {
        let raw = characteristicsByID[kind.characteristicId]?.nameFR ?? "#\(kind.characteristicId)"
        switch kind.characteristicId {
        case 88, 89, 90, 91, 92:
            // Dommages élémentaires : DofusDB stocke "Terre" mais l'UI Dofus dit "Dommage Terre"
            return "Dommage \(raw)"
        case 33, 34, 35, 36, 37:
            // Résistances en % : "Terre (%)" → "Résistance Terre %"
            let cleaned = raw.replacingOccurrences(of: "(%)", with: "").trimmingCharacters(in: .whitespaces)
            return "Résistance \(cleaned) %"
        case 54, 55, 56, 57, 58:
            // Résistances fixes : "Terre (fixe)" → "Résistance Terre"
            let cleaned = raw.replacingOccurrences(of: "(fixe)", with: "").trimmingCharacters(in: .whitespaces)
            return "Résistance \(cleaned)"
        case 18:
            // DofusDB "Critique" = % de coup critique → disambigue
            return "% Critique"
        case 86:
            // DofusDB "Critiques" = Dommages Critiques → disambigue
            return "Dommages Critiques"
        case 123:
            // DofusDB "Sorts (%)" → "Do Sort %"
            return "Do Sort %"
        case 120:
            // DofusDB "Distance (%)" → "Do Distance %"
            return "Do Distance %"
        default:
            return raw
        }
    }

    // MARK: - Item selection

    public func searchItems(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            itemSearchResults = []
            return
        }
        isSearchingItems = true
        do {
            itemSearchResults = try referenceRepository.searchItems(query: trimmed, limit: 30)
        } catch {
            logger.error("Item search failed: \(error.localizedDescription, privacy: .public)")
            itemSearchResults = []
        }
        isSearchingItems = false
    }

    public func selectItem(id: Int) {
        do {
            guard let newSpec = try referenceRepository.itemSpec(id: id) else {
                logger.error("Item select : spec introuvable pour id \(id, privacy: .public)")
                return
            }
            let wasAlreadySelected = selectedItem?.id == newSpec.id
            selectedItem = newSpec
            itemSearchResults = []
            // **Préserve le preset existant** si on resélectionne le MÊME item
            // (sinon import .efitem → click item → écrasement).
            if !wasAlreadySelected || currentStatsPreset == nil {
                regenerateCurrentPreset()
                currentConfigPreset = StatsPreset.smartConfig(for: newSpec)
            }
            recomputeDecision()
            logger.info("Item selected: \(self.selectedItem?.name ?? "?", privacy: .public) (preset \(wasAlreadySelected ? "préservé" : "régénéré", privacy: .public))")
        } catch {
            logger.error("Item select failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func clearSelectedItem() {
        selectedItem = nil
        currentStatsPreset = nil
        currentDecision = nil
    }

    /// Change le scénario actif.
    /// **Préserve les targets custom** si un preset est déjà chargé (importé/édité).
    /// Ajoute seulement les targets nouvelles nécessaires au scenario (ex: PA pour exoPA).
    public func setScenario(_ scenario: PresetScenario) {
        currentScenario = scenario
        if currentStatsPreset != nil {
            mergeScenarioRequirements(scenario)
        } else {
            regenerateCurrentPreset()
        }
        recomputeDecision()
    }

    /// Régénère totalement le preset à partir du scenario (perte des targets custom).
    private func regenerateCurrentPreset() {
        guard let spec = selectedItem else { return }
        currentStatsPreset = StatsPreset.make(scenario: currentScenario, for: spec)
    }

    /// Préserve les targets existantes et ajoute seulement ce qui est nécessaire
    /// au scenario (ex: target PA=1 pour exoPA, target Sort=N pour exoDoSort).
    /// Update aussi le scenario du preset.
    private func mergeScenarioRequirements(_ scenario: PresetScenario) {
        guard var preset = currentStatsPreset else { return }
        preset.scenario = scenario
        // Si scenario exo : ajouter la cible exo si pas déjà présente
        if let exo = scenario.exoTarget {
            let exoKind = StatKind(characteristicId: exo.characteristicId)
            if preset.targets[exoKind] == nil {
                preset.targets[exoKind] = StatTarget(
                    target: exo.target,
                    minimum: nil,
                    priority: 120,  // top
                    enabled: true
                )
            } else {
                // Ajuste juste la target si l'user n'avait pas configuré le bon pct
                let existing = preset.targets[exoKind]!
                if existing.target < exo.target {
                    preset.targets[exoKind] = StatTarget(
                        target: exo.target,
                        minimum: existing.minimum,
                        priority: max(existing.priority, 120),
                        enabled: true
                    )
                }
            }
        }
        preset.updatedAt = Date()
        currentStatsPreset = preset
    }

    /// Sauvegarde le preset courant en DB.
    public func saveCurrentPreset() {
        guard let preset = currentStatsPreset else { return }
        do {
            var p = preset
            p.updatedAt = Date()
            try presetRepository.save(p)
            currentStatsPreset = p
            refreshSavedPresets()
            logger.info("Preset sauvegardé: \(p.name, privacy: .public)")
        } catch {
            logger.error("Save preset failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func loadPreset(_ preset: StatsPreset) {
        currentStatsPreset = preset
        currentScenario = preset.scenario
        currentStepIndex = 0
        recomputeDecision()
    }

    public func deletePreset(_ preset: StatsPreset) {
        do {
            try presetRepository.delete(id: preset.id)
            refreshSavedPresets()
        } catch {
            logger.error("Delete preset failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func refreshSavedPresets() {
        savedPresets = (try? presetRepository.allPresets()) ?? []
    }

    // MARK: - File d'attente

    public func addToQueue() {
        guard let spec = selectedItem, let preset = currentStatsPreset else { return }
        let item = QueueItem(
            itemSpecId: spec.id,
            itemName: spec.name,
            presetId: preset.id,
            presetName: preset.name
        )
        queue.append(item)
    }

    public func removeFromQueue(_ item: QueueItem) {
        queue.removeAll { $0.id == item.id }
    }

    public func moveQueueItem(from source: IndexSet, to destination: Int) {
        queue.move(fromOffsets: source, toOffset: destination)
    }

    public func clearQueue() {
        queue.removeAll()
        isQueueActive = false
    }

    /// Démarre la file d'attente : passe en mode auto et traite chaque item séquentiellement.
    /// L'utilisateur doit poser l'item dans Dofus à chaque transition.
    public func startQueue() {
        guard !queue.isEmpty else { return }
        guard automation == .auto else {
            autoClickError = "La file d'attente nécessite le mode Auto"
            return
        }
        isQueueActive = true
        advanceToNextQueueItem()
    }

    public func stopQueue() {
        isQueueActive = false
        for i in queue.indices where queue[i].status == .current {
            queue[i].status = .pending
        }
        stopSession()
    }

    private func advanceToNextQueueItem() {
        guard isQueueActive else { return }
        if let currentIdx = queue.firstIndex(where: { $0.status == .current }) {
            queue[currentIdx].status = .done
        }
        guard let nextIdx = queue.firstIndex(where: { $0.status == .pending }) else {
            isQueueActive = false
            stopSession()
            logger.info("File d'attente terminée")
            return
        }
        queue[nextIdx].status = .current
        let item = queue[nextIdx]
        selectItem(id: item.itemSpecId)
        if let preset = try? presetRepository.preset(id: item.presetId) {
            loadPreset(preset)
        }
        startSession()
        logger.info("File : démarrage item \(item.itemName, privacy: .public)")
    }

    /// Recalcule la décision à partir du snapshot courant + preset + spec.
    public func recomputeDecision() {
        // Pendant un click in-flight, on garde la décision stable (sinon l'overlay
        // change pendant le mouvement de curseur et la safety juge sur la mauvaise stat).
        guard !isAutoClickInFlight else { return }

        guard let snapshot = lastParsedSnapshot else {
            currentDecision = nil
            refreshOverlay()
            return
        }
        guard let stats = currentStatsPreset else {
            currentDecision = .blocked(reason: .noPresetSelected)
            refreshOverlay()
            return
        }
        // Multi-step : si le preset a des étapes, on construit un sous-preset
        // virtuel avec uniquement les targets de l'étape courante.
        let effectiveStats: StatsPreset = {
            guard stats.isMultiStep else { return stats }
            var s = stats
            s.targets = stats.effectiveTargets(at: currentStepIndex)
            return s
        }()
        let bundle = PresetBundle(
            stats: effectiveStats,
            config: currentConfigPreset,
            depletedRunes: depletedRunes
        )
        currentDecision = decisionEngine.decide(
            mode: sessionMode,
            snapshot: snapshot,
            preset: bundle,
            spec: selectedItem
        )
        // Auto-recovery depletion : si bloqué et le message indique "marquées épuisées",
        // c'est probablement un faux positif (clics ratés en cascade). On reset la
        // depletion UNE fois et on retente. Si ça rebloque, on laisse le user gérer.
        if case .blocked(let reason) = currentDecision,
           case .noActionPossible(let msg) = reason,
           msg.contains("marquées épuisées"),
           depletionRecoveryAttempts == 0,
           !depletedRunes.isEmpty {
            logger.warning("Auto-recovery depletion : reset \(self.depletedRunes.count) runes blacklistées et retry")
            depletedRunes.removeAll()
            noHistoryGrowthCount.removeAll()
            depletionRecoveryAttempts += 1
            let retryBundle = PresetBundle(
                stats: effectiveStats,
                config: currentConfigPreset,
                depletedRunes: []
            )
            currentDecision = decisionEngine.decide(
                mode: sessionMode,
                snapshot: snapshot,
                preset: retryBundle,
                spec: selectedItem
            )
        }
        // Si la décision est productive (rune ou finished), on reset le compteur
        // d'auto-recovery pour autoriser une future tentative en cas de re-blocage.
        if case .applyRune = currentDecision { depletionRecoveryAttempts = 0 }
        if case .finished = currentDecision { depletionRecoveryAttempts = 0 }
        // Multi-step : si l'étape courante est .finished, on passe à la suivante automatiquement
        if stats.isMultiStep, case .finished = currentDecision,
           currentStepIndex < stats.steps.count - 1 {
            currentStepIndex += 1
            logger.info("Étape FM terminée, passage à l'étape \(self.currentStepIndex + 1)/\(stats.steps.count)")
            // Re-décide avec la nouvelle étape
            let newEffective: StatsPreset = {
                var s = stats
                s.targets = stats.effectiveTargets(at: currentStepIndex)
                return s
            }()
            let newBundle = PresetBundle(
                stats: newEffective,
                config: currentConfigPreset,
                depletedRunes: depletedRunes
            )
            currentDecision = decisionEngine.decide(
                mode: sessionMode,
                snapshot: snapshot,
                preset: newBundle,
                spec: selectedItem
            )
        }
        computeProbabilitiesAndRisks()
        refreshOverlay()
        Task { await self.tryAutoClick() }
    }

    /// Force le passage à l'étape suivante du preset multi-étapes (action manuelle UI).
    public func skipCurrentStep() {
        guard let stats = currentStatsPreset, stats.isMultiStep else { return }
        guard currentStepIndex < stats.steps.count - 1 else { return }
        currentStepIndex += 1
        logger.info("Skip manuel : étape \(self.currentStepIndex + 1)/\(stats.steps.count)")
        recomputeDecision()
    }

    /// Remet l'étape courante à 0 (utile quand on charge un nouveau preset).
    public func resetStepIndex() {
        currentStepIndex = 0
    }

    /// Calcule probas SC/SN/EC et prédictions de chute pour la décision courante.
    /// Stocke dans `currentProbabilities` et `currentRiskDrops` pour affichage UI.
    private func computeProbabilitiesAndRisks() {
        guard let decision = currentDecision,
              case let .applyRune(rune, kind, _) = decision,
              let item = lastParsedSnapshot?.item,
              let stat = item.stat(matching: kind),
              let spec = selectedItem,
              let runeWeight = RuneWeights.weight(of: rune) else {
            currentProbabilities = nil
            currentRiskDrops = []
            return
        }
        // Calcul des poids globaux
        let pwrgCurrent = item.stats.reduce(0.0) {
            $0 + Double($1.value) * RuneWeights.unitWeight(of: $1.kind)
        }
        let pwrgMax = spec.stats.reduce(0.0) { sum, statSpec in
            sum + Double(statSpec.maxValue) * RuneWeights.unitWeight(of: statSpec.kind)
        }
        let pwrgCurrentStat = Double(stat.value) * RuneWeights.unitWeight(of: kind)
        let isExo = currentScenario == .exoPA || currentScenario == .exoPM
        let isOver = stat.value >= (stat.maxValue ?? Int.max)

        let inputs = SuccessProbabilityModel.Inputs(
            rune: rune,
            statCurrentValue: stat.value,
            statMin: stat.minValue ?? 0,
            statMax: stat.maxValue ?? stat.value,
            itemLevel: spec.level,
            pwrgCurrent: pwrgCurrent,
            pwrgMax: max(pwrgMax, 1),
            pwrgCurrentStat: pwrgCurrentStat,
            isExo: isExo,
            isOver: isOver,
            pwrgOverEtExo: pwrgCurrent
        )
        currentProbabilities = probaModel.compute(inputs)
        currentRiskDrops = riskSim.predictFallsIfBadOutcome(
            item: item,
            runePosed: rune,
            weightToLose: runeWeight,
            topN: 2
        )
    }

    /// Anti-régression : vérifie si le dernier click a fait baisser la stat ciblée.
    /// Détecte aussi no-change (rien n'a bougé → click probablement perdu ou inefficace).
    @MainActor
    private func checkRegressionAfterClick() {
        // Pendant qu'un click est en cours, on n'a pas encore le résultat → skip.
        guard !isAutoClickInFlight else { return }
        guard let lastKind = lastClickedStatKind,
              let valueBefore = lastClickedStatValueBefore,
              let currentSnapshot = lastParsedSnapshot,
              let currentValue = currentSnapshot.item?.stat(matching: lastKind)?.value else {
            return
        }
        // Attendre un délai post-click avant de juger. Sans ça, Dofus peut ne pas
        // avoir encore propagé la nouvelle valeur dans la table FM → faux no-change.
        let sinceClick = Date().timeIntervalSince(lastAutoClickAt)
        guard sinceClick >= postClickJudgmentDelaySeconds else { return }
        if currentValue < valueBefore {
            consecutiveRegressions += 1
            consecutiveNoChange = 0
            logger.warning("Regression \(self.consecutiveRegressions): \(currentValue) < \(valueBefore) on stat #\(lastKind.characteristicId)")
            if consecutiveRegressions >= maxConsecutiveRegressions {
                autoClickError = "Régression détectée \(consecutiveRegressions)× → ARRÊT AUTO"
                AlertSounds.shared.play(.alert, enabled: settings.soundsEnabled)
                stopSession()
            }
        } else if currentValue > valueBefore {
            consecutiveRegressions = 0
            consecutiveNoChange = 0
        } else {
            // Pas de changement → click peut-être perdu OU rune épuisée en inventaire.
            // On regarde aussi l'historique FM : s'il n'a pas grandi, le click n'a pas
            // déclenché de combine → la rune n'était probablement pas disponible.
            let historyDidGrow = currentSnapshot.history.count > lastHistoryCount
            if !historyDidGrow, let lastDecision = lastAutoClickDecision,
               case let .applyRune(rune, _, _) = lastDecision {
                noHistoryGrowthCount[rune, default: 0] += 1
                if noHistoryGrowthCount[rune, default: 0] >= maxNoHistoryGrowthBeforeDeplete {
                    depletedRunes.insert(rune)
                    noHistoryGrowthCount[rune] = 0
                    logger.warning("Rune épuisée détectée : \(rune.power.rawValue) sur stat #\(rune.kind.characteristicId, privacy: .public) — blacklistée pour la session")
                    AlertSounds.shared.play(.fail, enabled: settings.soundsEnabled)
                    // On reset les compteurs et relance — la prochaine décision évitera cette rune
                    consecutiveNoChange = 0
                    return
                }
            } else if historyDidGrow {
                // Une rune a effectivement été posée → reset les compteurs
                noHistoryGrowthCount.removeAll()
            }
            lastHistoryCount = currentSnapshot.history.count

            // EXCEPTION : en scénario exo (taux SC ~1%), des séries longues de
            // no-change sont normales — on désactive le safety dans ce cas.
            let isExoScenario = currentScenario == .exoPA || currentScenario == .exoPM
            if !isExoScenario {
                consecutiveNoChange += 1
                logger.debug("No-change #\(self.consecutiveNoChange) sur stat #\(lastKind.characteristicId)")
                if consecutiveNoChange >= maxConsecutiveNoChange {
                    autoClickError = "Aucun changement après \(consecutiveNoChange) clics → click probablement perdu. Vérifie la calibration."
                    stopSession()
                }
            }
        }
        lastClickedStatKind = nil
        lastClickedStatValueBefore = nil
    }

    /// Exécute un clic auto si toutes les conditions sont réunies.
    @MainActor
    private func tryAutoClick() async {
        // Vérification post-click précédent
        checkRegressionAfterClick()

        guard isSessionActive else { return }
        guard automation == .auto || automation == .demo else { return }
        guard let decision = currentDecision else { return }
        guard case let .applyRune(rune, kind, _) = decision else { return }

        // Anti-OCR-jitter : si la valeur du stat ciblé a baissé entre les 2 derniers
        // snapshots SANS qu'une combine soit apparue dans l'historique FM, c'est
        // probablement un OCR jitter (Vision a lu "5" comme "4" sur une frame).
        // Dans ce cas, on saute ce click et on attend la prochaine lecture stable.
        // Sinon le bot agirait sur une valeur fantôme et déclencherait des actions
        // inutiles (ex : +1 Dommages alors qu'on est déjà au max).
        if let diff = lastStateDiff,
           diff.combineLanded == nil {
            for change in diff.changes {
                if case let .statChanged(changedKind, oldV, newV) = change,
                   changedKind == kind, newV < oldV {
                    logger.warning("OCR jitter suspecté sur stat #\(kind.characteristicId, privacy: .public) : \(oldV)→\(newV) sans combine. Skip click, attend frame stable.")
                    return
                }
            }
        }

        // Check anti-detect : skip totalement en mode Turbo, sinon pause périodique.
        let now0 = Date()
        if !settings.turboMode {
            if isPausing {
                if now0 >= pauseUntil {
                    isPausing = false
                    nextPauseAt = now0.addingTimeInterval(.random(in: pauseEveryRange))
                    logger.debug("Pause terminée, prochain break dans \(Int(self.nextPauseAt.timeIntervalSince(now0)))s")
                } else {
                    return
                }
            } else if now0 >= nextPauseAt {
                let duration = Double.random(in: pauseDurationRange)
                isPausing = true
                pauseUntil = now0.addingTimeInterval(duration)
                logger.info("Pause anti-detect : \(String(format: "%.1f", duration))s")
                return
            }
        }
        guard let spec = selectedItem,
              let window = detectedWindow,
              let profile = savedProfiles.first(where: { $0.isComplete }),
              let statsRegion = profile.regions[.stats] else { return }

        let now = Date()
        let sinceLast = now.timeIntervalSince(lastAutoClickAt)
        guard sinceLast >= autoClickMinIntervalSeconds else { return }

        // Safety limits
        guard autoClickCount < autoClickMaxPerSession else {
            autoClickError = "Limite de clics atteinte (\(autoClickMaxPerSession))"
            stopSession()
            return
        }
        let sessionDuration = now.timeIntervalSince(sessionStartedAt) / 60
        guard sessionDuration < autoClickMaxSessionMinutes else {
            autoClickError = "Limite de temps atteinte (\(Int(autoClickMaxSessionMinutes)) min)"
            stopSession()
            return
        }

        // Calculate click position : EXO (rune cliquée en inventaire) vs maging (table FM)
        // **Important** : pour les stats EXO-CANDIDATES (PA/PM/PO/Do%) qui sont DÉJÀ
        // natives sur l'item, on doit utiliser la colonne FM (re-mage classique),
        // pas le slot inventaire (réservé aux exos sur stats non-natives).
        let displayName = self.displayName(for: kind)
        let isExo = ClickTargetResolver.isExoTargetForItem(kind, item: lastParsedSnapshot?.item)
        let point: CGPoint?
        let needsDoubleClick: Bool
        let needsFuserClick: Bool

        if isExo, let slotKind = ClickTargetResolver.exoSlotRegionKind(for: kind) {
            // Exo : cliquer la rune Ga PA/PM/Po directement dans l'inventaire calibré,
            // puis le bouton Fusionner pour valider la fusion (Dofus 3 ne pose pas
            // la rune sur simple double-clic depuis l'inventaire).
            point = clickResolver.exoInventorySlotPosition(
                for: kind,
                inventorySlotBounds: profile.regions[slotKind]?.bounds,
                dofusBounds: window.bounds
            )
            needsDoubleClick = false  // un clic suffit pour sélectionner la rune
            needsFuserClick = true
            if point == nil {
                autoClickError = "Slot inventaire pour \(slotKind.displayName) non calibré"
                return
            }
            if profile.regions[.fuserButton] == nil {
                autoClickError = "Bouton 'Fusionner' non calibré (requis pour valider l'exo). Recalibre."
                return
            }
        } else {
            point = clickResolver.cellPosition(
                for: kind,
                rank: rune.power,
                spec: spec,
                statsRegionBounds: statsRegion.bounds,
                baseColumnBounds: profile.regions[.statsBaseColumn]?.bounds,
                paColumnBounds: profile.regions[.statsPaColumn]?.bounds,
                raColumnBounds: profile.regions[.statsRaColumn]?.bounds,
                ocrSnapshot: lastOCRSnapshot,
                statsDisplayName: displayName,
                dofusBounds: window.bounds,
                dictionary: cachedDictionary
            )
            needsDoubleClick = false
            needsFuserClick = false
            if point == nil {
                autoClickError = "Position cellule introuvable"
                return
            }
        }
        guard let clickPoint = point else { return }

        // Safety : refuser de cliquer hors de la fenêtre Dofus (évite de cliquer sur Magus, le bureau, etc.)
        let dofusRect = window.bounds.insetBy(dx: -20, dy: -20)  // tolérance 20px
        guard dofusRect.contains(clickPoint) else {
            autoClickError = "Click calculé hors de la fenêtre Dofus (\(Int(clickPoint.x)), \(Int(clickPoint.y))) — calibration probablement bancale. Stop."
            logger.warning("Click hors Dofus rejeté : \(Int(clickPoint.x)),\(Int(clickPoint.y)) bounds=\(NSStringFromRect(window.bounds), privacy: .public)")
            stopSession()
            return
        }

        // Track la valeur AVANT le click pour détection régression
        lastClickedStatKind = kind
        lastClickedStatValueBefore = lastParsedSnapshot?.item?.stat(matching: kind)?.value

        if automation == .demo {
            demoClickCount += 1
            lastAutoClickAt = now
            lastAutoClickDecision = decision
            let chain = needsFuserClick ? "click+Fusionner" : (needsDoubleClick ? "DOUBLE-click" : "click")
            logger.info("[DEMO] Would \(chain, privacy: .public) @(\(Int(clickPoint.x), privacy: .public), \(Int(clickPoint.y), privacy: .public)) — \(rune.power.rawValue, privacy: .public) on \(displayName, privacy: .public)")
        } else {
            isAutoClickInFlight = true
            do {
                // En mode Turbo, on skip le mouvement humain Bézier (click direct = plus rapide).
                let useHumanMotion = !settings.turboMode
                try await clickEngine.click(at: clickPoint, pid: window.processID, humanMotion: useHumanMotion)
                if needsDoubleClick {
                    try await Task.sleep(nanoseconds: 80_000_000)  // 80ms delay typique
                    try await clickEngine.click(at: clickPoint, pid: window.processID, humanMotion: useHumanMotion)
                }
                // Chaîne le click sur le bouton Fusionner pour finaliser un exo.
                // Sans ce click, la rune reste juste "sélectionnée" dans l'inventaire
                // et le bot boucle en re-cliquant la même rune indéfiniment.
                if needsFuserClick, let fuserBounds = profile.regions[.fuserButton]?.bounds {
                    try await Task.sleep(nanoseconds: 150_000_000)  // 150ms — laisse Dofus enregistrer la sélection
                    let fuserScreen = clickResolver.exoInventorySlotPosition(
                        for: kind,
                        inventorySlotBounds: fuserBounds,
                        dofusBounds: window.bounds
                    )
                    if let fuserPoint = fuserScreen {
                        try await clickEngine.click(at: fuserPoint, pid: window.processID, humanMotion: useHumanMotion)
                        logger.info("Click bouton Fusionner @(\(Int(fuserPoint.x), privacy: .public),\(Int(fuserPoint.y), privacy: .public)) après rune exo")
                    }
                }
                autoClickCount += 1
                lastAutoClickAt = Date()  // post-click, pour le delay de jugement
                lastAutoClickDecision = decision
                autoClickError = nil
                let chain = needsFuserClick ? "click+Fusionner" : (needsDoubleClick ? "double-click" : "click")
                logger.info("Auto-\(chain, privacy: .public) #\(self.autoClickCount) @(\(Int(clickPoint.x), privacy: .public),\(Int(clickPoint.y), privacy: .public))")
            } catch {
                autoClickError = "Click failed: \(error.localizedDescription)"
                logger.error("Auto-click failed: \(error.localizedDescription, privacy: .public)")
            }
            isAutoClickInFlight = false
        }
    }

    /// L'auto requiert que les 3 colonnes click soient calibrées pour précision.
    public var canStartAuto: Bool {
        guard let profile = savedProfiles.first(where: { $0.isComplete }) else { return false }
        return profile.regions[.statsBaseColumn] != nil
            && profile.regions[.statsPaColumn] != nil
            && profile.regions[.statsRaColumn] != nil
    }

    public func checkAndSyncReference() async {
        let needs = (try? await referenceSync.needsSync()) ?? true
        if needs {
            await syncReference()
        }
    }

    public func syncReference() async {
        guard !isSyncingReference else { return }
        await MainActor.run {
            self.isSyncingReference = true
            self.lastSyncError = nil
        }
        do {
            try await referenceSync.sync { progress in
                Task { @MainActor in
                    self.syncProgress = progress
                }
            }
            await MainActor.run {
                self.loadReferenceMeta()
                self.syncProgress = SyncProgress(stage: .done)
            }
        } catch {
            logger.error("Reference sync failed: \(error.localizedDescription, privacy: .public)")
            await MainActor.run {
                self.lastSyncError = "\(error)"
                self.syncProgress = SyncProgress(stage: .failed)
            }
        }
        await MainActor.run {
            self.isSyncingReference = false
        }
    }

    private func bootstrap() {
        permissions.refresh()
        if permissions.allGranted {
            flowStep = .searchingDofus
            startWindowTracking()
        } else {
            flowStep = .missingPermissions
        }
    }

    public func retryPermissions() {
        permissions.refresh()
        if permissions.allGranted {
            flowStep = .searchingDofus
            startWindowTracking()
        }
    }

    public func requestScreenRecording() {
        permissions.requestScreenRecording()
        if permissions.allGranted {
            flowStep = .searchingDofus
            startWindowTracking()
        }
    }

    public func requestAccessibility() {
        permissions.requestAccessibility()
        if permissions.allGranted {
            flowStep = .searchingDofus
            startWindowTracking()
        }
    }

    public func openSettings(for permission: PermissionManager.Permission) {
        permissions.openSystemSettings(for: permission)
    }

    private func startWindowTracking() {
        windowTrackingTask?.cancel()
        let stream = windowFinder.track()
        windowTrackingTask = Task { [weak self] in
            for await window in stream {
                await MainActor.run {
                    self?.detectedWindow = window
                }
            }
        }
    }

    public func startCalibration() async {
        guard let window = detectedWindow else {
            flowStep = .error("Fenêtre Dofus introuvable")
            return
        }
        mode = .calibration
        flowStep = .capturingFirstFrame
        do {
            let stream = try await screenCapture.start(windowID: window.windowID, rate: .idle)
            // On prend la première frame puis on stop le stream
            for await frame in stream {
                calibrationFrame = frame.image
                let profile = ResolutionProfile(
                    name: "Profil \(Int(window.bounds.width))×\(Int(window.bounds.height))",
                    referenceSize: window.bounds.size
                )
                currentProfile = profile
                flowStep = .calibrating
                await screenCapture.stop()
                return
            }
        } catch {
            logger.error("Calibration start failed: \(error.localizedDescription, privacy: .public)")
            flowStep = .error("Capture impossible : \(error.localizedDescription)")
            mode = .home
        }
    }

    public func saveCalibration() {
        guard let profile = currentProfile else { return }
        do {
            try regionRepository.save(profile)
            savedProfiles = (try? regionRepository.allProfiles()) ?? []
            logger.info("Profil de calibration sauvegardé : \(profile.name, privacy: .public)")
            mode = .home
            flowStep = .ready
        } catch {
            logger.error("Save failed: \(error.localizedDescription, privacy: .public)")
            flowStep = .error("Sauvegarde impossible : \(error.localizedDescription)")
        }
    }

    public func cancelCalibration() {
        mode = .home
        currentProfile = nil
        calibrationFrame = nil
        if !savedProfiles.isEmpty {
            flowStep = .ready
        } else {
            flowStep = .searchingDofus
        }
    }

    public func recapture() async {
        await startCalibration()
    }

    /// Capture une nouvelle frame de Dofus et fait tourner le pipeline complet une fois.
    public func runOCRTest(profile: ResolutionProfile) async {
        guard let window = detectedWindow else { return }
        isRunningOCR = true
        defer { isRunningOCR = false }

        do {
            let stream = try await screenCapture.start(windowID: window.windowID, rate: .idle)
            for await frame in stream {
                await processFrame(frame, profile: profile)
                await screenCapture.stop()
                return
            }
        } catch {
            logger.error("OCR test failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Démarre une session de monitoring continue. L'OCR tourne toutes les ~500ms,
    /// la décision est recalculée à chaque snapshot. L'overlay est mis à jour.
    public func startSession() {
        guard !isSessionActive else { return }
        guard let window = detectedWindow else {
            logger.error("Cannot start session: no Dofus window detected")
            return
        }
        guard let profile = savedProfiles.first(where: { $0.isComplete }) else {
            logger.error("Cannot start session: no complete profile")
            return
        }
        // Si auto choisi mais colonnes pas calibrées → bascule en démo (refus silencieux)
        if automation == .auto && !canStartAuto {
            logger.warning("Auto demandé mais colonnes click non calibrées → bascule en demo")
            automation = .demo
        }
        isSessionActive = true
        sessionStartedAt = Date()
        autoClickCount = 0
        demoClickCount = 0
        consecutiveRegressions = 0
        lastClickedStatKind = nil
        lastClickedStatValueBefore = nil
        autoClickError = nil
        // Reset détection runes épuisées : nouvelle session = stock potentiellement rechargé
        depletedRunes.removeAll()
        noHistoryGrowthCount.removeAll()
        lastHistoryCount = 0
        sessionScCount = 0
        sessionSnCount = 0
        sessionEcCount = 0
        isPausing = false
        pauseUntil = .distantPast
        // Première pause planifiée 20-40s après le démarrage
        nextPauseAt = Date().addingTimeInterval(.random(in: pauseEveryRange))
        sessionTask = Task { [weak self] in
            await self?.runSessionLoop(windowID: window.windowID, profile: profile)
            await MainActor.run { self?.isSessionActive = false }
        }
        logger.info("Session démarrée (mode \(self.automation.rawValue, privacy: .public))")
    }

    public func stopSession() {
        sessionTask?.cancel()
        sessionTask = nil
        isSessionActive = false
        sessionFps = 0
        overlay.hide()
        clickMarker.hide()
        logger.info("Session stoppée")
    }

    /// ARRÊT D'URGENCE : stop tout immédiatement, force le mode guidé pour la prochaine session.
    public func emergencyStop() {
        stopSession()
        automation = .guided
        autoClickError = "Arrêt d'urgence déclenché"
        logger.warning("EMERGENCY STOP")
    }

    /// Met à jour l'overlay + click marker à partir de la décision courante.
    private func refreshOverlay() {
        guard isSessionActive,
              let window = detectedWindow,
              let decision = currentDecision else {
            overlay.hide()
            clickMarker.hide()
            return
        }
        let (title, subtitle, severity) = overlayContent(for: decision)
        overlay.show(dofusBounds: window.bounds) {
            OverlayContent(title: title, subtitle: subtitle, severity: severity)
        }

        // Click marker : affiché si on a une applyRune ET un click position calculable
        if case let .applyRune(rune, kind, _) = decision,
           let spec = selectedItem,
           let profile = savedProfiles.first(where: { $0.isComplete }),
           let statsRegion = profile.regions[.stats],
           settings.showClickMarker,
           (automation == .demo || automation == .auto) {
            let displayName = self.displayName(for: kind)
            let isExo = ClickTargetResolver.isExoTargetForItem(kind, item: lastParsedSnapshot?.item)
            let point: CGPoint?
            if isExo, let slotKind = ClickTargetResolver.exoSlotRegionKind(for: kind) {
                point = clickResolver.exoInventorySlotPosition(
                    for: kind,
                    inventorySlotBounds: profile.regions[slotKind]?.bounds,
                    dofusBounds: window.bounds
                )
            } else {
                point = clickResolver.cellPosition(
                    for: kind,
                    rank: rune.power,
                    spec: spec,
                    statsRegionBounds: statsRegion.bounds,
                    baseColumnBounds: profile.regions[.statsBaseColumn]?.bounds,
                    paColumnBounds: profile.regions[.statsPaColumn]?.bounds,
                    raColumnBounds: profile.regions[.statsRaColumn]?.bounds,
                    ocrSnapshot: lastOCRSnapshot,
                    statsDisplayName: displayName,
                    dofusBounds: window.bounds,
                    dictionary: cachedDictionary
                )
            }
            if let p = point {
                clickMarker.show(at: p)
            } else {
                clickMarker.hide()
            }
        } else {
            clickMarker.hide()
        }
    }

    private func overlayContent(for decision: Decision) -> (String, String, OverlayContent.Severity) {
        switch decision {
        case .applyRune(let rune, let kind, let explanation):
            let prefix = rune.power.prefix.isEmpty ? "" : "\(rune.power.prefix) "
            let title = "Rune \(prefix)\(displayName(for: kind))"
            return (title, explanation, .action)
        case .applyExo(let slot, let explanation):
            return ("Exo \(slot.displayName)", explanation, .exo)
        case .applyAntiRune(let rune, let kind, let explanation):
            let prefix = rune.power.prefix.isEmpty ? "" : "\(rune.power.prefix) "
            return ("Anti-rune \(prefix)\(displayName(for: kind))", explanation, .danger)
        case .finished(let e):
            return ("Jet parfait atteint", e, .success)
        case .waitingForUser(let reason):
            return ("En attente", reason, .info)
        case .blocked(let reason):
            return ("Bloqué", reason.description, .info)
        }
    }

    private func runSessionLoop(windowID: CGWindowID, profile: ResolutionProfile) async {
        do {
            let stream = try await screenCapture.start(windowID: windowID, rate: .idle)
            var framesInWindow = 0
            var windowStart = Date()
            for await frame in stream {
                if Task.isCancelled { break }
                let now = Date()
                guard now.timeIntervalSince(lastProcessedAt) >= sessionThrottleSeconds else { continue }
                guard !isProcessingFrame else { continue }
                lastProcessedAt = now

                await processFrame(frame, profile: profile)

                framesInWindow += 1
                let elapsed = now.timeIntervalSince(windowStart)
                if elapsed >= 5 {
                    let fps = Double(framesInWindow) / elapsed
                    await MainActor.run { self.sessionFps = fps }
                    framesInWindow = 0
                    windowStart = now
                }
            }
            await screenCapture.stop()
        } catch {
            logger.error("Session loop failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Pipeline complet : OCR → parsing → filtrage spec → extraction guidée → snapshot → décision.
    private func processFrame(_ frame: CaptureFrame, profile: ResolutionProfile) async {
        guard !isProcessingFrame else { return }
        isProcessingFrame = true
        defer { isProcessingFrame = false }

        await MainActor.run { self.isRunningOCR = true }
        defer { Task { @MainActor in self.isRunningOCR = false } }

        let pipeline = OCRPipeline(
            settings: settings.snapshot,
            customWords: buildOcrCustomWords()
        )
        let raw = await pipeline.recognize(frame: frame, profile: profile)
        let dict = await buildStatDictionary()
        let builder = SnapshotBuilder(dictionary: dict)
        var parsed = builder.build(from: raw)

        // Filtrage + enrichissement via ItemSpec
        if let spec = selectedItem {
            // Stats natives du spec + stats exo possibles (PA, PM, Portée).
            // Les stats exo n'apparaissent jamais dans spec.stats car non natives,
            // mais on doit les garder pour que ExoStrategy sache si l'exo a passé.
            let exoKinds: Set<StatKind> = [
                StatKind(characteristicId: 1),    // PA
                StatKind(characteristicId: 23),   // PM
                StatKind(characteristicId: 11),   // Portée
            ]
            let allowedKinds = Set(spec.stats.map(\.kind)).union(exoKinds)
            let filtered = (parsed.item?.stats ?? []).filter { allowedKinds.contains($0.kind) }
            let statsText = raw.results[.stats]?.rowGroupedText ?? ""
            let extractor = SpecGuidedExtractor(dictionary: dict)
            let enriched = extractor.enrich(parsed: filtered, with: spec, ocrText: statsText)

            let newItem = Item(
                id: parsed.item?.id ?? UUID(),
                referenceItemId: spec.id,
                name: spec.name,
                level: spec.level,
                typeId: spec.typeId,
                stats: enriched,
                exos: parsed.item?.exos ?? []
            )
            parsed = GameStateSnapshot(
                timestamp: parsed.timestamp,
                item: newItem,
                history: parsed.history,
                reliquat: parsed.reliquat,
                jobLevel: parsed.jobLevel,
                jobName: parsed.jobName
            )
        }

        let previous = lastParsedSnapshot
        let diff = previous.map { StateDiff(from: $0, to: parsed) }

        // Compte les nouvelles entrées d'historique pour les stats SC/SN/EC de la session
        let newEntries: [MageHistoryEntry] = {
            guard let prev = previous, parsed.history.count > prev.history.count else { return [] }
            return Array(parsed.history.suffix(parsed.history.count - prev.history.count))
        }()

        await MainActor.run {
            self.lastOCRSnapshot = raw
            self.lastParsedSnapshot = parsed
            self.lastStateDiff = diff
            for entry in newEntries {
                switch entry.result {
                case .criticalSuccess: self.sessionScCount += 1
                case .neutralSuccess: self.sessionSnCount += 1
                case .criticalFail: self.sessionEcCount += 1
                case .unknown: break
                }
            }
            // Alternance auto exo PA/PM (ExoFast feature) :
            // si scenario exo + option activée + combine effectif → flip le scenario
            if !newEntries.isEmpty && self.currentConfigPreset.alternateExoPAPM {
                switch self.currentScenario {
                case .exoPA: self.currentScenario = .exoPM
                case .exoPM: self.currentScenario = .exoPA
                default: break
                }
            }
            // Détection "jet atteint" → sound success
            if case .finished = self.currentDecision ?? .blocked(reason: .noItem) {
                AlertSounds.shared.play(.success, enabled: self.settings.soundsEnabled)
            }
            self.recomputeDecision()
        }
    }

    /// Construit la liste de customWords à donner à Vision pour booster
    /// la reconnaissance des noms de stats français. Source : DofusDB +
    /// formes courtes ExoFast (Vita, Sa, Fo, etc.).
    private func buildOcrCustomWords() -> [String] {
        var words: Set<String> = [
            // Stats principales (formes longues + courtes)
            "Vitalité", "Sagesse", "Force", "Agilité", "Chance", "Intelligence",
            "Vita", "Sa", "Fo", "Agi", "Cha", "Ine",
            "PA", "PM", "Portée", "Puissance", "Pods",
            "Initiative", "Prospection", "Soins", "Soin",
            "Critique", "Dommages", "Dommage",
            "Invocation", "Invocations",
            "Tacle", "Fuite", "Esquive",
            "Renvoi",
            // Élémentaires
            "Feu", "Eau", "Terre", "Air", "Neutre",
            "Dommage Feu", "Dommage Eau", "Dommage Terre", "Dommage Air", "Dommage Neutre",
            "Dommages Feu", "Dommages Eau", "Dommages Terre", "Dommages Air", "Dommages Neutre",
            "Résistance", "Résistance Feu", "Résistance Eau", "Résistance Terre",
            "Résistance Air", "Résistance Neutre",
            "Dommages Critiques", "Dommages Critique",
            // Mots de l'UI FM
            "Min", "Max", "Effets", "Carac", "Modif", "Ra", "Pa",
            "reliquat", "Reliquat",
        ]
        // Enrichit avec les vraies noms FR de la table DofusDB
        for (_, c) in characteristicsByID {
            if let n = c.nameFR, !n.isEmpty {
                words.insert(n)
            }
        }
        return Array(words)
    }

    /// Construit le StatDictionary depuis les caractéristiques DofusDB stockées.
    public func buildStatDictionary() async -> StatDictionary {
        do {
            let chars = try referenceRepository.allCharacteristics()
            let entries: [(kind: StatKind, displayName: String)] = chars.compactMap { c in
                guard let name = c.nameFR, !name.isEmpty, c.visible else { return nil }
                return (StatKind(characteristicId: c.id), name)
            }
            return StatDictionary(referenceEntries: entries)
        } catch {
            logger.error("Failed to build StatDictionary: \(error.localizedDescription, privacy: .public)")
            return StatDictionary(referenceEntries: [])
        }
    }

    /// Capture une fixture : screenshot + OCR + skeleton expected JSON.
    public func captureFixture(profile: ResolutionProfile) async {
        guard let window = detectedWindow else { return }
        do {
            let stream = try await screenCapture.start(windowID: window.windowID, rate: .idle)
            for await frame in stream {
                let pipeline = OCRPipeline(
                    settings: settings.snapshot,
                    customWords: buildOcrCustomWords()
                )
                let raw = await pipeline.recognize(frame: frame, profile: profile)
                let dict = await buildStatDictionary()
                let builder = SnapshotBuilder(dictionary: dict)
                let parsed = builder.build(from: raw)

                let path = try writeFixture(frame: frame, raw: raw, parsed: parsed)
                await MainActor.run {
                    self.lastFixturePath = path
                }
                await screenCapture.stop()
                logger.info("Fixture captured: \(path.path, privacy: .public)")
                return
            }
        } catch {
            logger.error("Capture fixture failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func writeFixture(frame: CaptureFrame, raw: RawOCRSnapshot, parsed: GameStateSnapshot) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let stamp = formatter.string(from: Date())

        // Cherche le dossier Tests/Fixtures dans le repo (utile pour dev).
        // Fallback : Documents/MagusFixtures.
        let baseURL: URL = {
            let fileManager = FileManager.default
            let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath)
            let repoFixtures = URL(fileURLWithPath: "/Users/simonyeche/Desktop/perso/MagusCode/MagusModules/Tests/Fixtures")
            if fileManager.fileExists(atPath: repoFixtures.path) {
                return repoFixtures
            }
            return (try? fileManager.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("MagusFixtures")) ?? cwd
        }()

        let dir = baseURL.appendingPathComponent(stamp)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // 1) Screenshot PNG
        if let rep = NSBitmapImageRep(cgImage: frame.image).representation(using: .png, properties: [:]) {
            try rep.write(to: dir.appendingPathComponent("capture.png"))
        }

        // 2) OCR brut JSON
        let ocrJSON: [String: Any] = [
            "elapsedMs": raw.totalElapsedMs,
            "regions": Dictionary(uniqueKeysWithValues: raw.results.map { (key, value) in
                (key.rawValue, [
                    "engine": value.engine,
                    "elapsedMs": value.elapsedMs,
                    "averageConfidence": value.averageConfidence,
                    "text": value.joinedText,
                    "observations": value.observations.map { o in
                        ["text": o.text, "confidence": o.confidence]
                    }
                ] as [String: Any])
            })
        ]
        let ocrData = try JSONSerialization.data(withJSONObject: ocrJSON, options: [.prettyPrinted, .sortedKeys])
        try ocrData.write(to: dir.appendingPathComponent("ocr.json"))

        // 3) Expected JSON (skeleton à éditer à la main)
        let expectedSkeleton: [String: Any] = [
            "_comment": "Édite manuellement ce fichier avec les valeurs attendues. Utilisé par les tests parsers.",
            "item": [
                "stats": parsed.item?.stats.map { s in
                    [
                        "characteristicId": s.kind.characteristicId,
                        "value": s.value,
                        "minValue": s.minValue as Any,
                        "maxValue": s.maxValue as Any
                    ] as [String: Any]
                } ?? []
            ],
            "reliquat": parsed.reliquat?.density as Any,
            "jobLevel": parsed.jobLevel as Any,
            "jobName": parsed.jobName as Any,
            "historyCount": parsed.history.count
        ]
        let expData = try JSONSerialization.data(withJSONObject: expectedSkeleton, options: [.prettyPrinted, .sortedKeys])
        try expData.write(to: dir.appendingPathComponent("expected.json"))

        return dir
    }
}
