//
//  TodayEmailsView.swift
//  Seline
//
//  Transformed from ImportantEmailsView to show AI-powered email summaries
//

import SwiftUI

struct TodayEmailsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ContentViewModel()
    @StateObject private var summaryCache = EmailSummaryCacheManager()
    @ObservedObject var openAIService: OpenAIService
    @State private var selectedEmail: Email?
    @State private var isShowingEmailDetail = false
    @State private var showingAPIKeySetupGuide = false
    @State private var showingFeatureComparison = false
    @State private var feedbackMessage: String = ""
    @State private var showingFeedback = false
    
    // Computed property for today's emails
    private var todaysEmails: [Email] {
        let today = Date()
        return viewModel.emails.filter { email in
            Calendar.current.isDate(email.date, inSameDayAs: today)
        }
    }
    @State private var isSuccessFeedback = true
    @State private var expandedGroups: [TimeGroup: Bool] = [.morning: true, .afternoon: true, .evening: true, .night: true]

    var body: some View {
        NavigationView {
            ZStack {
                DesignSystem.Colors.surface.ignoresSafeArea()
                
                if viewModel.isLoading {
                    loadingView
                } else if todaysEmails.isEmpty {
                    emptyStateView
                } else {
                    timeGroupedEmailsList
                }
                
                // Feedback Toast
                if showingFeedback {
                    VStack {
                        Spacer()
                        
                        HStack(spacing: 8) {
                            Image(systemName: isSuccessFeedback ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(isSuccessFeedback ? .green : .orange)
                            
                            Text(feedbackMessage)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(DesignSystem.Colors.surface)
                        .cornerRadius(12)
                        .shadow(color: DesignSystem.Colors.shadow.opacity(0.2), radius: 8, x: 0, y: 2)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 100)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .animation(.easeInOut(duration: 0.3), value: showingFeedback)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Text("Today's Emails")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
            }
            .onAppear {
                #if DEBUG
                print("📱 TodayEmailsView appeared")
                #endif
                
                Task {
                    // Fetch all today's emails with categorization
                    await viewModel.loadInitialData()
                }
            }
            .sheet(item: $selectedEmail) { email in
                GmailStyleEmailDetailView(email: email, viewModel: viewModel)
            }
        }
    }
    
    private var timeGroupedEmails: [TimeGroup: [Email]] {
        Dictionary(grouping: todaysEmails, by: { email in
            let hour = Calendar.current.component(.hour, from: email.date)
            if hour >= 6 && hour < 12 {
                return .morning
            } else if hour >= 12 && hour < 18 {
                return .afternoon
            } else if hour >= 18 && hour < 24 {
                return .evening
            } else {
                return .night
            }
        })
    }

    // MARK: - Time-Grouped Emails List

    private var timeGroupedEmailsList: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 12) {
                // AI Setup Promotion Card (shown when no API key configured)
                if openAIService.showAPIKeySetupGuide || (!openAIService.isConfigured && openAIService.hasPotentialChatGPTAccount) {
                    aiSetupPromotionCard
                }

                ForEach(TimeGroup.allCases, id: \.self) { group in
                    if let emails = timeGroupedEmails[group], !emails.isEmpty {
                        TimeGroupSection(
                            group: group,
                            emails: emails,
                            isExpanded: Binding(
                                get: { expandedGroups[group, default: true] },
                                set: { expandedGroups[group] = $0 }
                            ),
                            summaryCache: summaryCache,
                            onOpenInGmail: openEmailInApp
                        )
                        .padding(.leading, 10).padding(.trailing, 18)
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .refreshable {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            
            await performEnhancedRefresh()
            
            // Success feedback after refresh
            await MainActor.run {
                showSuccessFeedback(message: "Emails refreshed")
            }
        }
    }
    
    private func performEnhancedRefresh() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await viewModel.loadInitialData()
            }
            
            // Clear summary cache to get fresh summaries
            group.addTask {
                await summaryCache.clearCache()
            }
            
            // Add a small delay to ensure smooth animation
            group.addTask {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
            
            await group.waitForAll()
        }
    }
    
    // MARK: - Gmail Integration Actions
    
    private func openEmailInApp(_ email: Email) {
        selectedEmail = email
    }
    
    private func showPermissionAlert() {
        let alert = UIAlertController(
            title: "Permission Required",
            message: "To manage emails, Seline needs Gmail modify permission. Please sign out and sign in again when prompted.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first,
           let root = window.rootViewController {
            root.present(alert, animated: true)
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            ForEach(0..<5, id: \.self) { index in
                SkeletonSummaryCard()
                    .animatedSlideIn(from: .bottom, delay: Double(index) * 0.1)
            }
        }
        .padding(DesignSystem.Spacing.lg)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.accent.opacity(0.1))
                    .frame(width: 80, height: 80)
                    .animatedScaleIn(delay: 0.1)

                Image(systemName: "sun.max.circle")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundColor(DesignSystem.Colors.accent)
                    .animatedScaleIn(delay: 0.3)
            }

            VStack(spacing: 12) {
                Text("All Focused!")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .animatedSlideIn(from: .bottom, delay: 0.4)

                Text("No important emails today. We've filtered out promotional content so you can focus on what matters.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .animatedSlideIn(from: .bottom, delay: 0.5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
    
    // MARK: - AI Setup Promotion
    
    private var aiSetupPromotionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with AI icon
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.accent.opacity(0.1))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.accent)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Unlock AI Summaries")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    Text("Get intelligent 2-3 sentence email summaries")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                
                Spacer()
            }
            
            // Personalized message
            Text(openAIService.getPersonalizedSetupMessage())
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            
            // Benefits preview
            HStack(spacing: 16) {
                benefitPreview(icon: "clock.arrow.2.circlepath", title: "80% Faster", subtitle: "Email triage")
                benefitPreview(icon: "brain.head.profile", title: "AI Powered", subtitle: "Smart insights")
                benefitPreview(icon: "dollarsign.circle", title: "~$5/month", subtitle: "Typical cost")
            }
            
            // Action buttons
            HStack(spacing: 12) {
                Button(action: {
                    showingFeatureComparison = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "eye")
                        Text("See Examples")
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .fill(DesignSystem.Colors.accent.opacity(0.1))
                    )
                }
                
                Button(action: {
                    showingAPIKeySetupGuide = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.circle.fill")
                        Text("Setup Guide")
                    }
                    .font(.system(size: 15, weight: .semibold))
                }
                .buttonStyle(PrimaryButtonStyle())
                
                Button(action: {
                    openAIService.showAPIKeySetupGuide = false
                }) {
                    Text("Later")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DesignSystem.Colors.surface)
                .shadow(
                    color: DesignSystem.Colors.shadow.opacity(0.1),
                    radius: 8,
                    x: 0,
                    y: 2
                )
        )
        .sheet(isPresented: $showingAPIKeySetupGuide) {
            APIKeySetupGuideView(
                openAIService: openAIService,
                onComplete: {
                    showingAPIKeySetupGuide = false
                    openAIService.showAPIKeySetupGuide = false
                },
                onDismiss: {
                    showingAPIKeySetupGuide = false
                }
            )
        }
        .sheet(isPresented: $showingFeatureComparison) {
            FeatureComparisonView()
        }
    }
    
    private func benefitPreview(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(DesignSystem.Colors.accent)
            
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            Text(subtitle)
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
    }
    
    // MARK: - Helper Methods
    
    /// Retry operation with exponential backoff
    private func withRetry<T>(maxRetries: Int, operation: @escaping () async throws -> T) async throws -> T {
        var lastError: Error?
        
        for attempt in 0..<maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error
                if attempt < maxRetries - 1 {
                    let delay = Double(1 << attempt) // Exponential backoff: 1s, 2s, 4s
                    #if DEBUG
                    print("🔄 Retry attempt \(attempt + 1) failed, retrying in \(delay)s...")
                    #endif
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? NSError(domain: "RetryError", code: -1, userInfo: nil)
    }
    
    /// Show success feedback
    private func showSuccessFeedback(message: String) {
        feedbackMessage = message
        isSuccessFeedback = true
        showingFeedback = true
        
        // Auto-hide after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showingFeedback = false
        }
    }
    
    /// Show error feedback
    private func showErrorFeedback(message: String) {
        feedbackMessage = message
        isSuccessFeedback = false
        showingFeedback = true
        
        // Auto-hide after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            showingFeedback = false
        }
    }
}

