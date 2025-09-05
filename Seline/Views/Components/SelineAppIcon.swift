//
//  SelineAppIcon.swift
//  Seline
//
//  SwiftUI implementation of the Seline app icon symbol design
//

import SwiftUI

struct SelineAppIcon: View {
    let size: CGFloat
    let cornerRadius: CGFloat?
    
    init(size: CGFloat = 80, cornerRadius: CGFloat? = nil) {
        self.size = size
        self.cornerRadius = cornerRadius ?? size * 0.15 // 15% of size for rounded rectangle
    }
    
    var body: some View {
        ZStack {
            // Main cube container
            RoundedRectangle(cornerRadius: cornerRadius ?? size * 0.15)
                .stroke(iconColor, lineWidth: size * 0.075) // 6px equivalent at 80px size
                .frame(width: size, height: size)
            
            // Center "S" letter
            Text("S")
                .font(.system(size: size * 0.5, weight: .bold, design: .serif)) // Georgia equivalent
                .foregroundColor(iconColor)
            
            // Top-right indicator dot
            Circle()
                .fill(iconColor)
                .frame(width: size * 0.25, height: size * 0.25) // 20px equivalent at 80px size
                .offset(
                    x: size * 0.325, // Right edge minus dot radius
                    y: -size * 0.325  // Top edge minus dot radius
                )
        }
    }
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var iconColor: Color {
        colorScheme == .dark ? .white : .black
    }
}

// Variant for use as app icon (always high contrast)
struct SelineAppIconStatic: View {
    let size: CGFloat
    let cornerRadius: CGFloat?
    let isDarkMode: Bool
    
    init(size: CGFloat = 80, cornerRadius: CGFloat? = nil, isDarkMode: Bool = false) {
        self.size = size
        self.cornerRadius = cornerRadius ?? size * 0.15
        self.isDarkMode = isDarkMode
    }
    
    var body: some View {
        ZStack {
            // Background for app icon (if needed)
            if isDarkMode {
                RoundedRectangle(cornerRadius: cornerRadius ?? size * 0.15)
                    .fill(Color.black) // Changed from dark gray to pure black
            } else {
                RoundedRectangle(cornerRadius: cornerRadius ?? size * 0.15)
                    .fill(Color.white) // Light background
            }
            
            // Main cube container
            RoundedRectangle(cornerRadius: size * 0.12) // Slightly smaller than outer radius
                .stroke(iconColor, lineWidth: max(1.5, size * 0.075)) // Minimum 1.5px for small sizes
                .frame(width: size * 0.85, height: size * 0.85) // Slightly smaller to account for stroke
            
            // Center "S" letter
            Text("S")
                .font(.system(size: size * 0.42, weight: .bold, design: .serif))
                .foregroundColor(iconColor)
            
            // Top-right indicator dot
            Circle()
                .fill(iconColor)
                .frame(width: size * 0.2, height: size * 0.2)
                .offset(
                    x: size * 0.27,
                    y: -size * 0.27
                )
        }
    }
    
    private var iconColor: Color {
        isDarkMode ? .white : .black
    }
}

#Preview("Light Mode Icon") {
    VStack(spacing: 20) {
        SelineAppIcon(size: 120)
        SelineAppIconStatic(size: 120, isDarkMode: false)
    }
    .padding()
}

#Preview("Dark Mode Icon") {
    VStack(spacing: 20) {
        SelineAppIcon(size: 120)
        SelineAppIconStatic(size: 120, isDarkMode: true)
    }
    .padding()
    .background(Color.black)
    .preferredColorScheme(.dark)
}

#Preview("Multiple Sizes") {
    HStack(spacing: 16) {
        VStack(spacing: 8) {
            SelineAppIcon(size: 29)
            Text("29pt")
                .font(.caption2)
        }
        VStack(spacing: 8) {
            SelineAppIcon(size: 40)
            Text("40pt")
                .font(.caption2)
        }
        VStack(spacing: 8) {
            SelineAppIcon(size: 60)
            Text("60pt")
                .font(.caption2)
        }
        VStack(spacing: 8) {
            SelineAppIcon(size: 120)
            Text("120pt")
                .font(.caption2)
        }
    }
    .padding()
}