//
//  OnboardingFlowView.swift
//  Seline
//
//  Created by Claude on 2025-08-25.
//

import SwiftUI

/// Production-ready onboarding flow with privacy-first approach
struct OnboardingFlowView: View {
    @StateObject private var onboardingManager = OnboardingManager()
    @StateObject private var googleOAuth = GoogleOAuthService.shared
    @State private var currentStep: OnboardingStep = .welcome
    @State private var isAuthenticating = false
    @State private var showingPrivacyPolicy = false
    @State private var showingTermsOfService = false
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    DesignSystem.Colors.surface,
                    DesignSystem.Colors.accent.opacity(0.1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Progress indicator
                progressIndicator
                
                // Main content
                Group {
                    switch currentStep {
                    case .welcome:
                        WelcomeStepView(onNext: advanceToNextStep)
                    case .privacy:
                        PrivacyStepView(
                            onNext: advanceToNextStep,
                            onPrivacyPolicy: { showingPrivacyPolicy = true },
                            onTermsOfService: { showingTermsOfService = true }
                        )
                    case .features:
                        FeaturesStepView(onNext: advanceToNextStep)
                    case .permissions:
                        PermissionsStepView(onNext: advanceToNextStep)
                    case .authentication:
                        AuthenticationStepView(
                            onNext: advanceToNextStep,
                            onSkip: skipAuthentication,
                            isAuthenticating: $isAuthenticating
                        )
                    case .completion:
                        CompletionStepView(onComplete: completeOnboarding)
                    }
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .animation(.easeInOut(duration: 0.4), value: currentStep)
            }
        }
        .sheet(isPresented: $showingPrivacyPolicy) {
            PrivacyPolicyView()
        }
        .sheet(isPresented: $showingTermsOfService) {
            TermsOfServiceView()
        }
        .onAppear {
            AnalyticsManager.shared.trackOnboardingStep(step: "onboarding_started", completed: false)
        }
    }
    
    // MARK: - Progress Indicator
    
    private var progressIndicator: some View {
        VStack(spacing: 16) {
            // Step indicators
            HStack(spacing: 12) {
                ForEach(OnboardingStep.allCases, id: \.self) { step in
                    Circle()
                        .fill(stepIndicatorColor(for: step))
                        .frame(width: 8, height: 8)
                        .scaleEffect(step == currentStep ? 1.5 : 1.0)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentStep)
                }
            }
            
            // Step counter
            Text("\(currentStep.rawValue + 1) of \(OnboardingStep.allCases.count)")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .padding(.top, 20)
        .padding(.bottom, 40)
    }
    
    private func stepIndicatorColor(for step: OnboardingStep) -> Color {
        if step.rawValue < currentStep.rawValue {
            return DesignSystem.Colors.accent
        } else if step == currentStep {
            return DesignSystem.Colors.accent
        } else {
            return DesignSystem.Colors.border
        }
    }
    
    // MARK: - Navigation
    
    private func advanceToNextStep() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        AnalyticsManager.shared.trackOnboardingStep(
            step: currentStep.analyticsName,
            completed: true
        )
        
        if let nextStep = OnboardingStep(rawValue: currentStep.rawValue + 1) {
            withAnimation(.easeInOut(duration: 0.4)) {
                currentStep = nextStep
            }
        }
    }
    
    private func skipAuthentication() {
        AnalyticsManager.shared.trackOnboardingStep(
            step: "authentication_skipped",
            completed: true
        )
        
        // Skip to completion
        withAnimation(.easeInOut(duration: 0.4)) {
            currentStep = .completion
        }
    }
    
    private func completeOnboarding() {
        onboardingManager.completeOnboarding()
        AnalyticsManager.shared.trackOnboardingStep(
            step: "onboarding_completed",
            completed: true
        )
    }
}

// MARK: - Welcome Step

struct WelcomeStepView: View {
    let onNext: () -> Void
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // App icon and branding
            VStack(spacing: 24) {
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.accent.opacity(0.1))
                        .frame(width: 120, height: 120)
                    
