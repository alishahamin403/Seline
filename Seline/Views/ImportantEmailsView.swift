//
//  ImportantEmailsView.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-24.
//

import SwiftUI

struct ImportantEmailsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ContentViewModel()
    @State private var showingEmailDetail = false
    @State private var selectedEmail: Email?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with stats
                importantEmailsHeader
                
                // Email list
                if viewModel.isLoading {
                    loadingView
                } else if viewModel.importantEmails.isEmpty {
                    emptyStateView
                } else {
                    importantEmailsList
                }
            }
            .designSystemBackground()
            .navigationTitle("Important Emails")
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
        .sheet(item: $selectedEmail) { email in
            EmailDetailView(email: email)
        }
        .onAppear {
            Task {
                await viewModel.loadEmails()
            }
        }
    }
    
    // MARK: - Header
    
    private var importantEmailsHeader: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(viewModel.importantEmails.count)")
                        .font(DesignSystem.Typography.title1)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                    
                    Text("Important Emails")
                        .font(DesignSystem.Typography.subheadline)
                        .secondaryText()
                }
                
                Spacer()
                
                // Priority indicator
                ZStack {
                    Circle()
                        .fill(.red.opacity(0.1))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.red)
                }
            }
            
            // Quick stats
            if !viewModel.importantEmails.isEmpty {
                HStack(spacing: DesignSystem.Spacing.lg) {
                    StatItem(
                        value: viewModel.importantEmails.filter { !$0.isRead }.count,
                        label: "Unread",
                        color: DesignSystem.Colors.accent
                    )
                    
                    StatItem(
                        value: viewModel.importantEmails.filter { $0.date > Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date() }.count,
                        label: "Today",
                        color: .orange
                    )
                    
                    StatItem(
                        value: viewModel.importantEmails.filter { !$0.attachments.isEmpty }.count,
                        label: "With Files",
                        color: .green
                    )
                    
                    Spacer()
                }
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .background(DesignSystem.Colors.systemSecondaryBackground)
        .overlay(
            Rectangle()
                .fill(DesignSystem.Colors.systemBorder)
                .frame(height: 1),
            alignment: .bottom
        )
    }
    
    // MARK: - Email List
    
    private var importantEmailsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.importantEmails.sorted { $0.date > $1.date }) { email in
                    ImportantEmailRow(email: email) {
                        selectedEmail = email
                        showingEmailDetail = true
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    
                    if email.id != viewModel.importantEmails.last?.id {
                        Divider()
                            .padding(.leading, 80)
                    }
                }
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            ForEach(0..<5, id: \.self) { _ in
                SkeletonEmailRow()
            }
        }
        .padding(DesignSystem.Spacing.lg)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(.red.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 40))
                    .foregroundColor(.red.opacity(0.6))
            }
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("No Important Emails")
                    .font(DesignSystem.Typography.title3)
                    .primaryText()
                
                Text("Important emails will appear here when you receive them")
                    .font(DesignSystem.Typography.body)
                    .secondaryText()
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignSystem.Spacing.lg)
    }
}

// MARK: - Important Email Row