// MARK: - Time Grouping

enum TimeGroup: CaseIterable {
    case morning    // 6 AM - 12 PM
    case afternoon  // 12 PM - 6 PM  
    case evening    // 6 PM - 12 AM
    case night      // 12 AM - 6 AM
    
    var displayName: String {
        switch self {
        case .morning: return "This Morning"
        case .afternoon: return "This Afternoon"
        case .evening: return "This Evening"
        case .night: return "Late Night"
        }
    }
    
    func contains(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        
        switch self {
        case .morning: return hour >= 6 && hour < 12
        case .afternoon: return hour >= 12 && hour < 18
        case .evening: return hour >= 18 && hour < 24
        case .night: return hour >= 0 && hour < 6
        }
    }
}

// MARK: - Time Group Section Component

struct TimeGroupSection: View {
    let group: TimeGroup
    let emails: [Email]
    @Binding var isExpanded: Bool // Added back
    let summaryCache: EmailSummaryCacheManager
    let onOpenInGmail: (Email) -> Void
    
    private let maxEmailsToShow = 3 // Limit to 3 emails initially
    @State private var showAllEmails = false // State to control "Show More"
    
    var body: some View {
        DisclosureGroup( // Changed back to DisclosureGroup
            isExpanded: $isExpanded,
            content: {
                VStack(spacing: 6) {
                    ForEach(emails.prefix(showAllEmails ? emails.count : maxEmailsToShow)) { email in
                        AISummaryEmailCard(
                            email: email,
                            onOpenInGmail: {
                                onOpenInGmail(email)
                            }
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                        .animation(.easeInOut(duration: 0.3).delay(Double(emails.firstIndex(of: email) ?? 0) * 0.1), value: emails.count)
                    }
                    
                    if emails.count > maxEmailsToShow && !showAllEmails {
                        Button(action: {
                            showAllEmails = true
                        }) {
                            Text("Show All \(emails.count) Emails")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(DesignSystem.Colors.accent)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity)
                                .background(DesignSystem.Colors.accent.opacity(0.1))
                                .cornerRadius(8)
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(DesignSystem.Colors.surface)
                )
            },
            label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.displayName)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        
                        Text("\(emails.count) \(emails.count == 1 ? "email" : "emails")")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    
                    Spacer()
                    
                    // Email count badge
                    Text("\(emails.count)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.buttonTextOnAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(DesignSystem.Colors.accent)
                        )
                }
                .contentShape(Rectangle())
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
            }
        )
        .accentColor(DesignSystem.Colors.accent) // Added back
    }
}

// MARK: - Preview

struct TodayEmailsView_Previews: PreviewProvider {
    static var previews: some View {
        TodayEmailsView(openAIService: OpenAIService.shared)
    }
}
