// Linux stand-in for Core Image: enough for the EXIF orientation bake.
import CoreGraphics

public class CIImage {
    public var extent: CGRect = CGRect(x: 0, y: 0, width: 0, height: 0)
    public init(cgImage: CGImage) { self.extent = CGRect(x: 0, y: 0, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)) }
    public func oriented(_ orientation: CGImagePropertyOrientation) -> CIImage { self }
}

public final class CIContext: Sendable {
    public init(options: [String: Any]?) {}
    public func createCGImage(_ image: CIImage, from rect: CGRect) -> CGImage? { CGImage() }
}
