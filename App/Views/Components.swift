import SwiftUI
import UIKit
import MediaPlayer
import AVKit

/// Square cover art, or a generated placeholder.
struct CoverView: View {
    let book: Book
    var cornerRadius: CGFloat = 8

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image = CoverCache.image(for: book) {
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

    static func image(for book: Book) -> UIImage? {
        guard let url = LibraryStore.shared.coverURL(for: book) else { return nil }
        let key = "\(url.path)#\(book.coverVersion ?? 0)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: key)
        return image
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

