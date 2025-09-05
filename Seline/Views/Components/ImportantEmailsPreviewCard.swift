//
//  ImportantEmailsPreviewCard.swift
//  Seline
//
//  Created by Claude Code on 2025-09-05.
//

import SwiftUI

struct ImportantEmailsPreviewCard: View {
    let emails: [Email]
    let totalCount: Int
    let onTap: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerView
            
            // Email previews or empty state
            if emails.isEmpty {
                emptyStateView
            } else {
                emailPreviewsList
            }
            
            // Footer with "See More" if there are more emails
            if totalCount > emails.count {
                footerView
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DesignSystem.Colors.surface)
                .shadow(
                    color: colorScheme == .light ? Color.black.opacity(0.06) : Color.clear,
                    radius: 8,
                    x: 0,
                    y: 4
                )
        )
        .onTapGesture {
            onTap()
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.red)
            
            // Title and count
            VStack(alignment: .leading, spacing: 2) {
                Text("Important")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("\(totalCount) email\(totalCount == 1 ? "" : "s")")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            
            Spacer()
            
            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.6))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.5))
            
            Text("No important emails")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .frame(height: 80)
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Email Previews List
    
    private var emailPreviewsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(emails.enumerated()), id: \.element.id) { index, email in
                EmailPreviewRow(email: email, isLast: index == emails.count - 1)
            }
        }
        .padding(.horizontal, 20)
    }
    
    // MARK: - Footer View
    
    private var footerView: some View {
        HStack {
            Spacer()
            
            Text("See \(totalCount - emails.count) more")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(DesignSystem.Colors.accent)
            
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(DesignSystem.Colors.accent)
            
            Spacer()
        }
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DesignSystem.Colors.accent.opacity(0.05))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}

// MARK: - Email Preview Row Component

struct EmailPreviewRow: View {
    let email: Email
    let isLast: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Sender initial or avatar
                Circle()
                    .fill(DesignSystem.Colors.accent.opacity(0.1))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(String((email.sender.name ?? "U").prefix(1)).uppercased())
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.accent)
                    )
                
                // Email content
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(email.sender.displayName)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text(formatEmailDate(email.date))
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    
                    Text(email.subject)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.vertical, 12)
            
            // Divider (except for last item)
            if !isLast {
                Rectangle()
                    .fill(DesignSystem.Colors.border.opacity(0.3))
                    .frame(height: 0.5)
                    .padding(.leading, 48) // Align with text content
            }
        }
    }
    
    private func formatEmailDate(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            let formatter = DateFormatter()
            formatter.dateFormat = "E" // Mon, Tue, etc.
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Preview

struct ImportantEmailsPreviewCard_Previews: PreviewProvider {
    static var previews: some View {
        ImportantEmailsPreviewCard(
            emails: [
                Email(
                    id: "1",
                    subject: "Important meeting tomorrow",
                    sender: EmailContact(name: "John Doe", email: "john@example.com"),
                    recipients: [EmailContact(name: "Me", email: "me@example.com")],
                    body: "Don't forget about the meeting",
                    date: Date(),
                    isRead: false,
                    isImportant: true,
                    labels: ["INBOX"],
                    attachments: [],
                    isPromotional: false,
                    hasCalendarEvent: false
                )
            ],
            totalCount: 5,
            onTap: {}
        )
        .padding()
    }
}