//
//  IconGenerator.swift
//  Seline
//
//  Utility for generating app icon representations
//

import SwiftUI
import UIKit

struct IconGenerator {
    
    /// Creates a UIImage representation of the Seline app icon
    static func createIcon(size: CGSize, isDark: Bool = false) -> UIImage? {
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            // Create the SwiftUI view
            let hostingController = UIHostingController(
                rootView: SelineAppIconStatic(
                    size: min(size.width, size.height),
                    cornerRadius: size.width * 0.15,
                    isDarkMode: isDark
                )
                .frame(width: size.width, height: size.height)
                .background(isDark ? Color.black : Color.white)
            )
            
            hostingController.view.frame = CGRect(origin: .zero, size: size)
            hostingController.view.backgroundColor = isDark ? UIColor.black : UIColor.white
            
            // Render the view
            hostingController.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
        }
    }
    
    /// Generate all required app icon sizes
    static func generateAllIcons() -> [String: UIImage] {
        var icons: [String: UIImage] = [:]
        
        let iconSizes: [(String, CGFloat)] = [
            ("AppIcon-20", 40),      // 20pt @2x
            ("AppIcon-20@3x", 60),   // 20pt @3x
            ("AppIcon-29", 58),      // 29pt @2x
            ("AppIcon-29@3x", 87),   // 29pt @3x
            ("AppIcon-40", 80),      // 40pt @2x
            ("AppIcon-40@3x", 120),  // 40pt @3x
            ("AppIcon-60@2x", 120),  // 60pt @2x
            ("AppIcon-60@3x", 180),  // 60pt @3x
            ("AppIcon-20-ipad", 20), // iPad 20pt @1x
            ("AppIcon-20@2x-ipad", 40), // iPad 20pt @2x
            ("AppIcon-29-ipad", 29), // iPad 29pt @1x
            ("AppIcon-29@2x-ipad", 58), // iPad 29pt @2x
            ("AppIcon-40-ipad", 40), // iPad 40pt @1x
            ("AppIcon-40@2x-ipad", 80), // iPad 40pt @2x
            ("AppIcon-76", 76),      // iPad 76pt @1x
            ("AppIcon-76@2x", 152),  // iPad 76pt @2x
            ("AppIcon-83.5@2x", 167), // iPad Pro 83.5pt @2x
            ("AppIcon-1024", 1024)   // App Store
        ]
        
        for (name, size) in iconSizes {
            let cgSize = CGSize(width: size, height: size)
            if let icon = createIcon(size: cgSize, isDark: false) {
                icons[name] = icon
            }
        }
        
        return icons
    }
    
    /// Save an icon to the app bundle (for development/testing)
    static func saveIconForTesting(name: String, image: UIImage) {
        guard let data = image.pngData() else { return }
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let iconPath = documentsPath.appendingPathComponent("\(name).png")
        
        try? data.write(to: iconPath)
        print("📱 Generated test icon: \(iconPath.absoluteString)")
    }
}

// MARK: - SwiftUI Preview for Icon Testing

struct IconGeneratorPreview: View {
    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                ForEach([(20, "20pt"), (29, "29pt"), (40, "40pt"), (60, "60pt"), (76, "76pt"), (83.5, "83.5pt")], id: \.0) { size, label in
                    VStack(spacing: 8) {
                        SelineAppIcon(size: CGFloat(size))
                            .frame(width: CGFloat(size), height: CGFloat(size))
                        
                        Text(label)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Icon Sizes")
    }
}

#Preview {
    NavigationView {
        IconGeneratorPreview()
    }
}