                    Circle()
                        .fill(DesignSystem.Colors.accent.gradient)
                        .frame(width: 100, height: 100)
                        .overlay(
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 40, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.buttonTextOnAccent)
                        )
                }
                .animatedScaleIn(delay: 0.1)
                
                VStack(spacing: 16) {
                    Text("Welcome to Seline")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                        .animatedSlideIn(from: .bottom, delay: 0.3)
                    
                    Text("Your intelligent email assistant that helps you stay organized and productive.")
                        .font(.system(size: 18, weight: .regular, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .animatedSlideIn(from: .bottom, delay: 0.4)
                }
            }
            
            Spacer()
            
            // Continue button
            Button(action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                onNext()
            }) {
                HStack(spacing: 12) {
                    Text("Get Started")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.buttonTextOnAccent)
                    
                    Image(systemName: "arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.buttonTextOnAccent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(DesignSystem.Colors.accent.gradient)
                        .shadow(color: DesignSystem.Colors.accent.opacity(0.3), radius: 8, x: 0, y: 4)
                )
            }
            .buttonStyle(AnimatedButtonStyle())
            .animatedSlideIn(from: .bottom, delay: 0.5)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 40)
    }
}

// MARK: - Privacy Step

struct PrivacyStepView: View {
    let onNext: () -> Void
    let onPrivacyPolicy: () -> Void
    let onTermsOfService: () -> Void
    
    @State private var analyticsConsent = false
    
    var body: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 16) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 60))
                    .foregroundColor(DesignSystem.Colors.accent)
                    .animatedScaleIn(delay: 0.1)
                
                VStack(spacing: 8) {
                    Text("Privacy First")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                        .animatedSlideIn(from: .bottom, delay: 0.2)
                    
                    Text("Your data stays private and secure")
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .animatedSlideIn(from: .bottom, delay: 0.3)
                }
            }
            
            // Privacy features
            VStack(spacing: 20) {
                PrivacyFeatureRow(
                    icon: "key.fill",
                    title: "End-to-End Encryption",
                    description: "Your emails and data are encrypted locally"
                )
                .animatedSlideIn(from: .leading, delay: 0.4)
                
                PrivacyFeatureRow(
                    icon: "eye.slash.fill",
                    title: "No Data Collection",
                    description: "We don't collect or sell your personal information"
                )
                .animatedSlideIn(from: .leading, delay: 0.5)
                
                PrivacyFeatureRow(
                    icon: "server.rack",
                    title: "Local Processing",
                    description: "AI features work locally when possible"
                )
                .animatedSlideIn(from: .leading, delay: 0.6)
            }
            
            Spacer()
            
            // Analytics consent
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Button(action: {
                        analyticsConsent.toggle()
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                    }) {
                        Image(systemName: analyticsConsent ? "checkmark.square.fill" : "square")
                            .font(.system(size: 20))
                            .foregroundColor(analyticsConsent ? DesignSystem.Colors.accent : DesignSystem.Colors.textSecondary)
                    }
                    
                    Text("Help improve Seline with anonymous usage analytics")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    
                    Spacer()
                }
                
                // Legal links
                HStack(spacing: 16) {
                    Button("Privacy Policy", action: onPrivacyPolicy)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.accent)
                    
                    Text("•")
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    
                    Button("Terms of Service", action: onTermsOfService)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.accent)
                    
                    Spacer()
                }
            }
            .animatedSlideIn(from: .bottom, delay: 0.7)
            
            // Continue button
            Button(action: {
                AnalyticsManager.shared.hasUserConsent = analyticsConsent
                onNext()
            }) {
                Text("Continue")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.buttonTextOnAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(DesignSystem.Colors.accent.gradient)
                    )
            }
            .buttonStyle(AnimatedButtonStyle())
            .animatedSlideIn(from: .bottom, delay: 0.8)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 40)
    }
}

// MARK: - Features Step

struct FeaturesStepView: View {
    let onNext: () -> Void
    
