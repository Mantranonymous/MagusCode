import AppKit
import CoreGraphics
import Foundation
import MagusCommon
import MagusCore
import MagusPerception
import MagusPersistence
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

    // State
    public var mode: Mode = .home
    public var flowStep: FlowStep = .checkingPermissions
    public var detectedWindow: WindowInfo?
    public var calibrationFrame: CGImage?
    public var currentProfile: ResolutionProfile?
    public var savedProfiles: [ResolutionProfile] = []

    // OCR test
    public var lastOCRSnapshot: RawOCRSnapshot?
    public var isRunningOCR = false

    private var windowTrackingTask: Task<Void, Never>?

    public init() {
        self.permissions = PermissionManager()
        self.windowFinder = WindowFinder()
        self.screenCapture = ScreenCapture()
        do {
            let db = try DatabaseManager.makeDefault()
            self.regionRepository = RegionRepository(database: db)
            self.savedProfiles = (try? regionRepository.allProfiles()) ?? []
        } catch {
            logger.error("DatabaseManager init failed: \(error.localizedDescription, privacy: .public)")
            // Fallback in-memory pour ne pas crasher
            let db = try! DatabaseManager.makeInMemory()
            self.regionRepository = RegionRepository(database: db)
        }
        bootstrap()
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

    /// Capture une nouvelle frame de Dofus et fait tourner l'OCR pipeline sur
    /// toutes les régions du profil fourni. Stocke le résultat dans lastOCRSnapshot.
    public func runOCRTest(profile: ResolutionProfile) async {
        guard let window = detectedWindow else { return }
        isRunningOCR = true
        defer { isRunningOCR = false }

        do {
            let stream = try await screenCapture.start(windowID: window.windowID, rate: .idle)
            for await frame in stream {
                let pipeline = OCRPipeline()
                let snapshot = await pipeline.recognize(frame: frame, profile: profile)
                await MainActor.run {
                    self.lastOCRSnapshot = snapshot
                }
                await screenCapture.stop()
                logger.info("OCR test completed in \(snapshot.totalElapsedMs)ms for \(snapshot.results.count) regions")
                return
            }
        } catch {
            logger.error("OCR test failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
