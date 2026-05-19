import AppKit
import CoreGraphics
import Foundation
import MagusCommon
import MagusCore
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
        self.referenceSync = ReferenceDataSync(
            client: DofusDBClient(),
            repository: self.referenceRepository
        )
        self.savedProfiles = (try? regionRepository.allProfiles()) ?? []
        loadReferenceMeta()
        bootstrap()

        // Lance la sync DofusDB en arrière-plan si nécessaire
        Task { await self.checkAndSyncReference() }
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
            logger.info("Item selected: \(self.selectedItem?.name ?? "?", privacy: .public)")
        } catch {
            logger.error("Item select failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func clearSelectedItem() {
        selectedItem = nil
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

    /// Capture une nouvelle frame de Dofus et fait tourner l'OCR pipeline puis les parsers.
    /// Si un item est sélectionné, filtre les stats parsées au spec et enrichit via SpecGuidedExtractor.
    public func runOCRTest(profile: ResolutionProfile) async {
        guard let window = detectedWindow else { return }
        isRunningOCR = true
        defer { isRunningOCR = false }

        do {
            let stream = try await screenCapture.start(windowID: window.windowID, rate: .idle)
            for await frame in stream {
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
                }
                await screenCapture.stop()
                logger.info("OCR+parse done in \(raw.totalElapsedMs)ms — \(parsed.item?.stats.count ?? 0) stats")
                return
            }
        } catch {
            logger.error("OCR test failed: \(error.localizedDescription, privacy: .public)")
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