struct ImportantEmailRow: View {
    let email: Email
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DesignSystem.Spacing.md) {
                // Priority indicator and avatar
                ZStack {
                    Circle()
                        .fill(priorityColor.opacity(0.1))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Circle()
                                .stroke(priorityColor.opacity(0.3), lineWidth: 2)
                        )
                    
                    if !email.isRead {
                        // Unread indicator
                        Circle()
                            .fill(DesignSystem.Colors.accent)
                            .frame(width: 12, height: 12)
                            .offset(x: 15, y: -15)
                    }
                    
                    Text(String(email.sender.displayName.prefix(1).uppercased()))
                        .font(DesignSystem.Typography.bodyMedium)
                        .foregroundColor(priorityColor)
                }
                
                // Email content
                VStack(alignment: .leading, spacing: 6) {
                    // Header row
                    HStack {
                        Text(email.sender.displayName)
                            .font(email.isRead ? DesignSystem.Typography.body : DesignSystem.Typography.bodyMedium)
                            .primaryText()
                            .lineLimit(1)
                        
                        Spacer()
                        
                        // Priority and time
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(priorityColor)
                            
                            Text(RelativeDateTimeFormatter().localizedString(for: email.date, relativeTo: Date()))
                                .font(DesignSystem.Typography.caption)
                                .secondaryText()
                        }
                    }
                    
                    // Subject
                    Text(email.subject)
                        .font(email.isRead ? DesignSystem.Typography.subheadline : DesignSystem.Typography.callout)
                        .foregroundColor(email.isRead ? DesignSystem.Colors.systemTextSecondary : DesignSystem.Colors.systemTextPrimary)
                        .lineLimit(1)
                    
                    // Preview with highlighting for urgent keywords
                    Text(highlightUrgentKeywords(in: email.body))
                        .font(DesignSystem.Typography.footnote)
                        .secondaryText()
                        .lineLimit(2)
                    
                    // Metadata
                    HStack(spacing: DesignSystem.Spacing.md) {
                        if !email.attachments.isEmpty {
                            Label("\(email.attachments.count)", systemImage: "paperclip")
                                .font(DesignSystem.Typography.caption2)
                                .foregroundColor(DesignSystem.Colors.systemTextSecondary)
                        }
                        
                        if email.hasCalendarEvent {
                            Label("Meeting", systemImage: "calendar")
                                .font(DesignSystem.Typography.caption2)
                                .foregroundColor(DesignSystem.Colors.accent)
                        }
                        
                        Spacer()
                        
                        // Urgency indicator
                        Text(urgencyLevel)
                            .font(DesignSystem.Typography.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(priorityColor.gradient)
                            )
                    }
                }
                
                // Action indicator
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(DesignSystem.Colors.systemTextSecondary)
                    .scaleEffect(isPressed ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 0.1), value: isPressed)
            }
            .padding(DesignSystem.Spacing.lg)
            .background(DesignSystem.Colors.systemBackground)
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0.0, maximumDistance: .infinity) {
            // Long press action
        } onPressingChanged: { pressing in
            isPressed = pressing
        }
    }
    
    private var priorityColor: Color {
        if urgencyLevel == "URGENT" {
            return .red
        } else if urgencyLevel == "HIGH" {
            return .orange
        } else {
            return .yellow
        }
    }
    
    private var urgencyLevel: String {
        let urgentKeywords = ["urgent", "asap", "emergency", "critical", "deadline"]
        let highKeywords = ["important", "priority", "meeting", "action required"]
        
        let content = (email.subject + " " + email.body).lowercased()
        
        if urgentKeywords.contains(where: { content.contains($0) }) {
            return "URGENT"
        } else if highKeywords.contains(where: { content.contains($0) }) {
            return "HIGH"
        } else {
            return "NORMAL"
        }
    }
    
    private func highlightUrgentKeywords(in text: String) -> AttributedString {
        var attributedString = AttributedString(text)
        let urgentKeywords = ["urgent", "asap", "emergency", "critical", "deadline", "important"]
        
        for keyword in urgentKeywords {
            if let range = attributedString.range(of: keyword, options: .caseInsensitive) {
                attributedString[range].foregroundColor = .red
                attributedString[range].font = .system(size: 13, weight: .semibold)
            }
        }
        
        return attributedString
    }
}

// MARK: - Stat Item

struct StatItem: View {
    let value: Int
    let label: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(DesignSystem.Typography.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(label)
                .font(DesignSystem.Typography.caption)
                .secondaryText()
        }
    }
}

// MARK: - Skeleton Email Row

struct SkeletonEmailRow: View {
    @State private var animateGradient = false
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            // Skeleton avatar
            Circle()
                .fill(shimmerGradient)
                .frame(width: 50, height: 50)
            
            // Skeleton content
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Rectangle()
                        .fill(shimmerGradient)
                        .frame(width: 120, height: 16)
                        .cornerRadius(4)
                    
                    Spacer()
                    
                    Rectangle()
                        .fill(shimmerGradient)
                        .frame(width: 40, height: 12)
                        .cornerRadius(4)
                }
                
                Rectangle()
                    .fill(shimmerGradient)
                    .frame(height: 14)
                    .cornerRadius(4)
                
                Rectangle()
                    .fill(shimmerGradient)
                    .frame(width: 200, height: 12)
                    .cornerRadius(4)
                
                HStack {
                    Rectangle()
                        .fill(shimmerGradient)
                        .frame(width: 60, height: 10)
                        .cornerRadius(4)
                    
                    Spacer()
                    
                    Capsule()
                        .fill(shimmerGradient)
                        .frame(width: 50, height: 16)
                }
            }
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(DesignSystem.Colors.systemBorder)
        }
        .padding(DesignSystem.Spacing.lg)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
    }
    
    private var shimmerGradient: LinearGradient {
        LinearGradient(
            colors: [
                DesignSystem.Colors.systemBorder,
                DesignSystem.Colors.systemBorder.opacity(0.5),
                DesignSystem.Colors.systemBorder
            ],
            startPoint: animateGradient ? .leading : .trailing,
            endPoint: animateGradient ? .trailing : .leading
        )
    }
}

// MARK: - Preview

struct ImportantEmailsView_Previews: PreviewProvider {
    static var previews: some View {
        ImportantEmailsView()
    }
}