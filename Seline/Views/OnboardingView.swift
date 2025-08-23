//
//  OnboardingView.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-24.
//

import SwiftUI

struct OnboardingView: View {
    @StateObject private var authService = AuthenticationService.shared
    @State private var showingPermissionSheet = false
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xxl) {
            Spacer()
            
            // App Icon and Branding
            brandingSection
            
            // Feature Highlights
            featuresSection
            
            Spacer()
            
            // Sign In Button
            signInSection
            
            // Privacy and Terms
            legalSection
        }
        .padding(DesignSystem.Spacing.lg)
        .designSystemBackground()
        .sheet(isPresented: $showingPermissionSheet) {
            PermissionExplanationSheet()
        }
    }
    
    // MARK: - Branding Section
    
    private var brandingSection: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            // App Icon Placeholder
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                .fill(DesignSystem.Colors.accent)
                .frame(width: 100, height: 100)
                .overlay(
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.white)
                )
                .shadow(color: DesignSystem.Shadow.medium, radius: 10, x: 0, y: 5)
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Welcome to Seline")
                    .font(DesignSystem.Typography.title1)
                    .primaryText()
                
                Text("Smart email management with Google integration")
                    .font(DesignSystem.Typography.body)
                    .secondaryText()
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    // MARK: - Features Section
    
    private var featuresSection: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            FeatureRow(
                icon: "magnifyingglass.circle.fill",
                title: "Smart Search",
                description: "Find emails quickly with intelligent search"
            )
            
            FeatureRow(
                icon: "tray.2.fill",
                title: "Auto-Categorization",
                description: "Important, promotional, and calendar emails organized automatically"
            )
            
            FeatureRow(
                icon: "calendar.circle.fill",
                title: "Calendar Integration",
                description: "View upcoming events alongside your emails"
            )
        }
    }
    
    // MARK: - Sign In Section
    
    private var signInSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Button(action: {
                showingPermissionSheet = true
            }) {
                HStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "globe")
                        .font(.title2)
                        .foregroundColor(.white)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Continue with Google")
                            .font(DesignSystem.Typography.bodyMedium)
                            .foregroundColor(.white)
                        
                        Text("Gmail & Calendar access")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Spacer()
                }
                .padding(DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.accent)
                .cornerRadius(DesignSystem.CornerRadius.md)
                .shadow(color: DesignSystem.Shadow.medium, radius: 8, x: 0, y: 4)
            }
            .disabled(authService.isLoading)
            
            if authService.isLoading {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ProgressView()
                        .scaleEffect(0.8)
                    
                    Text("Signing in...")
                        .font(DesignSystem.Typography.callout)
                        .secondaryText()
                }
                .padding(.top, DesignSystem.Spacing.sm)
            }
            
            if let error = authService.authError {
                Text(error)
                    .font(DesignSystem.Typography.footnote)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.top, DesignSystem.Spacing.sm)
            }
        }
    }
    
    // MARK: - Legal Section
    
    private var legalSection: some View {
        VStack(spacing: DesignSystem.Spacing.xs) {
            Text("By continuing, you agree to our")
                .font(DesignSystem.Typography.caption)
                .secondaryText()
            
            HStack(spacing: DesignSystem.Spacing.xs) {
                Button("Privacy Policy") {
                    // Handle privacy policy tap
                }
                .font(DesignSystem.Typography.caption)
                .accentColor()
                
                Text("and")
                    .font(DesignSystem.Typography.caption)
                    .secondaryText()
                
                Button("Terms of Service") {
                    // Handle terms tap
                }
                .font(DesignSystem.Typography.caption)
                .accentColor()
            }
        }
    }
}

// MARK: - Feature Row Component

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(DesignSystem.Colors.accent)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(DesignSystem.Typography.bodyMedium)
                    .primaryText()
                
                Text(description)
                    .font(DesignSystem.Typography.subheadline)
                    .secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
    }
}

// MARK: - Permission Explanation Sheet

struct PermissionExplanationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var authService = AuthenticationService.shared
    
    var body: some View {
        NavigationView {
            VStack(spacing: DesignSystem.Spacing.lg) {
                // Header
                VStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 50))
                        .foregroundColor(DesignSystem.Colors.accent)
                    
                    Text("Permissions Required")
                        .font(DesignSystem.Typography.title2)
                        .primaryText()
                    
                    Text("Seline needs access to Gmail and Calendar to provide smart email management")
                        .font(DesignSystem.Typography.body)
                        .secondaryText()
                        .multilineTextAlignment(.center)
                }
                
                // Permission Details
                VStack(spacing: DesignSystem.Spacing.md) {
                    PermissionRow(
                        icon: "envelope.fill",
                        title: "Gmail Access",
                        description: "Read your emails to organize and search them"
                    )
                    
                    PermissionRow(
                        icon: "calendar.circle.fill",
                        title: "Calendar Access",
                        description: "View upcoming events and meeting information"
                    )
                    
                    PermissionRow(
                        icon: "person.circle.fill",
                        title: "Profile Information",
                        description: "Your name and email for personalization"
                    )
                }
                .padding(DesignSystem.Spacing.md)
                .designSystemSecondaryBackground()
                .cornerRadius(DesignSystem.CornerRadius.md)
                
                // Security Note
                VStack(spacing: DesignSystem.Spacing.sm) {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.green)
                        
                        Text("Your data stays secure")
                            .font(DesignSystem.Typography.bodyMedium)
                            .primaryText()
                        
                        Spacer()
                    }
                    
                    Text("Seline only reads your emails and calendar. We never store your personal data on our servers.")
                        .font(DesignSystem.Typography.subheadline)
                        .secondaryText()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: DesignSystem.Spacing.sm) {
                    Button(action: {
                        dismiss()
                        Task {
                            await authService.signInWithGoogle()
                        }
                    }) {
                        HStack {
                            if authService.isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .foregroundColor(.white)
                            } else {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.white)
                            }
                            
                            Text(authService.isLoading ? "Signing In..." : "Grant Permissions")
                                .font(DesignSystem.Typography.bodyMedium)
                                .foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(DesignSystem.Spacing.md)
                        .background(DesignSystem.Colors.accent)
                        .cornerRadius(DesignSystem.CornerRadius.md)
                    }
                    .disabled(authService.isLoading)
                    
                    Button("Maybe Later") {
                        dismiss()
                    }
                    .font(DesignSystem.Typography.body)
                    .secondaryText()
                }
            }
            .padding(DesignSystem.Spacing.lg)
            .designSystemBackground()
            .navigationTitle("Permissions")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(DesignSystem.Typography.body)
                    .accentColor()
                }
            }
        }
    }
}

// MARK: - Permission Row Component

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(DesignSystem.Colors.accent)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(DesignSystem.Typography.bodyMedium)
                    .primaryText()
                
                Text(description)
                    .font(DesignSystem.Typography.footnote)
                    .secondaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
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
            
            PermissionExplanationSheet()
                .preferredColorScheme(.light)
                .previewDisplayName("Permission Sheet")
        }
    }
}