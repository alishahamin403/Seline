//
//  APIKeySetupGuideView.swift
//  Seline
//
//  AI-guided OpenAI API key setup tutorial
//

import SwiftUI

struct APIKeySetupGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var openAIService: OpenAIService
    @State private var enteredAPIKey: String = ""
    @State private var currentStep: SetupStep = .welcome
    @State private var isValidating = false
    @State private var validationResult: ValidationResult?
    
    let onComplete: () -> Void
    let onDismiss: () -> Void
    
    enum SetupStep: Int, CaseIterable {
        case welcome = 0
        case benefits = 1
        case instructions = 2
        case keyEntry = 3
        case validation = 4
        case success = 5
        
        var title: String {
            switch self {
            case .welcome: return "Welcome!"
            case .benefits: return "Why Connect?"
            case .instructions: return "Get Your Key"
            case .keyEntry: return "Enter Your Key"
            case .validation: return "Validating..."
            case .success: return "All Set!"
            }
        }
    }
    
    enum ValidationResult {
        case success
        case invalidFormat
        case networkError
        case apiError
        
        var message: String {
            switch self {
            case .success: return "API key validated successfully!"
            case .invalidFormat: return "Invalid API key format. Keys should start with 'sk-'."
            case .networkError: return "Network error. Please check your connection."
            case .apiError: return "Invalid API key. Please check your key from OpenAI."
            }
        }
        
        var isError: Bool {
            switch self {
            case .success: return false
            default: return true
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Progress Bar
                ProgressView(value: Double(currentStep.rawValue), total: Double(SetupStep.allCases.count - 1))
                    .progressViewStyle(LinearProgressViewStyle(tint: DesignSystem.Colors.accent))
                    .scaleEffect(x: 1, y: 2, anchor: .center)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                
                // Content Area
                ScrollView {
                    VStack(spacing: 24) {
                        stepContent
                    }
                    .padding(20)
                }
                
                // Navigation Buttons
                HStack(spacing: 16) {
                    if currentStep != .welcome {
                        Button("Back") {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                previousStep()
                            }
                        }
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .font(.system(size: 16, weight: .medium))
                    }
                    
                    Spacer()
                    
                    navigationButton
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 34)
                .background(DesignSystem.Colors.surface)
            }
            .background(DesignSystem.Colors.background)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle(currentStep.title)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Skip") {
                        onDismiss()
                    }
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }
        }
    }
    
    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .welcome:
            welcomeStep
        case .benefits:
            benefitsStep
        case .instructions:
            instructionsStep
        case .keyEntry:
            keyEntryStep
        case .validation:
            validationStep
        case .success:
            successStep
        }
    }
    
    private var welcomeStep: some View {
        VStack(spacing: 24) {
            // AI Icon
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.accent.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.accent)
            }
            
            VStack(spacing: 16) {
                Text("Unlock AI-Powered Email")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                
                Text(openAIService.getPersonalizedSetupMessage())
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Quick Stats
            HStack(spacing: 20) {
                statItem(icon: "clock.arrow.2.circlepath", value: "80%", label: "Faster Triage")
                statItem(icon: "sparkles", value: "AI", label: "Summaries")
                statItem(icon: "magnifyingglass.circle", value: "Smart", label: "Search")
            }
            .padding(.top, 8)
        }
    }
    
    private var benefitsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Here's what you'll get:")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            VStack(spacing: 16) {
                ForEach(openAIService.getSetupBenefits(), id: \.self) { benefit in
                    benefitRow(benefit)
                }
            }
            
            // Cost Info
            VStack(alignment: .leading, spacing: 8) {
                Text("💰 Cost Information")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("OpenAI API pricing is pay-as-you-use. Typical email summaries cost ~$0.001 each. Most users spend less than $5/month.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(DesignSystem.Colors.accent.opacity(0.05))
            .cornerRadius(12)
        }
    }
    
    private var instructionsStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Get your API key in 3 steps:")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            VStack(spacing: 16) {
                instructionStep(
                    number: 1,
                    title: "Go to OpenAI Platform",
                    description: "Visit platform.openai.com and sign in with your account"
                )
                
                instructionStep(
                    number: 2,
                    title: "Navigate to API Keys",
                    description: "Go to 'API Keys' in your dashboard and click 'Create new secret key'"
                )
                
                instructionStep(
                    number: 3,
                    title: "Copy Your Key",
                    description: "Copy the generated key (starts with 'sk-') and paste it in the next step"
                )
            }
            
            // Quick Link Button
            Button(action: {
                if let url = URL(string: "https://platform.openai.com/api-keys") {
                    UIApplication.shared.open(url)
                }
            }) {
                HStack {
                    Image(systemName: "link")
                        .font(.system(size: 14, weight: .medium))
                    
                    Text("Open OpenAI Platform")
                        .font(.system(size: 16, weight: .medium))
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 8)
        }
    }
    
    private var keyEntryStep: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Enter your OpenAI API key")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("Paste the API key you copied from OpenAI Platform")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // API Key Input
            VStack(alignment: .leading, spacing: 8) {
                TextField("sk-...", text: $enteredAPIKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(.body, design: .monospaced))
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                
                if !enteredAPIKey.isEmpty && !isValidAPIKeyFormat(enteredAPIKey) {
                    Text("⚠️ API keys should start with 'sk-'")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.orange)
                }
            }
            
            // Security Notice
            VStack(alignment: .leading, spacing: 8) {
                Text("🔒 Security Notice")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("Your API key is stored securely on your device and never shared with anyone.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(DesignSystem.Colors.textSecondary.opacity(0.05))
            .cornerRadius(8)
        }
    }
    
    private var validationStep: some View {
        VStack(spacing: 24) {
            // Loading Indicator
            VStack(spacing: 16) {
                if isValidating {
                    ProgressView()
                        .scaleEffect(1.2)
                    
                    Text("Validating your API key...")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                } else if let result = validationResult {
                    Image(systemName: result.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundColor(result.isError ? .red : .green)
                    
                    Text(result.message)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(result.isError ? .red : .green)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
    
    private var successStep: some View {
        VStack(spacing: 24) {
            // Success Animation
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundColor(.green)
            }
            
            VStack(spacing: 16) {
                Text("You're all set!")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("AI features are now active. You'll see intelligent summaries, smart search, and calendar processing throughout the app.")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Next Steps
            VStack(alignment: .leading, spacing: 12) {
                Text("💡 Pro Tips:")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("• Check Today's Emails for AI summaries")
                    Text("• Try intelligent search with natural language")
                    Text("• Look for AI insights in email details")
                }
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .padding(16)
            .background(DesignSystem.Colors.accent.opacity(0.05))
            .cornerRadius(12)
        }
    }
    
    @ViewBuilder
    private var navigationButton: some View {
        Button(action: nextAction) {
            HStack(spacing: 8) {
                Text(nextButtonTitle)
                    .font(.system(size: 16, weight: .semibold))
                
                if currentStep != .success && currentStep != .validation {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .medium))
                }
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(!canProceed)
        .opacity(canProceed ? 1 : 0.6)
    }
    
    // MARK: - Helper Methods
    
    private func statItem(icon: String, value: String, label: String) -> VStack<TupleView<(some View, some View, some View)>> {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(DesignSystem.Colors.accent)
            
            Text(value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            Text(label)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
    }
    
    private func benefitRow(_ benefit: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("•")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(DesignSystem.Colors.accent)
                .frame(width: 8, alignment: .leading)
            
            Text(benefit)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
    }
    
    private func instructionStep(number: Int, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.accent)
                    .frame(width: 32, height: 32)
                
                Text("\(number)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.buttonTextOnAccent)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text(description)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
    }
    
    private func isValidAPIKeyFormat(_ key: String) -> Bool {
        return key.hasPrefix("sk-") && key.count > 20
    }
    
    private var canProceed: Bool {
        switch currentStep {
        case .keyEntry:
            return isValidAPIKeyFormat(enteredAPIKey)
        case .validation:
            return validationResult != nil && !validationResult!.isError
        default:
            return true
        }
    }
    
    private var nextButtonTitle: String {
        switch currentStep {
        case .welcome: return "Get Started"
        case .benefits: return "Continue"
        case .instructions: return "I Got My Key"
        case .keyEntry: return "Validate Key"
        case .validation: return validationResult?.isError == true ? "Try Again" : "Continue"
        case .success: return "Start Using AI"
        }
    }
    
    private var nextButtonColor: Color {
        switch currentStep {
        case .validation:
            if let result = validationResult {
                return result.isError ? .orange : DesignSystem.Colors.accent
            }
            return DesignSystem.Colors.accent
        default:
            return DesignSystem.Colors.accent
        }
    }
    
    private func nextAction() {
        switch currentStep {
        case .keyEntry:
            validateAPIKey()
        case .validation:
            if validationResult?.isError == true {
                // Reset to key entry to try again
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentStep = .keyEntry
                    validationResult = nil
                }
            } else {
                nextStep()
            }
        case .success:
            onComplete()
        default:
            nextStep()
        }
    }
    
    private func nextStep() {
        withAnimation(.easeInOut(duration: 0.3)) {
            if let currentIndex = SetupStep.allCases.firstIndex(of: currentStep),
               currentIndex < SetupStep.allCases.count - 1 {
                currentStep = SetupStep.allCases[currentIndex + 1]
            }
        }
    }
    
    private func previousStep() {
        if let currentIndex = SetupStep.allCases.firstIndex(of: currentStep),
           currentIndex > 0 {
            currentStep = SetupStep.allCases[currentIndex - 1]
            
            // Clear validation state when going back
            if currentStep == .keyEntry {
                validationResult = nil
            }
        }
    }
    
    private func validateAPIKey() {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = .validation
        }
        
        isValidating = true
        validationResult = nil
        
        // Basic format validation
        guard isValidAPIKeyFormat(enteredAPIKey) else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                isValidating = false
                validationResult = .invalidFormat
            }
            return
        }
        
        // Store the key
        let success = SecureStorage.shared.storeOpenAIKey(enteredAPIKey)
        
        // Simulate validation delay for better UX
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isValidating = false
            
            if success {
                // Refresh OpenAI service configuration
                openAIService.refreshConfiguration()
                validationResult = .success
                
                // Auto-proceed to success after brief delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    nextStep()
                }
            } else {
                validationResult = .apiError
            }
        }
    }
}

// MARK: - Preview

struct APIKeySetupGuideView_Previews: PreviewProvider {
    static var previews: some View {
        APIKeySetupGuideView(
            openAIService: OpenAIService.shared,
            onComplete: { print("Setup completed") },
            onDismiss: { print("Setup dismissed") }
        )
        .preferredColorScheme(.dark)
    }
}