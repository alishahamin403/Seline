//
//  EmailDetailView.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-24.
//

import SwiftUI

struct EmailDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let email: Email
    @StateObject private var viewModel = ContentViewModel()
    @State private var showingReplyComposer = false
    @State private var showingForwardComposer = false
    @State private var isMarkedAsRead = false
    @State private var isMarkedAsImportant = false
    @State private var showingAttachmentPreview = false
    @State private var selectedAttachment: EmailAttachment?
    @State private var scrollOffset: CGFloat = 0
    @State private var contentStructure = EmailContentStructure()
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        // Email header with sender info
                        emailHeader
                        
                        // Email content
                        emailContent
                        
                        // Attachments section
                        if !email.attachments.isEmpty {
                            attachmentsSection
                        }
                        
                        // Related emails section
                        relatedEmailsSection
                    }
                    .background(
                        GeometryReader { proxy in
                            Color.clear
                                .preference(key: ScrollOffsetPreferenceKey.self, value: proxy.frame(in: .named("scroll")).origin.y)
                        }
                    )
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { value in
                    scrollOffset = value
                }
            }
            .designSystemBackground()
            .navigationTitle("Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Back") {
                        dismiss()
                    }
                    .font(DesignSystem.Typography.body)
                    .accentColor()
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        // Mark as important
                        Button(action: toggleImportant) {
                            Image(systemName: isMarkedAsImportant ? "exclamationmark.circle.fill" : "exclamationmark.circle")
                                .font(.title3)
                                .foregroundColor(isMarkedAsImportant ? .red : DesignSystem.Colors.systemTextSecondary)
                        }
                        
                        // More actions menu
                        Menu {
                            Button(action: {
                                // Archive action
                            }) {
                                Label("Archive", systemImage: "archivebox")
                            }
                            
                            Button(action: {
                                // Move to folder
                            }) {
                                Label("Move to Folder", systemImage: "folder")
                            }
                            
                            Button(action: {
                                // Mark as spam
                            }) {
                                Label("Mark as Spam", systemImage: "exclamationmark.octagon")
                            }
                            
                            Divider()
                            
                            Button(role: .destructive, action: {
                                // Delete action
                            }) {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                                .foregroundColor(DesignSystem.Colors.systemTextSecondary)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                quickActionBar
            }
        }
        .sheet(isPresented: $showingReplyComposer) {
            EmailComposerView(replyTo: email)
        }
        .sheet(isPresented: $showingForwardComposer) {
            EmailComposerView(forward: email)
        }
        .sheet(item: $selectedAttachment) { attachment in
            AttachmentPreviewView(attachment: attachment)
        }
        .onAppear {
            isMarkedAsRead = email.isRead
            isMarkedAsImportant = email.isImportant
            
            // Mark as read when opened
            if !email.isRead {
                markAsRead()
            }
        }
    }
    
    // MARK: - Email Header
    
    private var emailHeader: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            // Sender info with avatar
            HStack(spacing: DesignSystem.Spacing.md) {
                // Sender avatar
                ZStack {
                    Circle()
                        .fill(senderColor.opacity(0.1))
                        .frame(width: 60, height: 60)
                        .overlay(
                            Circle()
                                .stroke(senderColor.opacity(0.3), lineWidth: 2)
                        )
                    
                    if let firstLetter = email.sender.displayName.first {
                        Text(String(firstLetter).uppercased())
                            .font(DesignSystem.Typography.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(senderColor)
                    }
                    
                    // Status indicators
                    if !isMarkedAsRead {
                        Circle()
                            .fill(DesignSystem.Colors.accent)
                            .frame(width: 12, height: 12)
                            .offset(x: 18, y: -18)
                    }
                    
                    if isMarkedAsImportant {
                        Circle()
                            .fill(.red)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Image(systemName: "exclamationmark")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            )
                            .offset(x: 18, y: 18)
                    }
                }
                
                // Sender details
                VStack(alignment: .leading, spacing: 4) {
                    Text(email.sender.displayName)
                        .font(DesignSystem.Typography.headline)
                        .primaryText()
                    
                    Text(email.sender.email)
                        .font(DesignSystem.Typography.subheadline)
                        .secondaryText()
                    
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Text(formatDate(email.date))
                            .font(DesignSystem.Typography.caption)
                            .secondaryText()
                        
                        if email.hasCalendarEvent {
                            Label("Meeting", systemImage: "calendar")
                                .font(DesignSystem.Typography.caption2)
                                .foregroundColor(DesignSystem.Colors.notionBlue)
                        }
                        
                        if email.isPromotional {
                            Label("Promo", systemImage: "tag")
                                .font(DesignSystem.Typography.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                Spacer()
            }
            
            // Subject
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                HStack {
                    Text("Subject")
                        .font(DesignSystem.Typography.caption)
                        .fontWeight(.medium)
                        .secondaryText()
                    
                    Spacer()
                }
                
                Text(email.subject)
                    .font(DesignSystem.Typography.title3)
                    .fontWeight(.semibold)
                    .primaryText()
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Recipients
            if email.recipients.count > 1 {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    HStack {
                        Text("To:")
                            .font(DesignSystem.Typography.caption)
                            .fontWeight(.medium)
                            .secondaryText()
                        
                        Spacer()
                    }
                    
                    Text(email.recipients.map { $0.displayName }.joined(separator: ", "))
                        .font(DesignSystem.Typography.subheadline)
                        .secondaryText()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                .fill(DesignSystem.Colors.systemSecondaryBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                        .stroke(DesignSystem.Colors.systemBorder, lineWidth: 1)
                )
        )
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.top, DesignSystem.Spacing.lg)
    }
    
    // MARK: - Email Content (Enhanced)
    
    private var emailContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            // Content header with enhanced info
            HStack {
                Text("Message")
                    .font(DesignSystem.Typography.bodyMedium)
                    .fontWeight(.semibold)
                    .primaryText()
                
                Spacer()
                
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Text("\(email.body.count) characters")
                        .font(DesignSystem.Typography.caption)
                        .secondaryText()
                    
                    if contentStructure.meetingInfo != nil {
                        Label("Meeting", systemImage: "video")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }
            
            // Enhanced formatted email content
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.lg) {
                    // Main content with rich formatting
                    Text(EnhancedTextRenderer.formatEmailBody(email.body))
                        .textSelection(.enabled)
                        .lineSpacing(4)
                    
                    // Meeting information card (if detected)
                    if let meetingInfo = contentStructure.meetingInfo {
                        MeetingInfoCard(meetingInfo: meetingInfo)
                            .animatedScaleIn(delay: 0.1)
                    }
                    
                    // Action items section
                    if !contentStructure.actionItems.isEmpty {
                        ActionItemsSection(actionItems: contentStructure.actionItems)
                            .animatedScaleIn(delay: 0.2)
                    }
                    
                    // Important dates
                    if !contentStructure.dates.isEmpty {
                        ImportantDatesSection(dates: contentStructure.dates)
                            .animatedScaleIn(delay: 0.3)
                    }
                    
                    // Extract and display links with enhanced previews
                    if !extractedLinks.isEmpty {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("Links")
                                .font(DesignSystem.Typography.bodyMedium)
                                .fontWeight(.semibold)
                                .primaryText()
                            
                            ForEach(extractedLinks, id: \.self) { link in
                                EnhancedLinkPreviewCard(url: link)
                                    .animatedSlideIn(delay: 0.1)
                            }
                        }
                        .animatedScaleIn(delay: 0.4)
                    }
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                    .fill(DesignSystem.Colors.systemBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                            .stroke(DesignSystem.Colors.systemBorder, lineWidth: 1)
                    )
            )
            .frame(minHeight: 200)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.top, DesignSystem.Spacing.md)
        .onAppear {
            // Parse content structure with animation
            withAnimation(AnimationSystem.Curves.smooth.delay(0.3)) {
                contentStructure = EnhancedTextRenderer.extractContentStructure(from: email.body)
            }
        }
    }
    
    // MARK: - Attachments Section
    
    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                Text("Attachments")
                    .font(DesignSystem.Typography.bodyMedium)
                    .fontWeight(.semibold)
                    .primaryText()
                
                Spacer()
                
                Text("\(email.attachments.count) file\(email.attachments.count == 1 ? "" : "s")")
                    .font(DesignSystem.Typography.caption)
                    .secondaryText()
            }
            
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: DesignSystem.Spacing.sm),
                GridItem(.flexible(), spacing: DesignSystem.Spacing.sm)
            ], spacing: DesignSystem.Spacing.sm) {
                ForEach(email.attachments) { attachment in
                    AttachmentCard(attachment: attachment) {
                        selectedAttachment = attachment
                        showingAttachmentPreview = true
                    }
                }
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.top, DesignSystem.Spacing.md)
    }
    
    // MARK: - Related Emails Section
    
    private var relatedEmailsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                Text("Related Emails")
                    .font(DesignSystem.Typography.bodyMedium)
                    .fontWeight(.semibold)
                    .primaryText()
                
                Spacer()
                
                Button("View All") {
                    // Show related emails
                }
                .font(DesignSystem.Typography.caption)
                .accentColor()
            }
            
            // Mock related emails - in real app would fetch from same sender or thread
            VStack(spacing: DesignSystem.Spacing.xs) {
                RelatedEmailRow(
                    subject: "Re: \(email.subject)",
                    sender: email.sender.displayName,
                    date: Calendar.current.date(byAdding: .day, value: -1, to: email.date) ?? email.date
                )
                
                RelatedEmailRow(
                    subject: "Follow up: \(email.subject)",
                    sender: "You",
                    date: Calendar.current.date(byAdding: .day, value: -3, to: email.date) ?? email.date
                )
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.top, DesignSystem.Spacing.md)
        .padding(.bottom, 100) // Space for action bar
    }
    
    // MARK: - Quick Action Bar
    
    private var quickActionBar: some View {
        HStack(spacing: DesignSystem.Spacing.lg) {
            // Reply
            Button(action: {
                showingReplyComposer = true
            }) {
                VStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.title2)
                    Text("Reply")
                        .font(DesignSystem.Typography.caption)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.accent)
                .cornerRadius(DesignSystem.CornerRadius.md)
            }
            
            // Forward
            Button(action: {
                showingForwardComposer = true
            }) {
                VStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "arrowshape.turn.up.right")
                        .font(.title2)
                    Text("Forward")
                        .font(DesignSystem.Typography.caption)
                }
                .foregroundColor(DesignSystem.Colors.systemTextPrimary)
                .frame(maxWidth: .infinity)
                .padding(DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.systemSecondaryBackground)
                .cornerRadius(DesignSystem.CornerRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                        .stroke(DesignSystem.Colors.systemBorder, lineWidth: 1)
                )
            }
            
            // Archive
            Button(action: {
                // Archive email
            }) {
                VStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "archivebox")
                        .font(.title2)
                    Text("Archive")
                        .font(DesignSystem.Typography.caption)
                }
                .foregroundColor(DesignSystem.Colors.systemTextPrimary)
                .frame(maxWidth: .infinity)
                .padding(DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.systemSecondaryBackground)
                .cornerRadius(DesignSystem.CornerRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                        .stroke(DesignSystem.Colors.systemBorder, lineWidth: 1)
                )
            }
            
            // Delete
            Button(action: {
                // Delete email
            }) {
                VStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "trash")
                        .font(.title2)
                    Text("Delete")
                        .font(DesignSystem.Typography.caption)
                }
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding(DesignSystem.Spacing.md)
                .background(Color.red.opacity(0.1))
                .cornerRadius(DesignSystem.CornerRadius.md)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.md)
        .background(
            Rectangle()
                .fill(DesignSystem.Colors.systemBackground)
                .shadow(color: DesignSystem.Shadow.medium, radius: 8, x: 0, y: -2)
        )
    }
    
    // MARK: - Helper Properties
    
    private var senderColor: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .red, .pink]
        return colors[email.sender.email.hash % colors.count]
    }
    
    private var extractedLinks: [String] {
        // Simple link extraction - in real app would use more sophisticated parsing
        let body = email.body
        var links: [String] = []
        
        if body.contains("zoom.us") {
            links.append("https://zoom.us/join")
        }
        if body.contains("teams.microsoft.com") {
            links.append("https://teams.microsoft.com/join")
        }
        if body.contains("meet.google.com") {
            links.append("https://meet.google.com/join")
        }
        
        return links
    }
    
    // MARK: - Helper Methods
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatEmailBody(_ body: String) -> AttributedString {
        var attributedString = AttributedString(body)
        
        // Make links clickable (simplified)
        let linkKeywords = ["zoom.us", "teams.microsoft.com", "meet.google.com", "http://", "https://"]
        for keyword in linkKeywords {
            if let range = attributedString.range(of: keyword, options: .caseInsensitive) {
                attributedString[range].foregroundColor = DesignSystem.Colors.accent
                attributedString[range].underlineStyle = .single
            }
        }
        
        return attributedString
    }
    
    private func markAsRead() {
        viewModel.markEmailAsRead(email.id)
        isMarkedAsRead = true
    }
    
    private func toggleImportant() {
        viewModel.markEmailAsImportant(email.id)
        isMarkedAsImportant.toggle()
    }
}

