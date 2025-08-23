//
//  ContentView.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-24.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    @State private var showingInbox = false
    @State private var showingSettings = false
    @State private var showingSearchResults = false
    @State private var showingImportantEmails = false
    @State private var showingPromotionalEmails = false
    @State private var showingUpcomingEvents = false
    @State private var isRefreshing = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Custom header with inbox button
                headerWithActions
                    .animatedSlideIn(from: .top)
                
                RefreshableScrollView(isRefreshing: $isRefreshing, onRefresh: {
                    await performRefresh()
                }) {
                    VStack(spacing: DesignSystem.Spacing.xxl) {
                        // Enhanced search section
                        enhancedSearchSection
                            .animatedScaleIn(delay: 0.1)
                        
                        // Enhanced category cards
                        enhancedCategoryCards
                            .animatedScaleIn(delay: 0.2)
                    }
                    .padding(DesignSystem.Spacing.lg)
                    .padding(.top, DesignSystem.Spacing.lg)
                }
            }
            .designSystemBackground()
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showingInbox) {
            InboxView()
                .transition(AnimationSystem.Transitions.modalPresent)
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .transition(AnimationSystem.Transitions.modalPresent)
        }
        .sheet(isPresented: $showingSearchResults) {
            SearchResultsView(searchQuery: viewModel.searchText)
                .transition(AnimationSystem.Transitions.slideFromBottom)
        }
        .sheet(isPresented: $showingImportantEmails) {
            ImportantEmailsView()
                .transition(AnimationSystem.Transitions.slideFromRight)
        }
        .sheet(isPresented: $showingPromotionalEmails) {
            PromotionalEmailsView()
                .transition(AnimationSystem.Transitions.slideFromRight)
        }
        .sheet(isPresented: $showingUpcomingEvents) {
            UpcomingEventsView()
                .transition(AnimationSystem.Transitions.slideFromRight)
        }
        .onChange(of: viewModel.searchText) { searchText in
            withAnimation(AnimationSystem.Curves.smooth) {
                if !searchText.isEmpty && !viewModel.searchResults.isEmpty {
                    showingSearchResults = true
                }
            }
        }
    }
    
    // MARK: - Header With Actions
    private var headerWithActions: some View {
        HStack {
            // App title
            Text("Seline")
                .font(DesignSystem.Typography.title1)
                .primaryText()
            
            Spacer()
            
            // Settings button
            Button(action: {
                showingSettings = true
            }) {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundColor(DesignSystem.Colors.accent)
            }
            
            // Inbox button
            Button(action: {
                showingInbox = true
            }) {
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "tray.fill")
                        .font(.callout)
                    Text("Inbox")
                        .font(DesignSystem.Typography.bodyMedium)
                }
                .foregroundColor(.white)
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .background(DesignSystem.Colors.accent)
                .cornerRadius(DesignSystem.CornerRadius.sm)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.systemBackground)
        .overlay(
            Rectangle()
                .fill(DesignSystem.Colors.systemBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }
    
    // MARK: - Enhanced Search Section
    private var enhancedSearchSection: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            // Welcome message with loading state
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("Smart Email Management")
                    .font(DesignSystem.Typography.title2)
                    .primaryText()
                    .multilineTextAlignment(.center)
                
                if viewModel.isLoading {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading emails...")
                            .font(DesignSystem.Typography.body)
                            .secondaryText()
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                } else {
                    Text("Find and organize your emails with intelligent search")
                        .font(DesignSystem.Typography.body)
                        .secondaryText()
                        .multilineTextAlignment(.center)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: viewModel.isLoading)
            
            // Enhanced search box
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                HStack(spacing: DesignSystem.Spacing.md) {
                    Image(systemName: "magnifyingglass")
                        .font(.title3)
                        .foregroundColor(viewModel.searchText.isEmpty ? DesignSystem.Colors.systemTextSecondary : DesignSystem.Colors.accent)
                        .animation(.easeInOut(duration: 0.2), value: viewModel.searchText.isEmpty)
                    
                    TextField("Search your emails...", text: $viewModel.searchText)
                        .font(DesignSystem.Typography.headline)
                        .foregroundColor(DesignSystem.Colors.systemTextPrimary)
                        .submitLabel(.search)
                        .onSubmit {
                            if !viewModel.searchText.isEmpty {
                                showingSearchResults = true
                            }
                        }
                    
                    if !viewModel.searchText.isEmpty {
                        Button(action: {
                            viewModel.searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundColor(DesignSystem.Colors.systemTextSecondary)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(DesignSystem.Spacing.lg)
                .background(DesignSystem.Colors.systemSecondaryBackground)
                .cornerRadius(DesignSystem.CornerRadius.lg)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                        .stroke(
                            viewModel.searchText.isEmpty ? 
                            DesignSystem.Colors.systemBorder : 
                            DesignSystem.Colors.accent.opacity(0.5), 
                            lineWidth: viewModel.searchText.isEmpty ? 1 : 2
                        )
                        .animation(.easeInOut(duration: 0.2), value: viewModel.searchText.isEmpty)
                )
                .shadow(color: DesignSystem.Shadow.light, radius: 8, x: 0, y: 2)
                .scaleEffect(viewModel.searchText.isEmpty ? 1.0 : 1.02)
                .animation(.easeInOut(duration: 0.2), value: viewModel.searchText.isEmpty)
                
                // Search suggestions/recent searches (when text is entered)
                if !viewModel.searchText.isEmpty && !viewModel.searchResults.isEmpty {
                    HStack {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption)
                            .foregroundColor(DesignSystem.Colors.systemTextSecondary)
                        
                        Text("\(viewModel.searchResults.count) results found")
                            .font(DesignSystem.Typography.caption)
                            .secondaryText()
                        
                        Spacer()
                        
                        Button("View All") {
                            showingSearchResults = true
                        }
                        .font(DesignSystem.Typography.caption)
                        .accentColor()
                    }
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: viewModel.searchText.isEmpty)
        }
    }
    
    // MARK: - Enhanced Category Cards
    private var enhancedCategoryCards: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            HStack {
                Text("Quick Access")
                    .font(DesignSystem.Typography.title3)
                    .primaryText()
                
                Spacer()
                
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            if viewModel.isLoading {
                // Skeleton loading state
                VStack(spacing: DesignSystem.Spacing.md) {
                    ForEach(0..<3, id: \.self) { _ in
                        SkeletonCategoryCard()
                    }
                }
                .transition(.opacity)
            } else {
                VStack(spacing: DesignSystem.Spacing.md) {
                    EnhancedCategoryCard(
                        icon: "exclamationmark.circle.fill",
                        title: "Important",
                        subtitle: "Priority emails and urgent messages",
                        color: .red,
                        count: viewModel.importantEmails.count,
                        action: { showingImportantEmails = true }
                    )
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    
                    EnhancedCategoryCard(
                        icon: "tag.fill",
                        title: "Promotional",
                        subtitle: "Offers, deals, and marketing emails",
                        color: .orange,
                        count: viewModel.promotionalEmails.count,
                        action: { showingPromotionalEmails = true }
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    
                    EnhancedCategoryCard(
                        icon: "calendar.circle.fill",
                        title: "Upcoming Events",
                        subtitle: "Calendar invites and meeting requests",
                        color: DesignSystem.Colors.notionBlue,
                        count: viewModel.calendarEmails.count,
                        action: { showingUpcomingEvents = true }
                    )
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }
            }
        }
        .animation(.easeInOut(duration: 0.5), value: viewModel.isLoading)
    }
    
    // MARK: - Helper Methods
    
    private func performRefresh() async {
        isRefreshing = true
        await viewModel.refresh()
        
        // Add a slight delay for better UX
        try? await Task.sleep(nanoseconds: 500_000_000)
        isRefreshing = false
    }
    
}

