//
//  DesignSystem.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-24.
//

import SwiftUI

struct DesignSystem {
    
    // MARK: - Colors
    struct Colors {
        
        // MARK: - System Adaptive Colors (automatically switch with system appearance)
        static let systemBackground = Color(UIColor.systemBackground)
        static let systemSecondaryBackground = Color(UIColor.secondarySystemBackground)
        static let systemTextPrimary = Color(UIColor.label)
        static let systemTextSecondary = Color(UIColor.secondaryLabel)
        static let systemBorder = Color(UIColor.separator)
        
        // MARK: - Accent Colors
        static let accent = Color(hex: "#2383E2") // Notion blue
        
        // MARK: - Static Colors (for direct usage)
        static let notionBlue = Color(hex: "#2383E2")
        
        // MARK: - Manual Light/Dark Colors (for when you need specific control)
        static let backgroundLight = Color(hex: "#FFFFFF")
        static let secondaryBackgroundLight = Color(hex: "#F7F6F3")
        static let textPrimaryLight = Color(hex: "#37352F")
        static let textSecondaryLight = Color(hex: "#787774")
        static let borderLight = Color(hex: "#E9E9E7")
        
        static let backgroundDark = Color(hex: "#191919")
        static let secondaryBackgroundDark = Color(hex: "#2F2F2F")
        static let textPrimaryDark = Color(hex: "#FFFFFF")
        static let textSecondaryDark = Color(hex: "#9B9A97")
        static let borderDark = Color(hex: "#373737")
        
        // MARK: - Smart Adaptive Colors
        static var adaptiveBackground: Color {
            Color(UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark ? UIColor(backgroundDark) : UIColor(backgroundLight)
            })
        }
        
        static var adaptiveSecondaryBackground: Color {
            Color(UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark ? UIColor(secondaryBackgroundDark) : UIColor(secondaryBackgroundLight)
            })
        }
        
        static var adaptiveTextPrimary: Color {
            Color(UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark ? UIColor(textPrimaryDark) : UIColor(textPrimaryLight)
            })
        }
        
        static var adaptiveTextSecondary: Color {
            Color(UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark ? UIColor(textSecondaryDark) : UIColor(textSecondaryLight)
            })
        }
        
        static var adaptiveBorder: Color {
            Color(UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark ? UIColor(borderDark) : UIColor(borderLight)
            })
        }
    }
    
    // MARK: - Typography
    struct Typography {
        static let title1 = Font.system(size: 28, weight: .bold, design: .default)
        static let title2 = Font.system(size: 22, weight: .bold, design: .default)
        static let title3 = Font.system(size: 20, weight: .semibold, design: .default)
        static let headline = Font.system(size: 17, weight: .semibold, design: .default)
        static let body = Font.system(size: 17, weight: .regular, design: .default)
        static let bodyMedium = Font.system(size: 17, weight: .medium, design: .default)
        static let callout = Font.system(size: 16, weight: .regular, design: .default)
        static let subheadline = Font.system(size: 15, weight: .regular, design: .default)
        static let footnote = Font.system(size: 13, weight: .regular, design: .default)
        static let caption = Font.system(size: 12, weight: .regular, design: .default)
        static let caption2 = Font.system(size: 11, weight: .regular, design: .default)
    }
    
    // MARK: - Spacing
    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }
    
    // MARK: - Corner Radius
    struct CornerRadius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let circle: CGFloat = 50
    }
    
    // MARK: - Shadow
    struct Shadow {
        static let light = Color.black.opacity(0.1)
        static let medium = Color.black.opacity(0.15)
        static let heavy = Color.black.opacity(0.25)
    }
}

// MARK: - Color Extension for Hex Support
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - View Extensions for Design System
extension View {
    func designSystemBackground() -> some View {
        self.background(DesignSystem.Colors.systemBackground)
    }
    
    func designSystemSecondaryBackground() -> some View {
        self.background(DesignSystem.Colors.systemSecondaryBackground)
    }
    
    func primaryText() -> some View {
        self.foregroundColor(DesignSystem.Colors.systemTextPrimary)
    }
    
    func secondaryText() -> some View {
        self.foregroundColor(DesignSystem.Colors.systemTextSecondary)
    }
    
    func accentColor() -> some View {
        self.foregroundColor(DesignSystem.Colors.accent)
    }
    
    func cardStyle() -> some View {
        self
            .background(DesignSystem.Colors.systemSecondaryBackground)
            .cornerRadius(DesignSystem.CornerRadius.md)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .stroke(DesignSystem.Colors.systemBorder, lineWidth: 1)
            )
    }
}