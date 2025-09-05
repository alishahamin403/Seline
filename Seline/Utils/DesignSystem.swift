//
//  DesignSystem.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-24.
//

import SwiftUI

struct DesignSystem {
    
    // MARK: - Black & White Theme Colors
    struct Colors {
        
        // MARK: - Accent Colors (Black & White Theme)
        static let accent = Color.primary // Uses system primary (black in light, white in dark)
        static let accentSecondary = Color.secondary
        static let success = Color.green
        static let warning = Color.orange
        static let danger = Color.red
        
        // MARK: - Light Mode Colors (Pure Black & White)
        private static let backgroundLight = Color.white // Pure white background
        private static let surfaceLight = Color(hex: "#FAFAFA") // Very subtle off-white for cards
        private static let surfaceSecondaryLight = Color(hex: "#F8F8F8") // Even subtler for secondary surfaces
        private static let textPrimaryLight = Color.black // Pure black text
        private static let textSecondaryLight = Color(hex: "#666666") // Dark gray for secondary text
        private static let textTertiaryLight = Color(hex: "#999999") // Medium gray for tertiary text
        private static let borderLight = Color(hex: "#E0E0E0") // Light gray borders
        private static let borderSecondaryLight = Color(hex: "#F0F0F0") // Very light borders
        private static let shadowLight = Color.black.opacity(0.08) // Subtle black shadows
        
        // MARK: - Dark Mode Colors (Pure Black & White)
        private static let backgroundDark = Color.black // Pure black background
        private static let surfaceDark = Color(hex: "#1A1A1A") // Dark gray for cards
        private static let surfaceSecondaryDark = Color(hex: "#2A2A2A") // Lighter dark gray for secondary surfaces
        private static let textPrimaryDark = Color.white // Pure white text
        private static let textSecondaryDark = Color(hex: "#CCCCCC") // Light gray for secondary text
        private static let textTertiaryDark = Color(hex: "#999999") // Medium gray for tertiary text
        private static let borderDark = Color(hex: "#333333") // Dark borders
        private static let borderSecondaryDark = Color(hex: "#2A2A2A") // Subtle dark borders
        private static let shadowDark = Color.white.opacity(0.05) // Subtle white shadows for dark mode
        
        // MARK: - Adaptive Colors (Auto Light/Dark)
        static var background: Color {
            Color(UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark ? UIColor(backgroundDark) : UIColor(backgroundLight)
            })
        }
        