// MARK: - Enhanced Category Card Component
struct EnhancedCategoryCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let count: Int
    let action: () -> Void
    
    @State private var isPressed = false
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            // Add haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            
            withAnimation(AnimationSystem.Curves.bouncy) {
                action()
            }
        }) {
            HStack(spacing: DesignSystem.Spacing.lg) {
                // Enhanced icon with gradient and animation
                ZStack {
                    Circle()
                        .fill(color.opacity(isPressed ? 0.3 : isHovered ? 0.2 : 0.1))
                        .frame(width: 56, height: 56)
                        .overlay(
                            Circle()
                                .stroke(color.opacity(isHovered ? 0.4 : 0.3), lineWidth: isHovered ? 2 : 1)
                        )
                        .scaleEffect(isPressed ? 0.9 : isHovered ? 1.1 : 1.0)
                    
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundStyle(color.gradient)
                        .scaleEffect(isPressed ? 0.8 : isHovered ? 1.1 : 1.0)
                        .rotationEffect(.degrees(isHovered ? 5 : 0))
                }
                .animation(AnimationSystem.MicroInteractions.buttonPress(), value: isPressed)
                .animation(AnimationSystem.MicroInteractions.cardHover(), value: isHovered)
                
                // Enhanced content
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(title)
                            .font(DesignSystem.Typography.headline)
                            .foregroundColor(DesignSystem.Colors.systemTextPrimary)
                        
                        Spacer()
                        
                        // Enhanced count badge with pulsing animation
                        if count > 0 {
                            Text("\(count)")
                                .font(DesignSystem.Typography.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(color.gradient)
                                        .shadow(color: color.opacity(0.3), radius: 2, x: 0, y: 1)
                                )
                                .scaleEffect(isHovered ? 1.15 : 1.0)
                                .animation(AnimationSystem.Curves.bouncy, value: isHovered)
                        } else {
                            Text("0")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.systemTextSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(DesignSystem.Colors.systemBorder)
                                )
                        }
                    }
                    
                    Text(subtitle)
                        .font(DesignSystem.Typography.subheadline)
                        .foregroundColor(DesignSystem.Colors.systemTextSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineLimit(2)
                }
                
                // Animated chevron with enhanced effects
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(isHovered ? color : DesignSystem.Colors.systemTextSecondary)
                    .scaleEffect(isHovered ? 1.2 : 1.0)
                    .offset(x: isHovered ? 4 : 0)
                    .animation(AnimationSystem.MicroInteractions.iconBounce(), value: isHovered)
            }
            .padding(DesignSystem.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                    .fill(DesignSystem.Colors.systemSecondaryBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                            .stroke(
                                isHovered ? color.opacity(0.3) : DesignSystem.Colors.systemBorder, 
                                lineWidth: isHovered ? 2 : 1
                            )
                    )
            )
            .scaleEffect(isPressed ? 0.95 : isHovered ? 1.02 : 1.0)
            .shadow(
                color: isHovered ? color.opacity(0.2) : DesignSystem.Shadow.light, 
                radius: isHovered ? 12 : 4, 
                x: 0, 
                y: isHovered ? 6 : 2
            )
            .hoverAnimation(isHovered: isHovered)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0.0, maximumDistance: .infinity) {
            // Long press action with haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
            impactFeedback.impactOccurred()
        } onPressingChanged: { pressing in
            withAnimation(AnimationSystem.MicroInteractions.buttonPress()) {
                isPressed = pressing
            }
        }
        .onHover { hovering in
            withAnimation(AnimationSystem.MicroInteractions.cardHover()) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Skeleton Category Card
struct SkeletonCategoryCard: View {
    @State private var animateGradient = false
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.lg) {
            // Skeleton icon
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            DesignSystem.Colors.systemBorder,
                            DesignSystem.Colors.systemBorder.opacity(0.5),
                            DesignSystem.Colors.systemBorder
                        ],
                        startPoint: animateGradient ? .leading : .trailing,
                        endPoint: animateGradient ? .trailing : .leading
                    )
                )
                .frame(width: 56, height: 56)
            
            // Skeleton content
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    DesignSystem.Colors.systemBorder,
                                    DesignSystem.Colors.systemBorder.opacity(0.5),
                                    DesignSystem.Colors.systemBorder
                                ],
                                startPoint: animateGradient ? .leading : .trailing,
                                endPoint: animateGradient ? .trailing : .leading
                            )
                        )
                        .frame(width: 80, height: 16)
                        .cornerRadius(4)
                    
                    Spacer()
                    
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    DesignSystem.Colors.systemBorder,
                                    DesignSystem.Colors.systemBorder.opacity(0.5),
                                    DesignSystem.Colors.systemBorder
                                ],
                                startPoint: animateGradient ? .leading : .trailing,
                                endPoint: animateGradient ? .trailing : .leading
                            )
                        )
                        .frame(width: 20, height: 20)
                }
                
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                DesignSystem.Colors.systemBorder,
                                DesignSystem.Colors.systemBorder.opacity(0.5),
                                DesignSystem.Colors.systemBorder
                            ],
                            startPoint: animateGradient ? .leading : .trailing,
                            endPoint: animateGradient ? .trailing : .leading
                        )
                    )
                    .frame(height: 12)
                    .cornerRadius(4)
            }
            
            // Skeleton chevron
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(DesignSystem.Colors.systemBorder)
        }
        .padding(DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.systemSecondaryBackground)
        .cornerRadius(DesignSystem.CornerRadius.lg)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                .stroke(DesignSystem.Colors.systemBorder, lineWidth: 1)
        )
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
    }
}