// MARK: - Enhanced Supporting Views

struct MeetingInfoCard: View {
    let meetingInfo: MeetingInfo
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Button(action: {
                withAnimation(AnimationSystem.Curves.bouncy) {
                    isExpanded.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "video.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Meeting Detected")
                            .font(DesignSystem.Typography.bodyMedium)
                            .primaryText()
                        
                        if let title = meetingInfo.title {
                            Text(title)
                                .font(DesignSystem.Typography.subheadline)
                                .secondaryText()
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(DesignSystem.Colors.systemTextSecondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .animation(AnimationSystem.Curves.easeInOut, value: isExpanded)
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            if isExpanded {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    if let time = meetingInfo.time {
                        Label(time, systemImage: "clock")
                            .font(DesignSystem.Typography.subheadline)
                            .foregroundColor(DesignSystem.Colors.systemTextPrimary)
                    }
                    
                    if let joinUrl = meetingInfo.joinUrl {
                        Button(action: {
                            // Open meeting URL
                            if let url = URL(string: joinUrl) {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            HStack {
                                Image(systemName: "link")
                                    .font(.caption)
                                Text("Join Meeting")
                                    .font(DesignSystem.Typography.bodyMedium)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.blue.gradient)
                            .cornerRadius(8)
                        }
                        .buttonStyle(AnimatedButtonStyle())
                    }
                }
                .transition(AnimationSystem.Transitions.slideFromBottom)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                .fill(Color.blue.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                        .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

struct ActionItemsSection: View {
    let actionItems: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Image(systemName: "checkmark.circle")
                    .font(.title3)
                    .foregroundColor(.green)
                
                Text("Action Items")
                    .font(DesignSystem.Typography.bodyMedium)
                    .fontWeight(.semibold)
                    .primaryText()
            }
            
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                ForEach(Array(actionItems.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                        
                        Text(item)
                            .font(DesignSystem.Typography.subheadline)
                            .primaryText()
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .animatedSlideIn(from: .leading, delay: Double(index) * 0.1)
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                .fill(Color.green.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                        .stroke(Color.green.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

struct ImportantDatesSection: View {
    let dates: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Image(systemName: "calendar.circle")
                    .font(.title3)
                    .foregroundColor(.orange)
                
                Text("Important Dates")
                    .font(DesignSystem.Typography.bodyMedium)
                    .fontWeight(.semibold)
                    .primaryText()
            }
            
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                ForEach(Array(dates.enumerated()), id: \.offset) { index, date in
                    HStack {
                        Image(systemName: "calendar")
                            .font(.caption)
                            .foregroundColor(.orange)
                        
                        Text(date)
                            .font(DesignSystem.Typography.subheadline)
                            .primaryText()
                    }
                    .animatedSlideIn(from: .trailing, delay: Double(index) * 0.1)
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                .fill(Color.orange.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

struct EnhancedLinkPreviewCard: View {
    let url: String
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            if let url = URL(string: url) {
                UIApplication.shared.open(url)
            }
        }) {
            HStack(spacing: DesignSystem.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(linkColor.opacity(0.1))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: linkIcon)
                        .font(.title3)
                        .foregroundColor(linkColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(linkTitle)
                        .font(DesignSystem.Typography.bodyMedium)
                        .primaryText()
                        .lineLimit(1)
                    
                    Text(url)
                        .font(DesignSystem.Typography.caption)
                        .secondaryText()
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundColor(linkColor)
                    .scaleEffect(isHovered ? 1.2 : 1.0)
                    .animation(AnimationSystem.MicroInteractions.iconBounce(), value: isHovered)
            }
            .padding(DesignSystem.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                    .fill(DesignSystem.Colors.systemSecondaryBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                            .stroke(isHovered ? linkColor.opacity(0.3) : DesignSystem.Colors.systemBorder, lineWidth: 1)
                    )
            )
            .hoverAnimation(isHovered: isHovered)
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private var linkIcon: String {
        if url.contains("zoom") || url.contains("teams") || url.contains("meet") {
            return "video.fill"
        } else if url.contains("calendar") || url.contains("cal.com") {
            return "calendar"
        } else if url.contains("drive.google.com") || url.contains("dropbox") {
            return "folder.fill"
        } else {
            return "link"
        }
    }
    
    private var linkColor: Color {
        if url.contains("zoom") || url.contains("teams") || url.contains("meet") {
            return .blue
        } else if url.contains("calendar") {
            return .orange
        } else if url.contains("drive") || url.contains("dropbox") {
            return .green
        } else {
            return DesignSystem.Colors.accent
        }
    }
    
    private var linkTitle: String {
        if url.contains("zoom") {
            return "Join Zoom Meeting"
        } else if url.contains("teams") {
            return "Join Teams Meeting"
        } else if url.contains("meet") {
            return "Join Google Meet"
        } else if url.contains("calendar") {
            return "Calendar Event"
        } else if url.contains("drive") {
            return "Google Drive"
        } else if url.contains("dropbox") {
            return "Dropbox"
        } else {
            return "Web Link"
        }
    }
}

// MARK: - Supporting Views

struct AttachmentCard: View {
    let attachment: EmailAttachment
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: fileIcon)
                    .font(.title)
                    .foregroundColor(fileColor)
                
                Text(attachment.filename)
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.medium)
                    .primaryText()
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                Text(formatFileSize(attachment.size))
                    .font(DesignSystem.Typography.caption2)
                    .secondaryText()
            }
            .padding(DesignSystem.Spacing.md)
            .frame(minHeight: 80)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .fill(DesignSystem.Colors.systemSecondaryBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                            .stroke(DesignSystem.Colors.systemBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var fileIcon: String {
        let ext = attachment.filename.components(separatedBy: ".").last?.lowercased() ?? ""
        switch ext {
        case "pdf": return "doc.richtext"
        case "jpg", "jpeg", "png": return "photo"
        case "doc", "docx": return "doc.text"
        case "xls", "xlsx": return "tablecells"
        case "zip": return "archivebox"
        default: return "doc"
        }
    }
    
    private var fileColor: Color {
        let ext = attachment.filename.components(separatedBy: ".").last?.lowercased() ?? ""
        switch ext {
        case "pdf": return .red
        case "jpg", "jpeg", "png": return .blue
        case "doc", "docx": return .blue
        case "xls", "xlsx": return .green
        case "zip": return .orange
        default: return .gray
        }
    }
    
    private func formatFileSize(_ size: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
}

struct LinkPreviewCard: View {
    let url: String
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: linkIcon)
                .font(.title3)
                .foregroundColor(linkColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(linkTitle)
                    .font(DesignSystem.Typography.bodyMedium)
                    .primaryText()
                
                Text(url)
                    .font(DesignSystem.Typography.caption)
                    .secondaryText()
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button("Open") {
                // Open link
            }
            .font(DesignSystem.Typography.caption)
            .accentColor()
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                .fill(DesignSystem.Colors.systemSecondaryBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                        .stroke(DesignSystem.Colors.systemBorder, lineWidth: 1)
                )
        )
    }
    
    private var linkIcon: String {
        if url.contains("zoom") {
            return "video"
        } else if url.contains("teams") {
            return "video"
        } else if url.contains("meet") {
            return "video"
        } else {
            return "link"
        }
    }
    
    private var linkColor: Color {
        if url.contains("zoom") || url.contains("teams") || url.contains("meet") {
            return .blue
        } else {
            return DesignSystem.Colors.accent
        }
    }
    
    private var linkTitle: String {
        if url.contains("zoom") {
            return "Join Zoom Meeting"
        } else if url.contains("teams") {
            return "Join Teams Meeting"
        } else if url.contains("meet") {
            return "Join Google Meet"
        } else {
            return "Web Link"
        }
    }
}

struct RelatedEmailRow: View {
    let subject: String
    let sender: String
    let date: Date
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(subject)
                    .font(DesignSystem.Typography.subheadline)
                    .primaryText()
                    .lineLimit(1)
                
                Text("From: \(sender)")
                    .font(DesignSystem.Typography.caption)
                    .secondaryText()
            }
            
            Spacer()
            
            Text(RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date()))
                .font(DesignSystem.Typography.caption)
                .secondaryText()
        }
        .padding(DesignSystem.Spacing.sm)
        .background(DesignSystem.Colors.systemSecondaryBackground)
        .cornerRadius(DesignSystem.CornerRadius.sm)
    }
}

// MARK: - Placeholder Views

struct EmailComposerView: View {
    let replyTo: Email?
    let forward: Email?
    
    init(replyTo: Email) {
        self.replyTo = replyTo
        self.forward = nil
    }
    
    init(forward: Email) {
        self.forward = forward
        self.replyTo = nil
    }
    
    var body: some View {
        Text("Email Composer (Coming Soon)")
            .font(DesignSystem.Typography.title2)
            .primaryText()
    }
}

struct AttachmentPreviewView: View {
    let attachment: EmailAttachment
    
    var body: some View {
        Text("Attachment Preview: \(attachment.filename)")
            .font(DesignSystem.Typography.title2)
            .primaryText()
    }
}

// MARK: - Scroll Offset Preference Key

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Preview

struct EmailDetailView_Previews: PreviewProvider {
    static var previews: some View {
        EmailDetailView(email: Email(
            id: "preview_1",
            subject: "Important Meeting Tomorrow",
            sender: EmailContact(name: "John Doe", email: "john@company.com"),
            recipients: [EmailContact(name: "You", email: "you@company.com")],
            body: "Hi there, I wanted to remind you about our important meeting scheduled for tomorrow at 10 AM. Please make sure to review the attached documents beforehand. The meeting will cover our quarterly goals and the upcoming project timeline. Looking forward to seeing you there!",
            date: Date(),
            isRead: false,
            isImportant: true,
            labels: ["INBOX", "IMPORTANT"],
            attachments: [
                EmailAttachment(filename: "Meeting_Agenda.pdf", mimeType: "application/pdf", size: 245760)
            ]
        ))
    }
}