import Foundation
import CoreGraphics
import ImageIO

/// Decides which metadata dictionaries survive into the encoded file.
enum MetadataPolicy {

    struct Payload {
        var exif: [CFString: Any]?
        var tiff: [CFString: Any]?
        var gps: [CFString: Any]?
        var iptc: [CFString: Any]?
        var eightBIM: [CFString: Any]?
    }

    // The orientation tag carries the same literal name in the EXIF and TIFF
    // dictionaries, and ImageIO exposes it as kCGImagePropertyTIFFOrientation.
    private enum Tag {
        static let orientation = kCGImagePropertyTIFFOrientation
        static let geographic = ["GPS", "LATITUDE", "LON as CFStringGITUDE", "ALTITUDE"]
    }

    static func payload(
        from properties: [CFString: Any]?,
        keepMetadata: Bool,
        stripLocation: Bool
    ) -> Payload? {
        guard keepMetadata, let properties else { return nil }

        var exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        var tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]

        // Orientation is already baked into the pixels, so the tag has to go —
        // otherwise viewers rotate the image a second time.
        exif.removeValue(forKey: Tag.orientation)
        tiff.removeValue(forKey: Tag.orientation)

        var gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any]
        if stripLocation {
            gps = nil
            exif = exif.filter { !isGeographic($0.key) }
            tiff = tiff.filter { !isGeographic($0.key) }
        }

        let iptc = properties[kCGImagePropertyIPTCDictionary] as? [CFString: Any]
        let eightBIM = properties[kCGImageProperty8BIMDictionary] as? [CFString: Any]

        return Payload(
            exif: exif.isEmpty ? nil : exif,
            tiff: tiff.isEmpty ? nil : tiff,
            gps: (gps?.isEmpty ?? true) ? nil : gps,
            iptc: (iptc?.isEmpty ?? true) ? nil : iptc,
            eightBIM: (eightBIM?.isEmpty ?? true) ? nil : eightBIM
        )
    }

    private static func isGeographic(_ key: CFString) -> Bool {
        let name = (key as String).uppercased()
        return Tag.geographic.contains { name.contains($0) }
    }
}
