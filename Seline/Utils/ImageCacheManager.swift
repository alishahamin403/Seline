import SwiftUI
import Foundation

/// Manages image caching to reduce network egress and improve performance
class ImageCacheManager {
    static let shared = ImageCacheManager()

    private let cache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    // Disk cache limits
    private let maxDiskCacheSize: Int64 = 500 * 1024 * 1024 // 500 MB max disk cache
    private let targetDiskCacheSize: Int64 = 400 * 1024 * 1024 // Clean to 400 MB when exceeded

    private init() {
        // Set up cache directory
        let paths = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)
        cacheDirectory = paths[0].appendingPathComponent("ImageCache")

        // Create directory if it doesn't exist
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Configure memory cache
        cache.countLimit = 100 // Max 100 images in memory
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB max

        // Check and clean disk cache if needed on init
        Task {
            await cleanDiskCacheIfNeeded()
        }
    }

    /// Get cached image or download it
    func getImage(url: String) async -> UIImage? {
        let key = url as NSString

        // Check memory cache first
        if let cachedImage = cache.object(forKey: key) {
            return cachedImage
        }

        // Check disk cache
        let filename = url.hash.description
        let fileURL = cacheDirectory.appendingPathComponent(filename)

        if let imageData = try? Data(contentsOf: fileURL),
           let image = UIImage(data: imageData) {
            cache.setObject(image, forKey: key)
            return image
        }

        // Download image
        guard let imageURL = URL(string: url) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: imageURL)
            guard let image = UIImage(data: data) else { return nil }

            // Optimize image before caching (resize to max 1024x1024 for performance)
            let optimizedImage = await optimizeImage(image)

            // Save to memory cache
            cache.setObject(optimizedImage, forKey: key)

            // Save optimized image to disk cache
            if let optimizedData = optimizedImage.jpegData(compressionQuality: 0.8) {
                try? optimizedData.write(to: fileURL)

                // Clean disk cache if it exceeds limit
                await cleanDiskCacheIfNeeded()
            }

            print("🌐 Downloaded and cached image: \(url.suffix(30))")
            return optimizedImage
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

    /// Get image cache size in MB
    func getCacheSize() -> Double {
        guard let contents = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }

        let totalBytes = contents.compactMap { url -> Int64? in
            try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init)
        }.reduce(0, +)

        return Double(totalBytes) / 1_024 / 1_024 // Convert to MB
    }

    /// Get total cache size including tasks cache (in MB)
    func getTotalCacheSize() -> Double {
        let imageCache = getCacheSize()
        let taskCache = getTaskCacheSize()
        return imageCache + taskCache
    }

    /// Optimize image for caching (resize and compress)
    private func optimizeImage(_ image: UIImage) async -> UIImage {
        let maxDimension: CGFloat = 1024 // Max width or height

        // Check if image needs resizing
        let size = image.size
        if size.width <= maxDimension && size.height <= maxDimension {
            return image // Already small enough
        }

        // Calculate new size maintaining aspect ratio
        let ratio = size.width / size.height
        let newSize: CGSize
        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / ratio)
        } else {
            newSize = CGSize(width: maxDimension * ratio, height: maxDimension)
        }

        // Resize image on background thread to avoid blocking main thread
        return await Task.detached(priority: .userInitiated) {
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return resizedImage ?? image
        }.value
    }

    /// Clean disk cache if it exceeds the maximum size
    private func cleanDiskCacheIfNeeded() async {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        ) else {
            return
        }

        // Calculate total cache size
        let filesWithMetadata = contents.compactMap { url -> (url: URL, size: Int64, date: Date)? in
            guard let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let size = resourceValues.fileSize,
                  let date = resourceValues.contentModificationDate else {
                return nil
            }
            return (url, Int64(size), date)
        }

        let totalSize = filesWithMetadata.reduce(Int64(0)) { $0 + $1.size }

        // Check if cleanup is needed
        guard totalSize > maxDiskCacheSize else {
            return
        }

        print("🗑️ Disk cache exceeded \(maxDiskCacheSize / 1024 / 1024)MB, cleaning up...")

        // Sort by date (oldest first)
        let sortedFiles = filesWithMetadata.sorted { $0.date < $1.date }

        // Delete oldest files until we reach target size
        var currentSize = totalSize
        for file in sortedFiles {
            if currentSize <= targetDiskCacheSize {
                break
            }

            try? fileManager.removeItem(at: file.url)
            currentSize -= file.size
            print("🗑️ Deleted cached image: \(file.url.lastPathComponent)")
        }

        print("✅ Disk cache cleaned to \(currentSize / 1024 / 1024)MB")
    }

    /// Get task cache size from UserDefaults (in MB)
    private func getTaskCacheSize() -> Double {
        if let savedTasks = UserDefaults.standard.data(forKey: "SavedTasks") {
            return Double(savedTasks.count) / 1_024 / 1_024 // Convert bytes to MB
        }
        return 0
    }

    /// Clear both image and task caches
    func clearAllCaches() {
        // Clear image cache
        cache.removeAllObjects()
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Clear task cache
        UserDefaults.standard.removeObject(forKey: "SavedTasks")

        print("🗑️ Cleared all caches (images + tasks)")
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