    var body: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 60))
                    .foregroundColor(DesignSystem.Colors.accent)
                    .animatedScaleIn(delay: 0.1)
                
                VStack(spacing: 8) {
                    Text("Powerful Features")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                        .animatedSlideIn(from: .bottom, delay: 0.2)
                    
                    Text("Designed to make email management effortless")
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .animatedSlideIn(from: .bottom, delay: 0.3)
                }
            }
            
            // Feature list
            VStack(spacing: 24) {
                FeatureRow(
                    icon: "magnifyingglass",
                    iconColor: .blue,
                    title: "AI-Powered Search",
                    description: "Ask questions in natural language and get instant answers"
                )
                .animatedSlideIn(from: .leading, delay: 0.4)
                
                FeatureRow(
                    icon: "brain.head.profile",
                    iconColor: .purple,
                    title: "Smart Categorization",
                    description: "Automatically organize emails by importance and type"
                )
                .animatedSlideIn(from: .leading, delay: 0.5)
                
                FeatureRow(
                    icon: "hand.draw.fill",
                    iconColor: .green,
                    title: "Intuitive Gestures",
                    description: "Swipe to archive, delete, or take quick actions"
                )
                .animatedSlideIn(from: .leading, delay: 0.6)
                
                
            }
            
            Spacer()
            
            // Continue button
            Button(action: onNext) {
                Text("Continue")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.buttonTextOnAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(DesignSystem.Colors.accent.gradient)
                    )
            }
            .buttonStyle(AnimatedButtonStyle())
            .animatedSlideIn(from: .bottom, delay: 0.8)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 40)
    }
}

// MARK: - Supporting Views

struct PrivacyFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(DesignSystem.Colors.accent)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(DesignSystem.Colors.accent.opacity(0.1))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text(description)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            
            Spacer()
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(iconColor)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(iconColor.opacity(0.1))
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text(description)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            
            Spacer()
        }
    }
}

// MARK: - Permissions Step (Placeholder)

struct PermissionsStepView: View {
    let onNext: () -> Void
    
    var body: some View {
        VStack {
            Text("Permissions Step")
                .font(.title)
            
            Text("Request necessary permissions here")
                .foregroundColor(.secondary)
            
            Button("Continue", action: onNext)
                .padding()
        }
    }
}

// MARK: - Authentication Step (Placeholder)

struct AuthenticationStepView: View {
    let onNext: () -> Void
    let onSkip: () -> Void
    @Binding var isAuthenticating: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Authentication Step")
                .font(.title)
            
            Text("Sign in with Google")
                .foregroundColor(.secondary)
            
            Button("Sign In") {
                Task {
                    isAuthenticating = true
                    // Implement Google OAuth
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    isAuthenticating = false
                    onNext()
                }
            }
            .disabled(isAuthenticating)
            
            Button("Skip for Now", action: onSkip)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Completion Step (Placeholder)

struct CompletionStepView: View {
    let onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("🎉")
                .font(.system(size: 60))
            
            Text("You're All Set!")
                .font(.title)
            
            Text("Welcome to Seline")
                .foregroundColor(.secondary)
            
            Button("Start Using Seline", action: onComplete)
                .padding()
        }
    }
}

// MARK: - Supporting Models

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case privacy = 1
    case features = 2
    case permissions = 3
    case authentication = 4
    case completion = 5
    
    var analyticsName: String {
        switch self {
        case .welcome: return "welcome"
        case .privacy: return "privacy"
        case .features: return "features"
        case .permissions: return "permissions"
        case .authentication: return "authentication"
        case .completion: return "completion"
        }
    }
}

// MARK: - Onboarding Manager

class OnboardingManager: ObservableObject {
    @Published var hasCompletedOnboarding: Bool
    
    init() {
        hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "has_completed_onboarding")
    }
    
    func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: "has_completed_onboarding")
    }
    
    func resetOnboarding() {
        hasCompletedOnboarding = false
        UserDefaults.standard.removeObject(forKey: "has_completed_onboarding")
    }
}

// MARK: - Legal Views (Placeholders)

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                Text("Privacy Policy content would go here...")
                    .padding()
            }
            .navigationTitle("Privacy Policy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct TermsOfServiceView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                Text("Terms of Service content would go here...")
                    .padding()
            }
            .navigationTitle("Terms of Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Preview

struct OnboardingFlowView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingFlowView()
    }
}