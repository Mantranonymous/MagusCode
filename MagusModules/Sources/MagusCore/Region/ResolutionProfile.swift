import CoreGraphics
import Foundation

/// Profil de calibration pour une résolution donnée de la fenêtre Dofus.
/// Contient toutes les régions définies relativement à la fenêtre.
public struct ResolutionProfile: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var referenceWidth: Double
    public var referenceHeight: Double
    public var regions: [RegionKind: Region]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        referenceSize: CGSize,
        regions: [RegionKind: Region] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.referenceWidth = Double(referenceSize.width)
        self.referenceHeight = Double(referenceSize.height)
        self.regions = regions
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var referenceSize: CGSize {
        CGSize(width: referenceWidth, height: referenceHeight)
    }

    public var isComplete: Bool {
        RegionKind.allCases.allSatisfy { regions[$0] != nil }
    }

    public var missingRegions: [RegionKind] {
        RegionKind.allCases.filter { regions[$0] == nil }
    }

    public mutating func setRegion(_ region: Region) {
        regions[region.kind] = region
        updatedAt = Date()
    }

    public mutating func removeRegion(kind: RegionKind) {
        regions.removeValue(forKey: kind)
        updatedAt = Date()
    }
}
