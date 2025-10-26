import SwiftUI
import UIKit
import CoreGraphics

// Simple k-means palette extractor with in-memory caching.
// Produces up to K swatches ordered by descending weight.
enum PaletteExtractor {
    private static let K = 4
    private static let iterations = 8
    private static let maxEdge: CGFloat = 64
    private static var cache = NSCache<NSString, NSArray>() // urlString -> [UIColor]

    static func palette(fromURL urlString: String?) async -> [UIColor]? {
        guard let urlString, let url = URL(string: urlString) else { return nil }
        if let cached = cache.object(forKey: urlString as NSString) as? [UIColor] { return cached }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let img = UIImage(data: data) else { return nil }
            let colors = extract(from: img, k: K, iterations: iterations)
            cache.setObject(colors as NSArray, forKey: urlString as NSString)
            return colors
        } catch {
            return nil
        }
    }

    // MARK: - Core

    static func extract(from image: UIImage, k: Int, iterations: Int) -> [UIColor] {
        guard let cg = downscale(image: image, maxEdge: maxEdge) else { return [.black, .darkGray, .gray, .white] }
        guard let providerData = cg.dataProvider?.data,
              let base = CFDataGetBytePtr(providerData)
        else { return [.black, .darkGray, .gray, .white] }

        let w = cg.width
        let h = cg.height
        let step = 4
        let rowStride = cg.bytesPerRow   // ← renamed to avoid shadowing Swift's stride()

        var samples: [(r: Float, g: Float, b: Float)] = []
        samples.reserveCapacity((w * h) / 4)

        // Subsample pixels (every 2px) and ignore very transparent ones
        let skip = 2
        for y in Swift.stride(from: 0, to: h, by: skip) {
            for x in Swift.stride(from: 0, to: w, by: skip) {
                let p = y * rowStride + x * step
                let a = Double(base[p+3]) / 255.0
                guard a > 0.2 else { continue }
                // Use Double pow, then cast to Float for storage
                let r = pow(Double(base[p+0]) / 255.0, 2.2)
                let g = pow(Double(base[p+1]) / 255.0, 2.2)
                let b = pow(Double(base[p+2]) / 255.0, 2.2)
                samples.append((Float(r), Float(g), Float(b)))
            }
        }
        guard !samples.isEmpty else { return [.black, .darkGray, .gray, .white] }

        // Initialize centroids with k-means++ style picks
        var centroids: [(Float,Float,Float)] = []
        centroids.append(samples[Int.random(in: 0..<samples.count)])
        while centroids.count < k {
            var dists = [Float](repeating: 0, count: samples.count)
            for (i, s) in samples.enumerated() {
                var best: Float = .greatestFiniteMagnitude
                for c in centroids {
                    let d = dist2(s, c)
                    if d < best { best = d }
                }
                dists[i] = best
            }
            let sum = dists.reduce(0,+)
            guard sum > 0 else { break }
            var r = Float.random(in: 0..<sum)
            var chosen = samples[0]
            for (i, d) in dists.enumerated() {
                r -= d
                if r <= 0 { chosen = samples[i]; break }
            }
            centroids.append(chosen)
        }

        // Lloyd iterations
        for _ in 0..<iterations {
            var sums = Array(repeating: (0 as Float, 0 as Float, 0 as Float, 0 as Float), count: centroids.count)
            for s in samples {
                var bestI = 0; var best: Float = .greatestFiniteMagnitude
                for (i,c) in centroids.enumerated() {
                    let d = dist2(s, c)
                    if d < best { best = d; bestI = i }
                }
                sums[bestI].0 += s.0; sums[bestI].1 += s.1; sums[bestI].2 += s.2; sums[bestI].3 += 1
            }
            for i in 0..<centroids.count {
                let n = max(sums[i].3, 1)
                centroids[i] = (sums[i].0 / n, sums[i].1 / n, sums[i].2 / n)
            }
        }

        // Weights & sort
        var counts = Array(repeating: 0, count: centroids.count)
        for s in samples {
            var bestI = 0; var best: Float = .greatestFiniteMagnitude
            for (i,c) in centroids.enumerated() {
                let d = dist2(s, c)
                if d < best { best = d; bestI = i }
            }
            counts[bestI] += 1
        }
        let ordered = centroids.enumerated().sorted { counts[$0.offset] > counts[$1.offset] }.map { $0.element }

        // Convert to UIColor (gamma correct back)
        let uis: [UIColor] = ordered.map { (r,g,b) in
            let R = CGFloat(pow(Double(r), 1/2.2))
            let G = CGFloat(pow(Double(g), 1/2.2))
            let B = CGFloat(pow(Double(b), 1/2.2))
            return UIColor(red: R, green: G, blue: B, alpha: 1)
        }
        return uis
    }

    private static func dist2(_ a: (Float,Float,Float), _ b: (Float,Float,Float)) -> Float {
        let dr = a.0 - b.0, dg = a.1 - b.1, db = a.2 - b.2
        return dr*dr + dg*dg + db*db
    }

    private static func downscale(image: UIImage, maxEdge: CGFloat) -> CGImage? {
        let size = image.size
        let scale = max(size.width, size.height) > maxEdge ? (maxEdge / max(size.width, size.height)) : 1
        let dst = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false
        let img = UIGraphicsImageRenderer(size: dst, format: fmt).image { _ in
            image.draw(in: CGRect(origin: .zero, size: dst))
        }
        return img.cgImage
    }
}