// MARK: - RefreshableScrollView
struct RefreshableScrollView<Content: View>: View {
    @Binding var isRefreshing: Bool
    let onRefresh: () async -> Void
    let content: Content
    
    @State private var refreshOffset: CGFloat = 0
    @State private var refreshThreshold: CGFloat = 50
    
    init(isRefreshing: Binding<Bool>, onRefresh: @escaping () async -> Void, @ViewBuilder content: () -> Content) {
        self._isRefreshing = isRefreshing
        self.onRefresh = onRefresh
        self.content = content()
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Pull to refresh indicator
                HStack {
                    if isRefreshing {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(DesignSystem.Colors.accent)
                    } else if refreshOffset > refreshThreshold {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title2)
                            .foregroundColor(DesignSystem.Colors.accent)
                            .rotationEffect(.degrees(180))
                    } else if refreshOffset > 20 {
                        Image(systemName: "arrow.down.circle")
                            .font(.title2)
                            .foregroundColor(DesignSystem.Colors.systemTextSecondary)
                    }
                }
                .frame(height: isRefreshing ? 40 : max(0, refreshOffset - 20))
                .animation(.easeInOut(duration: 0.2), value: refreshOffset)
                .animation(.easeInOut(duration: 0.3), value: isRefreshing)
                
                content
            }
        }
        .refreshable {
            await onRefresh()
        }
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView()
                .preferredColorScheme(.light)
                .previewDisplayName("Light Mode")
            
            ContentView()
                .preferredColorScheme(.dark)
                .previewDisplayName("Dark Mode")
            
            EnhancedCategoryCard(
                icon: "exclamationmark.circle.fill",
                title: "Important",
                subtitle: "Priority emails and urgent messages",
                color: .red,
                count: 5,
                action: {}
            )
            .padding()
            .previewDisplayName("Enhanced Category Card")
        }
    }
}