//
//  OnboardingView.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-24.
//

import SwiftUI

struct OnboardingView: View {
    @StateObject private var authService = AuthenticationService.shared
    @StateObject private var googleAuth = GoogleOAuthService.shared
    @State private var isAuthenticating = false
    @State private var showingPermissions = false
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 120)
            
            // Main heading with friendly tone
            VStack(spacing: DesignSystem.Spacing.lg) {
                Text(authService.hasCompletedOnboarding ? "Welcome back!" : "Let's organize your emails")
                    .font(.system(size: 32, weight: .medium, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                
                Text(authService.hasCompletedOnboarding ? "Sign in to continue" : "Connect your Gmail to get started")
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, DesignSystem.Spacing.xl)
            
            Spacer(minLength: 100)
            
            // Simple Google sign in button
            Button(action: {
                Task {
                    await performGoogleSignIn()
                }
            }) {
                HStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "globe")
                        .font(.title2)
                        .foregroundColor(.white)
                    
                    Text("Continue with Google")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black)
                )
            }
            .disabled(isAuthenticating || googleAuth.isAuthenticating)
            .padding(.horizontal, DesignSystem.Spacing.xl)
            
            // Loading state
            if isAuthenticating || googleAuth.isAuthenticating {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(DesignSystem.Colors.textSecondary)
                    
                    Text("Connecting...")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                .padding(.top, DesignSystem.Spacing.md)
            }
            
            // Error state
            if let error = googleAuth.lastError {
                Text(error.localizedDescription)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.top, DesignSystem.Spacing.md)
                    .padding(.horizontal, DesignSystem.Spacing.xl)
            } else if let error = authService.authError {
                Text(error)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.top, DesignSystem.Spacing.md)
                    .padding(.horizontal, DesignSystem.Spacing.xl)
            }
            
            Spacer(minLength: 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DesignSystem.Colors.surface)
        .onAppear {
            googleAuth.lastError = nil // Clear any previous errors
            
            // Update onboarding completion state based on stored auth data
            if authService.user != nil {
                authService.completeOnboarding()
            }
        }
    }
    
    // MARK: - Authentication Methods
    
    private func performGoogleSignIn() async {
        isAuthenticating = true
        
        do {
            try await googleAuth.authenticateWithFallback()
            
            // Update AuthenticationService if needed
            if googleAuth.isAuthenticated, let profile = googleAuth.userProfile {
                await updateAuthServiceWithGoogleUser(profile: profile)
            }
            
        } catch {
            // Error handling is already managed by the UI through googleAuth.lastError
        }
        
        isAuthenticating = false
    }
    
    
    private func updateAuthServiceWithGoogleUser(profile: GoogleUserProfile) async {
        // Check if this is a returning user
        let isReturningUser = await authService.isReturningUser(profile.id)
        
        // Create user object based on Google profile
        let selineUser = SelineUser(
            id: profile.id,
            email: profile.email,
            name: profile.name,
            profileImageURL: profile.picture,
            accessToken: await googleAuth.getValidAccessToken() ?? "",
            refreshToken: nil, // Google handles refresh tokens internally
            tokenExpirationDate: Date().addingTimeInterval(365 * 24 * 3600) // 1 year for development persistence
        )
        
        // Set authenticated user (this will also persist to Supabase)
        await authService.setAuthenticatedUser(selineUser)
        
        // For returning users, onboarding is automatically marked as complete
        // For new users, the onboarding completion is handled in setAuthenticatedUser
        if isReturningUser {
            authService.completeOnboarding()
        }
    }
    
}


// MARK: - Preview

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            OnboardingView()
                .preferredColorScheme(.light)
                .previewDisplayName("Light Mode")
            
            OnboardingView()
                .preferredColorScheme(.dark)
                .previewDisplayName("Dark Mode")
        }
    }
}
