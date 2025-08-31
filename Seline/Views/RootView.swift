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
                        // Debug authentication state during splash
                        debugAuthenticationState()
                        
                        // Check for persistent authentication
                        let hasPersistentAuth = authService.checkPersistentAuthentication()
                        print("🔐 Persistent auth available: \(hasPersistentAuth)")
                        
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
                        .onAppear {
                            print("🏠 DISPLAYING: MainAppView (user is authenticated)")
                            debugViewSelection()
                        }
                } else {
                    OnboardingView()
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .onAppear {
                            print("👋 DISPLAYING: OnboardingView (user not authenticated)")
                            debugViewSelection()
                        }
                }
            }
        }
        .animation(.easeInOut(duration: 0.5), value: authService.isAuthenticated)
        .animation(.easeInOut(duration: 0.5), value: showingSplash)
        .onReceive(authService.$isAuthenticated) { isAuth in
            print("🔄 AUTHENTICATION STATE CHANGED: \(isAuth)")
            debugAuthenticationState()
        }
    }
    
    // MARK: - Debug Methods
    
    private func debugAuthenticationState() {
        print("🔍 AUTHENTICATION DEBUG:")
        print("  - isAuthenticated: \(authService.isAuthenticated)")
        print("  - user: \(authService.user?.email ?? "nil")")
        print("  - authError: \(authService.authError ?? "nil")")
        print("  - isLoading: \(authService.isLoading)")
        
        // Check UserDefaults directly
        let storedAuthState = UserDefaults.standard.bool(forKey: "seline_auth_state")
        let hasUserData = UserDefaults.standard.data(forKey: "seline_user") != nil
        print("  - UserDefaults.authState: \(storedAuthState)")
        print("  - UserDefaults.userData: \(hasUserData)")
    }
    
    private func debugViewSelection() {
        print("🎯 VIEW SELECTION DEBUG:")
        print("  - showingSplash: \(showingSplash)")
        print("  - authService.isAuthenticated: \(authService.isAuthenticated)")
        print("  - Will show: \(authService.isAuthenticated ? "MainAppView" : "OnboardingView")")
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
                .textPrimary()
                .opacity(opacity)
            
            // Loading Indicator
            VStack(spacing: DesignSystem.Spacing.sm) {
                ProgressView()
                    .scaleEffect(0.8)
                    .tint(DesignSystem.Colors.accent)
                
                Text("Loading...")
                    .font(DesignSystem.Typography.footnote)
                    .textSecondary()
            }
            .opacity(opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .linearBackground()
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
                                .textPrimary()
                            
                            Text(user.email)
                                .font(DesignSystem.Typography.subheadline)
                                .textSecondary()
                        }
                    }
                    .padding(DesignSystem.Spacing.lg)
                    .linearCard()
                }
                
                // Settings Options
                VStack(spacing: 0) {
                    SettingsRow(
                        icon: "bell.fill",
                        title: "Notifications",
                        subtitle: "Email alerts and updates",
                        iconColor: .red,
                        action: {
                            // Handle notifications
                        }
                    )
                    
                    Divider()
                        .padding(.leading, 50)
                    
                    SettingsRow(
                        icon: "paintbrush.fill",
                        title: "Appearance",
                        subtitle: "Theme and display",
                        iconColor: .purple,
                        action: {
                            // Handle appearance
                        }
                    )
                    
                    Divider()
                        .padding(.leading, 50)
                    
                    SettingsRow(
                        icon: "shield.fill",
                        title: "Privacy",
                        subtitle: "Data protection",
                        iconColor: .green,
                        action: {
                            // Handle privacy
                        }
                    )
                    
                    Divider()
                        .padding(.leading, 50)
                    
                    SettingsRow(
                        icon: "questionmark.circle.fill",
                        title: "Help & Support",
                        subtitle: "Get assistance",
                        iconColor: .blue,
                        action: {
                            // Handle help
                        }
                    )
                }
                .linearCard()
                
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
                    .linearCard()
                }
                
                Spacer()
            }
            .padding(DesignSystem.Spacing.md)
            .linearBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
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