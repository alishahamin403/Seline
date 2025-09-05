//
//  FeatureComparisonView.swift
//  Seline
//
//  Shows value demonstration between free and premium AI features
//

import SwiftUI

struct FeatureComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: ComparisonTab = .summary
    @State private var showingSetupGuide = false
    
    enum ComparisonTab: CaseIterable {
        case summary
        case search
        
        
        var title: String {
            switch self {
            case .summary: return "Email Summaries"
            case .search: return "Intelligent Search"
            
            }
        }
        
        var icon: String {
            switch self {
            case .summary: return "doc.text"
            case .search: return "magnifyingglass"
            
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    headerSection
                    
                    // Feature Tabs
                    tabSelector
                    
                    // Comparison Content
                    comparisonContent
                    
                    // Upgrade CTA
                    upgradeCTA
                }
                .padding(.vertical, 20)
            }
            .background(DesignSystem.Colors.background)
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Free vs Premium")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingSetupGuide) {
            APIKeySetupGuideView(
                openAIService: OpenAIService.shared,
                onComplete: {
                    showingSetupGuide = false
                    dismiss()
                },
                onDismiss: {
                    showingSetupGuide = false
                }
            )
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                // Free Badge
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.gray.opacity(0.1))
                            .frame(width: 60, height: 60)
                        
                        Text("FREE")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.gray)
                    }
                    
                    Text("Basic Features")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.accent)
                
                // Premium Badge
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(DesignSystem.Colors.accent.opacity(0.1))
                            .frame(width: 60, height: 60)
                        
                        Image(systemName: "sparkles")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.accent)
                    }
                    
                    Text("AI Powered")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                }
            }
            
            Text("See the difference AI makes in your email workflow")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
    }
    
    private var tabSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(ComparisonTab.allCases, id: \.self) { tab in
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            selectedTab = tab
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 16, weight: .medium))
                            
                            Text(tab.title)
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundColor(selectedTab == tab ? .white : DesignSystem.Colors.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(selectedTab == tab ? DesignSystem.Colors.accent : DesignSystem.Colors.surface)
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }
    
    @ViewBuilder
    private var comparisonContent: some View {
        switch selectedTab {
        case .summary:
            summaryComparison
        case .search:
            searchComparison
        
        }
    }
    
    private var summaryComparison: some View {
        VStack(spacing: 20) {
            // Sample Email
            emailSample
            
            // Comparison
            HStack(alignment: .top, spacing: 16) {
                // Free Version
                comparisonCard(
                    title: "Free: Basic Summary",
                    content: "Message from Sarah Johnson regarding Meeting Invitation: Q1 Planning Review. Review the details and respond if action is required.",
                    isAI: false
                )
                
                // Premium Version
                comparisonCard(
                    title: "Premium: AI Summary",
                    content: "Sarah is requesting confirmation for Q1 planning review meeting next Tuesday at 2 PM. Please review attached agenda and confirm availability by Thursday.",
                    isAI: true
                )
            }
            .padding(.horizontal, 20)
        }
    }
    
    private var searchComparison: some View {
        VStack(spacing: 20) {
            // Search Query Example
            VStack(alignment: .leading, spacing: 12) {
                Text("Search Query Example:")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(DesignSystem.Colors.accent)
                    
                    Text("\"Show me urgent emails from this week about meetings\"")
                        .font(.system(size: 15, weight: .regular, design: .monospaced))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .padding(12)
                        .background(DesignSystem.Colors.surface)
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 20)
            
            // Comparison
            HStack(alignment: .top, spacing: 16) {
                // Free Version
                comparisonCard(
                    title: "Free: Keyword Search",
                    content: "Basic text matching:\n• Searches for exact words\n• No context understanding\n• Manual filtering required\n• Limited results",
                    isAI: false
                )
                
                // Premium Version
                comparisonCard(
                    title: "Premium: AI Search",
                    content: "Intelligent understanding:\n• Understands intent and context\n• Finds relevant emails even without exact keywords\n• Smart filtering and ranking\n• Comprehensive results",
                    isAI: true
                )
            }
            .padding(.horizontal, 20)
        }
    }
    
    
    
    private var emailSample: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sample Email:")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("From:")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Sarah Johnson <sarah@company.com>")
                        .font(.system(size: 14, weight: .regular))
                    Spacer()
                }
                
                HStack {
                    Text("Subject:")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Meeting Invitation: Q1 Planning Review")
                        .font(.system(size: 14, weight: .regular))
                    Spacer()
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Body:")
                        .font(.system(size: 14, weight: .semibold))
                    
                    Text("Hi team, I'd like to schedule our Q1 planning review meeting for next Tuesday at 2 PM. Please review the attached agenda and confirm your availability by Thursday. We'll be discussing budget allocations and upcoming project priorities.")
                        .font(.system(size: 14, weight: .regular))
                }
            }
            .foregroundColor(DesignSystem.Colors.textSecondary)
            .padding(16)
            .background(DesignSystem.Colors.surface)
            .cornerRadius(12)
        }
        .padding(.horizontal, 20)
    }
    
    private func comparisonCard(title: String, content: String, isAI: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                if isAI {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.accent)
                }
                
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isAI ? DesignSystem.Colors.accent : DesignSystem.Colors.textSecondary)
                
                Spacer()
            }
            
            Text(content)
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            
            if isAI {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                    
                    Text("Contextual & Actionable")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.green)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isAI ? DesignSystem.Colors.accent.opacity(0.05) : DesignSystem.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isAI ? DesignSystem.Colors.accent.opacity(0.2) : Color.clear, lineWidth: 1)
                )
        )
    }
    
    private var upgradeCTA: some View {
        VStack(spacing: 20) {
            // Cost Breakdown
            VStack(spacing: 12) {
                Text("💰 Typical Monthly Cost")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                VStack(spacing: 8) {
                    HStack {
                        Text("• Email summaries (100/month):")
                        Spacer()
                        Text("~$0.10")
                    }
                    
                    HStack {
                        Text("• Intelligent search queries:")
                        Spacer()
                        Text("~$0.50")
                    }
                    
                    
                    
                    Divider()
                    
                    HStack {
                        Text("Total estimated cost:")
                            .font(.system(size: 16, weight: .semibold))
                        Spacer()
                        Text("~$0.80 - $5.00/month")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.accent)
                    }
                }
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            .padding(20)
            .background(DesignSystem.Colors.surface)
            .cornerRadius(16)
            .padding(.horizontal, 20)
            
            // Upgrade Button
            Button(action: {
                showingSetupGuide = true
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 16, weight: .medium))
                    
                    Text("Upgrade to Premium AI")
                        .font(.system(size: 18, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [DesignSystem.Colors.accent, DesignSystem.Colors.accent.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .padding(.horizontal, 20)
            
            Text("Pay only for what you use with OpenAI's transparent pricing")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
    }
}

// MARK: - Preview

struct FeatureComparisonView_Previews: PreviewProvider {
    static var previews: some View {
        FeatureComparisonView()
            .preferredColorScheme(.dark)
    }
}