import SwiftUI
import UIKit
import MediaPlayer
import AVKit
import ImageIO

/// Square cover art, or a generated placeholder.
struct CoverView: View {
    let book: Book
    var cornerRadius: CGFloat = 8
    /// The full-resolution cover (player, details). Otherwise a lighter copy is used, which is
    /// plenty for library cards and keeps memory down with many books.
    var fullSize = false

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = CoverCache.image(for: book, fullSize: fullSize) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholder
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        GeometryReader { geo in
            ZStack {
                Theme.coverPlaceholder
                MascotView(size: geo.size.width * 0.7, headphones: true, animated: false)
                    .shadow(color: Theme.mascotBlue.opacity(0.25), radius: geo.size.width * 0.05, y: geo.size.width * 0.03)
            }
        }
    }
}

@MainActor
enum CoverCache {
    private static let cache = NSCache<NSString, UIImage>()
    /// Longest side of the lighter copy used on library cards (a tile is ~170 pt = ~510 px).
    static let cardPixels: CGFloat = 640

    static func image(for book: Book, fullSize: Bool = true) -> UIImage? {
        guard let url = LibraryStore.shared.coverURL(for: book) else { return nil }
        let key = "\(url.path)#\(book.coverVersion ?? 0)#\(fullSize ? "full" : "card")" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = fullSize ? UIImage(contentsOfFile: url.path) : downsampled(url, maxPixels: cardPixels)
        guard let image else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Decodes a smaller copy straight from the file, without loading the full image first.
    private static func downsampled(_ url: URL, maxPixels: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// The system volume slider (controls the iPhone's actual volume).
struct SystemVolumeSlider: UIViewRepresentable {
    var tint: UIColor = Theme.uiAccent

    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.tintColor = tint
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        uiView.tintColor = tint
    }
}

/// AirPlay / Bluetooth output picker.
struct RoutePickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .label
        view.activeTintColor = Theme.uiAccent
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

