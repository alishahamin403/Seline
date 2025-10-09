import SwiftUI
import Foundation

/// Manages image caching to reduce network egress and improve performance
class ImageCacheManager {
    static let shared = ImageCacheManager()

    private let cache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    private init() {
        // Set up cache directory
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("ImageCache")

        // Create directory if it doesn't exist
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Configure memory cache
        cache.countLimit = 100 // Max 100 images in memory
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB max
    }

    /// Get cached image or download it
    func getImage(url: String) async -> UIImage? {
        let key = url as NSString

        // Check memory cache first
        if let cachedImage = cache.object(forKey: key) {
            print("📦 Loaded image from memory cache: \(url.suffix(30))")
            return cachedImage
        }

        // Check disk cache
        let filename = url.hash.description
        let fileURL = cacheDirectory.appendingPathComponent(filename)

        if let imageData = try? Data(contentsOf: fileURL),
           let image = UIImage(data: imageData) {
            cache.setObject(image, forKey: key)
            print("💾 Loaded image from disk cache: \(url.suffix(30))")
            return image
        }

        // Download image
        guard let imageURL = URL(string: url) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: imageURL)
            guard let image = UIImage(data: data) else { return nil }

            // Save to memory cache
            cache.setObject(image, forKey: key)

            // Save to disk cache
            try? data.write(to: fileURL)

            print("🌐 Downloaded and cached image: \(url.suffix(30))")
            return image
        } catch {
            print("❌ Failed to download image: \(error)")
            return nil
        }
    }

    /// Clear all cached images
    func clearCache() {
        cache.removeAllObjects()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        print("🗑️ Cleared image cache")
    }

    /// Get cache size in MB
    func getCacheSize() -> Double {
        guard let contents = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }

        let totalBytes = contents.compactMap { url -> Int64? in
            try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init)
        }.reduce(0, +)

        return Double(totalBytes) / 1_024 / 1_024 // Convert to MB
    }
}

/// SwiftUI AsyncImage replacement with caching
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: String
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let image = image {
                content(Image(uiImage: image))
            } else {
                placeholder()
                    .onAppear {
                        loadImage()
                    }
            }
        }
    }

    private func loadImage() {
        guard !isLoading else { return }
        isLoading = true

        Task {
            let loadedImage = await ImageCacheManager.shared.getImage(url: url)
            await MainActor.run {
                self.image = loadedImage
                self.isLoading = false
            }
        }
    }
}

// Convenience initializer
extension CachedAsyncImage where Placeholder == ShadcnSpinner {
    init(url: String, @ViewBuilder content: @escaping (Image) -> Content) {
        self.url = url
        self.content = content
        self.placeholder = { ShadcnSpinner(size: .small) }
    }
}
