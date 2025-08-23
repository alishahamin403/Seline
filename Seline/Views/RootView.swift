//
//  RootView.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-24.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var authService: AuthenticationService
    @State private var showingSplash = true
    
    var body: some View {
        Group {
            if showingSplash {
                SplashView()
                    .onAppear {
                        // Show splash for a brief moment, then check auth state
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                showingSplash = false
                            }
                        }
                    }
            } else {
                if authService.isAuthenticated {
                    MainAppView()
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    OnboardingView()
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .animation(.easeInOut(duration: 0.5), value: authService.isAuthenticated)
        .animation(.easeInOut(duration: 0.5), value: showingSplash)
    }
}

// MARK: - Splash View

struct SplashView: View {
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0.0
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            // App Icon
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                .fill(DesignSystem.Colors.accent.gradient)
                .frame(width: 120, height: 120)
                .overlay(
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.white)
                )
                .scaleEffect(scale)
                .opacity(opacity)
                .shadow(color: DesignSystem.Shadow.medium, radius: 20, x: 0, y: 10)
            
            // App Name
            Text("Seline")
                .font(DesignSystem.Typography.title1)
                .primaryText()
                .opacity(opacity)
            
            // Loading Indicator
            VStack(spacing: DesignSystem.Spacing.sm) {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(DesignSystem.Colors.accent)
                
                Text("Loading...")
                    .font(DesignSystem.Typography.footnote)
                    .secondaryText()
            }
            .opacity(opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .designSystemBackground()
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                scale = 1.0
                opacity = 1.0
            }
        }
    }
}

// MARK: - Main App View

struct MainAppView: View {
    @EnvironmentObject private var authService: AuthenticationService
    @State private var showingSettings = false
    
    var body: some View {
        ContentView()
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
    }
}


struct SettingsView: View {
    @EnvironmentObject private var authService: AuthenticationService
    
    var body: some View {
        NavigationView {
            VStack(spacing: DesignSystem.Spacing.lg) {
                // User Profile Section
                if let user = authService.user {
                    VStack(spacing: DesignSystem.Spacing.md) {
                        Circle()
                            .fill(DesignSystem.Colors.accent.gradient)
                            .frame(width: 80, height: 80)
                            .overlay(
                                Text(String(user.name.prefix(1)))
                                    .font(.title)
                                    .foregroundColor(.white)
                            )
                        
                        VStack(spacing: 4) {
                            Text(user.name)
                                .font(DesignSystem.Typography.headline)
                                .primaryText()
                            
                            Text(user.email)
                                .font(DesignSystem.Typography.subheadline)
                                .secondaryText()
                        }
                    }
                    .padding(DesignSystem.Spacing.lg)
                    .cardStyle()
                }
                
                // Settings Options
                VStack(spacing: 0) {
                    SettingsRow(
                        icon: "bell.fill",
                        title: "Notifications",
                        action: {}
                    )
                    
                    Divider()
                        .padding(.leading, 50)
                    
                    SettingsRow(
                        icon: "paintbrush.fill",
                        title: "Appearance",
                        action: {}
                    )
                    
                    Divider()
                        .padding(.leading, 50)
                    
                    SettingsRow(
                        icon: "shield.fill",
                        title: "Privacy",
                        action: {}
                    )
                    
                    Divider()
                        .padding(.leading, 50)
                    
                    SettingsRow(
                        icon: "questionmark.circle.fill",
                        title: "Help & Support",
                        action: {}
                    )
                }
                .cardStyle()
                
                // Sign Out
                Button(action: {
                    Task {
                        await authService.signOut()
                    }
                }) {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(.red)
                        
                        Text("Sign Out")
                            .font(DesignSystem.Typography.bodyMedium)
                            .foregroundColor(.red)
                        
                        Spacer()
                    }
                    .padding(DesignSystem.Spacing.md)
                    .cardStyle()
                }
                
                Spacer()
            }
            .padding(DesignSystem.Spacing.md)
            .designSystemBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.md) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(DesignSystem.Colors.accent)
                    .frame(width: 24, height: 24)
                
                Text(title)
                    .font(DesignSystem.Typography.body)
                    .primaryText()
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(DesignSystem.Colors.systemTextSecondary)
            }
            .padding(DesignSystem.Spacing.md)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            RootView()
                .environmentObject(AuthenticationService.shared)
                .previewDisplayName("Root View")
            
            SplashView()
                .previewDisplayName("Splash")
            
            MainAppView()
                .environmentObject(AuthenticationService.shared)
                .previewDisplayName("Main App")
        }
    }
}