import CoreGraphics
import Foundation
import MagusCore

public enum RegionCropError: Error, Sendable {
    case invalidRegion
    case croppingFailed
}

/// Découpe une portion d'image correspondant à une région normalisée.
public enum RegionCropper {
    public static func crop(image: CGImage, region: Region) throws -> CGImage {
        let imageSize = CGSize(width: image.width, height: image.height)
        let cropRect = region.bounds.absolute(in: imageSize).integral

        guard cropRect.width > 0, cropRect.height > 0 else {
            throw RegionCropError.invalidRegion
        }

        guard let cropped = image.cropping(to: cropRect) else {
            throw RegionCropError.croppingFailed
        }
        return cropped
    }
}