        static var surface: Color {
            Color(UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark ? UIColor(surfaceDark) : UIColor(surfaceLight)
            })
        }
        
        static var surfaceSecondary: Color {
            Color(UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark ? UIColor(surfaceSecondaryDark) : UIColor(surfaceSecondaryLight)
            })
        }
        
        static var textPrimary: Color {
            Color(UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark ? UIColor(textPrimaryDark) : UIColor(textPrimaryLight)
            })
        }
        
        static var textSecondary: Color {
            Color(UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark ? UIColor(textSecondaryDark) : UIColor(textSecondaryLight)
            })
        }
        
        static var textTertiary: Color {
            Color(UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark ? UIColor(textTertiaryDark) : UIColor(textTertiaryLight)
            })
        }
        
        static var border: Color {
            Color(UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark ? UIColor(borderDark) : UIColor(borderLight)
            })
        }
        
        static var borderSecondary: Color {
            Color(UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark ? UIColor(borderSecondaryDark) : UIColor(borderSecondaryLight)
            })
        }
        
        static var shadow: Color {
            Color(UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark ? UIColor(shadowDark) : UIColor(shadowLight)
            })
        }
        
        // MARK: - Button Text Colors
        /// Adaptive text color for buttons on accent backgrounds
        /// White text on light mode (accent is black), black text on dark mode (accent is white)
        static var buttonTextOnAccent: Color {
            Color(UIColor { traitCollection in
                traitCollection.userInterfaceStyle == .dark ? UIColor.black : UIColor.white
            })
        }
        
        /// Always white color for specific use cases (e.g., progress indicators on dark backgrounds)
        static var alwaysWhite: Color {
            Color.white
        }
        
        // MARK: - Black & White Gradients for Icons
        static var primaryGradient: LinearGradient {
            LinearGradient(
                colors: [
                    Color(UIColor { traitCollection in
                        traitCollection.userInterfaceStyle == .dark ? 
                        UIColor.white : UIColor.black
                    }),
                    Color(UIColor { traitCollection in
                        traitCollection.userInterfaceStyle == .dark ? 
                        UIColor(white: 0.8, alpha: 1.0) : UIColor(white: 0.4, alpha: 1.0)
                    })
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        
        static var secondaryGradient: LinearGradient {
            LinearGradient(
                colors: [
                    Color(UIColor { traitCollection in
                        traitCollection.userInterfaceStyle == .dark ? 
                        UIColor(white: 0.9, alpha: 1.0) : UIColor(white: 0.2, alpha: 1.0)
                    }),
                    Color(UIColor { traitCollection in
                        traitCollection.userInterfaceStyle == .dark ? 
                        UIColor(white: 0.7, alpha: 1.0) : UIColor(white: 0.5, alpha: 1.0)
                    })
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        
        static var tertiaryGradient: LinearGradient {
            LinearGradient(
                colors: [
                    Color(UIColor { traitCollection in
                        traitCollection.userInterfaceStyle == .dark ? 
                        UIColor(white: 0.8, alpha: 1.0) : UIColor(white: 0.3, alpha: 1.0)
                    }),
                    Color(UIColor { traitCollection in
                        traitCollection.userInterfaceStyle == .dark ? 
                        UIColor(white: 0.6, alpha: 1.0) : UIColor(white: 0.6, alpha: 1.0)
                    })
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        
    }
    
    // MARK: - Linear-Inspired Typography
    struct Typography {
        // Display & Titles
        static let display = Font.system(size: 32, weight: .bold, design: .default)
        static let title1 = Font.system(size: 28, weight: .bold, design: .default)
        static let title2 = Font.system(size: 24, weight: .bold, design: .default)
        static let title3 = Font.system(size: 20, weight: .semibold, design: .default)
        
        // Headlines & Body
        static let headline = Font.system(size: 18, weight: .semibold, design: .default)
        static let body = Font.system(size: 16, weight: .regular, design: .default)
        static let bodyMedium = Font.system(size: 16, weight: .medium, design: .default)
        static let bodySemibold = Font.system(size: 16, weight: .semibold, design: .default)
        
        // Supporting Text
        static let callout = Font.system(size: 15, weight: .regular, design: .default)
        static let calloutMedium = Font.system(size: 15, weight: .medium, design: .default)
        static let subheadline = Font.system(size: 14, weight: .regular, design: .default)
        static let subheadlineMedium = Font.system(size: 14, weight: .medium, design: .default)
        
        // Small Text
        static let footnote = Font.system(size: 13, weight: .regular, design: .default)
        static let caption = Font.system(size: 12, weight: .regular, design: .default)
        static let caption2 = Font.system(size: 11, weight: .regular, design: .default)
        
        // Special
        static let code = Font.system(size: 14, weight: .regular, design: .monospaced)
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

// MARK: - Linear-Inspired View Extensions
extension View {
    // Background Styles
    func linearBackground() -> some View {
        self.background(DesignSystem.Colors.background.ignoresSafeArea())
    }
    
    func linearSurface() -> some View {
        self.background(DesignSystem.Colors.surface)
    }
    
    func linearSurfaceSecondary() -> some View {
        self.background(DesignSystem.Colors.surfaceSecondary)
    }
    
    // Text Styles
    func textPrimary() -> some View {
        self.foregroundColor(DesignSystem.Colors.textPrimary)
    }
    
    func textSecondary() -> some View {
        self.foregroundColor(DesignSystem.Colors.textSecondary)
    }
    
    func textTertiary() -> some View {
        self.foregroundColor(DesignSystem.Colors.textTertiary)
    }
    
    func textAccent() -> some View {
        self.foregroundColor(DesignSystem.Colors.accent)
    }
    
    func textSuccess() -> some View {
        self.foregroundColor(DesignSystem.Colors.success)
    }
    
    func textWarning() -> some View {
        self.foregroundColor(DesignSystem.Colors.warning)
    }
    
    func textDanger() -> some View {
        self.foregroundColor(DesignSystem.Colors.danger)
    }
    
    // Linear-Inspired Card Styles
    func linearCard() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                    .fill(DesignSystem.Colors.surface)
                    .shadow(
                        color: DesignSystem.Colors.shadow,
                        radius: 8,
                        x: 0,
                        y: 2
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
                    )
            )
    }
    
    func linearCardSecondary() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .fill(DesignSystem.Colors.surfaceSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                            .stroke(DesignSystem.Colors.borderSecondary, lineWidth: 1)
                    )
            )
    }
    
    func linearCardInteractive() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                    .fill(DesignSystem.Colors.surface)
                    .shadow(
                        color: DesignSystem.Colors.shadow,
                        radius: 12,
                        x: 0,
                        y: 4
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
                    )
            )
    }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(DesignSystem.Colors.accent)
            .foregroundColor(DesignSystem.Colors.buttonTextOnAccent)
            .cornerRadius(10)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}