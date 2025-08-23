//
//  InboxView.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-24.
//

import SwiftUI

struct InboxView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ContentViewModel()
    @State private var selectedFilter: InboxFilter = .all
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Filter tabs
                filterTabs
                
                // Email list
                if viewModel.isLoading {
                    loadingView
                } else if viewModel.emails.isEmpty {
                    emptyStateView
                } else {
                    emailList
                }
            }
            .designSystemBackground()
            .navigationTitle("Inbox")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(DesignSystem.Typography.bodyMedium)
                    .accentColor()
                }
            }
        }
        .onAppear {
            Task {
                await viewModel.loadEmails()
            }
        }
    }
    
    // MARK: - Filter Tabs
    
    private var filterTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                ForEach(InboxFilter.allCases, id: \.self) { filter in
                    FilterTab(
                        filter: filter,
                        isSelected: selectedFilter == filter,
                        count: getCount(for: filter)
                    ) {
                        selectedFilter = filter
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
        }
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(DesignSystem.Colors.systemSecondaryBackground)
    }
    
    private func getCount(for filter: InboxFilter) -> Int {
        switch filter {
        case .all:
            return viewModel.emails.count
        case .unread:
            return viewModel.emails.filter { !$0.isRead }.count
        case .important:
            return viewModel.importantEmails.count
        case .promotional:
            return viewModel.promotionalEmails.count
        case .calendar:
            return viewModel.calendarEmails.count
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(DesignSystem.Colors.accent)
            
            Text("Loading emails...")
                .font(DesignSystem.Typography.body)
                .secondaryText()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundColor(DesignSystem.Colors.systemTextSecondary)
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("No emails found")
                    .font(DesignSystem.Typography.title3)
                    .primaryText()
                
                Text("Your inbox is empty or all emails have been read")
                    .font(DesignSystem.Typography.body)
                    .secondaryText()
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignSystem.Spacing.lg)
    }
    
    // MARK: - Email List
    
    private var emailList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(filteredEmails) { email in
                    EmailRow(email: email) {
                        // Handle email tap
                    }
                    
                    Divider()
                        .padding(.leading, DesignSystem.Spacing.lg)
                }
            }
        }
    }
    
    private var filteredEmails: [Email] {
        switch selectedFilter {
        case .all:
            return viewModel.emails
        case .unread:
            return viewModel.emails.filter { !$0.isRead }
        case .important:
            return viewModel.importantEmails
        case .promotional:
            return viewModel.promotionalEmails
        case .calendar:
            return viewModel.calendarEmails
        }
    }
}

// MARK: - Inbox Filter

enum InboxFilter: String, CaseIterable {
    case all = "All"
    case unread = "Unread"
    case important = "Important"
    case promotional = "Promotional"
    case calendar = "Calendar"
    
    var icon: String {
        switch self {
        case .all:
            return "tray.fill"
        case .unread:
            return "envelope.fill"
        case .important:
            return "exclamationmark.circle.fill"
        case .promotional:
            return "tag.fill"
        case .calendar:
            return "calendar.circle.fill"
        }
    }
}

// MARK: - Filter Tab

struct FilterTab: View {
    let filter: InboxFilter
    let isSelected: Bool
    let count: Int
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: filter.icon)
                    .font(.caption)
                
                Text(filter.rawValue)
                    .font(DesignSystem.Typography.subheadline)
                
                if count > 0 {
                    Text("\(count)")
                        .font(DesignSystem.Typography.caption2)
                        .foregroundColor(isSelected ? .white : DesignSystem.Colors.systemTextSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? Color.white.opacity(0.3) : DesignSystem.Colors.systemBorder)
                        .cornerRadius(8)
                }
            }
            .foregroundColor(isSelected ? .white : DesignSystem.Colors.systemTextPrimary)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(isSelected ? DesignSystem.Colors.accent : Color.clear)
            .cornerRadius(DesignSystem.CornerRadius.sm)
        }
    }
}

// MARK: - Email Row

struct EmailRow: View {
    let email: Email
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DesignSystem.Spacing.md) {
                // Sender avatar
                Circle()
                    .fill(DesignSystem.Colors.accent.opacity(0.1))
                    .frame(width: 40, height: 40)
                    .overlay(
                        Text(String(email.sender.displayName.prefix(1).uppercased()))
                            .font(DesignSystem.Typography.bodyMedium)
                            .foregroundColor(DesignSystem.Colors.accent)
                    )
                
                // Email content
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(email.sender.displayName)
                            .font(email.isRead ? DesignSystem.Typography.body : DesignSystem.Typography.bodyMedium)
                            .primaryText()
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text(RelativeDateTimeFormatter().localizedString(for: email.date, relativeTo: Date()))
                            .font(DesignSystem.Typography.caption)
                            .secondaryText()
                    }
                    
                    Text(email.subject)
                        .font(email.isRead ? DesignSystem.Typography.subheadline : DesignSystem.Typography.callout)
                        .foregroundColor(email.isRead ? DesignSystem.Colors.systemTextSecondary : DesignSystem.Colors.systemTextPrimary)
                        .lineLimit(1)
                    
                    Text(email.body)
                        .font(DesignSystem.Typography.footnote)
                        .secondaryText()
                        .lineLimit(2)
                }
                
                // Status indicators
                VStack {
                    if !email.isRead {
                        Circle()
                            .fill(DesignSystem.Colors.accent)
                            .frame(width: 8, height: 8)
                    }
                    
                    if email.isImportant {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

struct InboxView_Previews: PreviewProvider {
    static var previews: some View {
        InboxView()
    }
}