import SwiftUI

#if canImport(UIKit)
    import UIKit

    /// Last-frame hold across a media URL swap (timeshift scrub commit, channel
    /// surf, episode change). Metal / sample-buffer surfaces often clear to black
    /// the moment the engine replaces its source; a SwiftUI image overlay keeps
    /// the outgoing picture up until the replacement paints its first frame.
    enum PlayerFreezeFrame {
        /// Full-bleed fit overlay that matches the video letterbox.
        struct Overlay: View {
            let image: UIImage

            var body: some View {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }

        /// Prefer a decoded `CGImage` (KSPlayer pixel buffer) over view snapshots.
        static func fromCGImage(_ cgImage: CGImage) -> UIImage? {
            let image = UIImage(cgImage: cgImage)
            return isMostlyBlack(image) ? nil : image
        }

        /// Snapshot a UIKit host. Rejects near-black results so a failed capture
        /// never freezes the black flash itself.
        static func capture(view: UIView) -> UIImage? {
            guard view.bounds.width > 1, view.bounds.height > 1 else { return nil }
            let format = UIGraphicsImageRendererFormat()
            format.scale = view.window?.screen.scale ?? UIScreen.main.scale
            format.opaque = true
            let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { _ in
                view.drawHierarchy(in: view.bounds, afterScreenUpdates: false)
            }
            return isMostlyBlack(image) ? nil : image
        }

        /// Snapshot a bare `CALayer` (AVPlayerLayer / AVSampleBufferDisplayLayer).
        static func capture(layer: CALayer) -> UIImage? {
            guard layer.bounds.width > 1, layer.bounds.height > 1 else { return nil }
            let format = UIGraphicsImageRendererFormat()
            format.scale = UIScreen.main.scale
            format.opaque = true
            let size = layer.bounds.size
            let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                layer.render(in: context.cgContext)
            }
            return isMostlyBlack(image) ? nil : image
        }

        /// Downsample to 8×8 and reject frames whose mean luminance is near zero.
        static func isMostlyBlack(_ image: UIImage, threshold: Double = 0.06) -> Bool {
            guard let cgImage = image.cgImage, cgImage.width > 2, cgImage.height > 2 else {
                return true
            }
            let side = 8
            var pixels = [UInt8](repeating: 0, count: side * side * 4)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let context = CGContext(
                data: &pixels,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return true
            }
            context.interpolationQuality = .low
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
            var total = 0
            for index in stride(from: 0, to: pixels.count, by: 4) {
                total += Int(pixels[index]) + Int(pixels[index + 1]) + Int(pixels[index + 2])
            }
            let average = Double(total) / Double(side * side * 3) / 255.0
            return average < threshold
        }
    }
#endif
