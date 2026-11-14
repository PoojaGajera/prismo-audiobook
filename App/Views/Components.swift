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
                LinearGradient(colors: [.orange, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "headphones")
                    .font(.system(size: geo.size.width * 0.38, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
    }
}

@MainActor
enum CoverCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for book: Book) -> UIImage? {
        guard let url = LibraryStore.shared.coverURL(for: book) else { return nil }
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

/// The system volume slider (controls the iPhone's actual volume).
struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.tintColor = .systemOrange
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

/// AirPlay / Bluetooth output picker.
struct RoutePickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .label
        view.activeTintColor = .systemOrange
        view.prioritizesVideoDevices = false
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

enum SkipIcon {
    static func name(back: Bool, seconds: Double) -> String {
        let n = Int(seconds)
        let base = back ? "gobackward" : "goforward"
        return [5, 10, 15, 30, 45, 60, 75, 90].contains(n) ? "\(base).\(n)" : base
    }
}
