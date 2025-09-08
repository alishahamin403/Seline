//
//  MainTabView.swift
//  Seline
//
//  Created by Claude Code on 2025-09-06.
//

import SwiftUI

// MARK: - Tab Enum

enum Tab: String, CaseIterable {
    case home = "Home"
    case email = "Email"
    case calendar = "Calendar"
    case todo = "Todo"
    case notes = "Notes"
    
    var icon: String {
        switch self {
        case .home:
            return "house"
        case .email:
            return "mail"
        case .calendar:
            return "calendar.badge.clock"
        case .todo:
            return "square"
        case .notes:
            return "doc.text"
        }
    }
    
    var selectedIcon: String {
        switch self {
        case .home:
            return "house.fill"
        case .email:
            return "mail.fill"
        case .calendar:
            return "calendar.badge.clock"
        case .todo:
            return "checkmark.square.fill"
        case .notes:
            return "doc.text.fill"
        }
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @State private var selectedTab: Tab = .home
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var sharedViewModel = ContentViewModel()
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Main content area
            VStack(spacing: 0) {
                contentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Spacer for tab bar
                Spacer()
                    .frame(height: tabBarHeight)
            }
            
            // Custom tab bar
            customTabBar
        }
        .background(DesignSystem.Colors.background)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            // Load initial data when the app appears
            sharedViewModel.loadInitialData()
        }
    }
    
    // MARK: - Content View
    
    @ViewBuilder
    private var contentView: some View {
        switch selectedTab {
        case .home:
            ContentView(selectedTab: $selectedTab)
                .environmentObject(sharedViewModel)
        case .email:
            NavigationView {
                TodayEmailsView(viewModel: sharedViewModel, openAIService: OpenAIService.shared)
            }
        case .calendar:
            NavigationView {
                UpcomingEventsView(viewModel: sharedViewModel)
            }
        case .todo:
            NavigationView {
                TodoListView()
            }
        case .notes:
            NavigationView {
                NotesView()
            }
        }
    }
    
    // MARK: - Custom Tab Bar
    
    private var customTabBar: some View {
        VStack(spacing: 0) {
            // Top border
            Rectangle()
                .fill(DesignSystem.Colors.border)
                .frame(height: 0.5)
            
            // Tab buttons
            HStack(spacing: 0) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    tabButton(for: tab)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 2) // Moved tab bar up by 2 more points
            .background(DesignSystem.Colors.surface)
        }
    }
    
    private func tabButton(for tab: Tab) -> some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab
            }
        }) {
            Image(systemName: selectedTab == tab ? tab.selectedIcon : tab.icon)
                .font(.system(size: 20, weight: selectedTab == tab ? .semibold : .regular))
                .foregroundColor(selectedTab == tab ? DesignSystem.Colors.accent : DesignSystem.Colors.textSecondary)
                .scaleEffect(selectedTab == tab ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: selectedTab)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Constants
    
    private var tabBarHeight: CGFloat {
        return 65 // Moved tab bar up by 2 more points (83 - 18)
    }
}

// MARK: - Preview

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
            .preferredColorScheme(.light)
        
        MainTabView()
            .preferredColorScheme(.dark)
    }
}