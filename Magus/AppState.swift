import AppKit
import CoreGraphics
import Foundation
import MagusCommon
import MagusCore
import MagusDecision
import MagusExecution
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

    // Continuous session monitoring
    public var isSessionActive = false
    public var sessionFps: Double = 0
    private var sessionTask: Task<Void, Never>?
    private var isProcessingFrame = false
    private var lastProcessedAt: Date = .distantPast
    private let sessionThrottleSeconds: TimeInterval = 0.5
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
    private let autoClickMinIntervalSeconds: TimeInterval = 1.5
    private let autoClickMaxPerSession = 600
    private let autoClickMaxSessionMinutes: TimeInterval = 30
    private let maxConsecutiveRegressions = 2
    private let maxConsecutiveNoChange = 5

    // Overlay
    private let overlay = OverlayWindow()
    private let clickMarker = ClickMarkerWindow()
    private let clickEngine = ClickEngine()
    private let clickResolver = ClickTargetResolver()

    // Panic stop hotkey
    private let panicHotkey = GlobalHotkey()

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
        }
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
            selectedItem = try referenceRepository.itemSpec(id: id)
            itemSearchResults = []
            regenerateCurrentPreset()
            recomputeDecision()
            logger.info("Item selected: \(self.selectedItem?.name ?? "?", privacy: .public)")
        } catch {
            logger.error("Item select failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func clearSelectedItem() {
        selectedItem = nil
        currentStatsPreset = nil
        currentDecision = nil
    }

    /// Change le scénario actif et régénère le preset.
    public func setScenario(_ scenario: PresetScenario) {
        currentScenario = scenario
        regenerateCurrentPreset()
        recomputeDecision()
    }

    private func regenerateCurrentPreset() {
        guard let spec = selectedItem else { return }
        currentStatsPreset = StatsPreset.make(scenario: currentScenario, for: spec)
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

    /// Recalcule la décision à partir du snapshot courant + preset + spec.
    public func recomputeDecision() {
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
        let bundle = PresetBundle(stats: stats, config: currentConfigPreset)
        currentDecision = decisionEngine.decide(
            mode: sessionMode,
            snapshot: snapshot,
            preset: bundle,
            spec: selectedItem
        )
        refreshOverlay()
        Task { await self.tryAutoClick() }
    }

    /// Anti-régression : vérifie si le dernier click a fait baisser la stat ciblée.
    /// Détecte aussi no-change (rien n'a bougé → click probablement perdu ou inefficace).
    @MainActor
    private func checkRegressionAfterClick() {
        guard let lastKind = lastClickedStatKind,
              let valueBefore = lastClickedStatValueBefore,
              let currentSnapshot = lastParsedSnapshot,
              let currentValue = currentSnapshot.item?.stat(matching: lastKind)?.value else {
            return
        }
        if currentValue < valueBefore {
            consecutiveRegressions += 1
            consecutiveNoChange = 0
            logger.warning("Regression \(self.consecutiveRegressions): \(currentValue) < \(valueBefore) on stat #\(lastKind.characteristicId)")
            if consecutiveRegressions >= maxConsecutiveRegressions {
                autoClickError = "Régression détectée \(consecutiveRegressions)× → ARRÊT AUTO"
                stopSession()
            }
        } else if currentValue > valueBefore {
            consecutiveRegressions = 0
            consecutiveNoChange = 0
        } else {
            // Pas de changement → click peut-être perdu
            consecutiveNoChange += 1
            logger.debug("No-change #\(self.consecutiveNoChange) sur stat #\(lastKind.characteristicId)")
            if consecutiveNoChange >= maxConsecutiveNoChange {
                autoClickError = "Aucun changement après \(consecutiveNoChange) clics → click probablement perdu. Vérifie la calibration."
                stopSession()
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

        // Calculate click position
        let displayName = self.displayName(for: kind)
        guard let point = clickResolver.cellPosition(
            for: kind,
            rank: rune.power,
            spec: spec,
            statsRegionBounds: statsRegion.bounds,
            baseColumnBounds: profile.regions[.statsBaseColumn]?.bounds,
            paColumnBounds: profile.regions[.statsPaColumn]?.bounds,
            raColumnBounds: profile.regions[.statsRaColumn]?.bounds,
            ocrSnapshot: lastOCRSnapshot,
            statsDisplayName: displayName,
            dofusBounds: window.bounds
        ) else {
            autoClickError = "Position cellule introuvable"
            return
        }

        // Track la valeur AVANT le click pour détection régression
        lastClickedStatKind = kind
        lastClickedStatValueBefore = lastParsedSnapshot?.item?.stat(matching: kind)?.value

        if automation == .demo {
            demoClickCount += 1
            lastAutoClickAt = now
            lastAutoClickDecision = decision
            logger.info("[DEMO] Would click @(\(Int(point.x), privacy: .public), \(Int(point.y), privacy: .public)) — \(rune.power.rawValue, privacy: .public) on \(displayName, privacy: .public)")
        } else {
            do {
                try await clickEngine.click(at: point, pid: window.processID)
                autoClickCount += 1
                lastAutoClickAt = now
                lastAutoClickDecision = decision
                autoClickError = nil
                logger.info("Auto-click #\(self.autoClickCount) @(\(Int(point.x), privacy: .public),\(Int(point.y), privacy: .public))")
            } catch {
                autoClickError = "Click failed: \(error.localizedDescription)"
                logger.error("Auto-click failed: \(error.localizedDescription, privacy: .public)")
            }
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
           (automation == .demo || automation == .auto) {
            let displayName = self.displayName(for: kind)
            if let point = clickResolver.cellPosition(
                for: kind,
                rank: rune.power,
                spec: spec,
                statsRegionBounds: statsRegion.bounds,
                baseColumnBounds: profile.regions[.statsBaseColumn]?.bounds,
                paColumnBounds: profile.regions[.statsPaColumn]?.bounds,
                raColumnBounds: profile.regions[.statsRaColumn]?.bounds,
                ocrSnapshot: lastOCRSnapshot,
                statsDisplayName: displayName,
                dofusBounds: window.bounds
            ) {
                clickMarker.show(at: point)
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

        let pipeline = OCRPipeline()
        let raw = await pipeline.recognize(frame: frame, profile: profile)
        let dict = await buildStatDictionary()
        let builder = SnapshotBuilder(dictionary: dict)
        var parsed = builder.build(from: raw)

        // Filtrage + enrichissement via ItemSpec
        if let spec = selectedItem {
            let allowedKinds = Set(spec.stats.map(\.kind))
            let filtered = (parsed.item?.stats ?? []).filter { allowedKinds.contains($0.kind) }
            let statsText = raw.results[.stats]?.joinedText ?? ""
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

        await MainActor.run {
            self.lastOCRSnapshot = raw
            self.lastParsedSnapshot = parsed
            self.lastStateDiff = diff
            self.recomputeDecision()
        }
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
                let pipeline = OCRPipeline()
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
