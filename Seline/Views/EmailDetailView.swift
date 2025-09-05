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
    @ObservedObject var viewModel: ContentViewModel
    @State private var showingReplyComposer = false
    @State private var showingForwardComposer = false
    @State private var isMarkedAsRead = false
    @State private var isMarkedAsImportant = false
    @State private var showingAttachmentPreview = false
    @State private var selectedAttachment: EmailAttachment?
    @State private var scrollOffset: CGFloat = 0
    @State private var showingDeleteConfirmation = false
    @State private var showingError = false
    @State private var aiSummary: String = ""
    @State private var isLoadingSummary = false
    @StateObject private var openAIService = OpenAIService.shared
    @State private var contentStructure = EmailContentStructure()
    
    var body: some View {
        // Removed NavigationView to avoid conflicts when presented as sheet
        VStack {
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
            .linearBackground()
            // Custom header instead of navigation title
            .overlay(alignment: .top) {
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.left")
                                .font(.title2)
                            Text("Back")
                                .font(.system(size: 16, weight: .medium))
                        }
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    }
                    
                    Spacer()
                    
                    Text("Email")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    Spacer()
                    
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        // Mark as important
                        Button(action: toggleImportant) {
                            Image(systemName: isMarkedAsImportant ? "exclamationmark.circle.fill" : "exclamationmark.circle")
                                .font(.title3)
                                .foregroundColor(isMarkedAsImportant ? .red : DesignSystem.Colors.textSecondary)
                        }
                        
                        // More actions menu
                        Menu {
                            Button(action: archiveEmail) {
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
                            
                            Button(role: .destructive, action: deleteEmail) {
                                Label("Delete", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)
                .background(DesignSystem.Colors.surface)
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
        .alert("Delete Email", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                confirmDelete()
            }
        } message: {
            Text("Are you sure you want to delete this email? This action cannot be undone.")
        }
        .alert("Error", isPresented: $showingError, presenting: viewModel.errorMessage) { _ in
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: { errorMessage in
            Text(errorMessage)
        }
        .onChange(of: viewModel.errorMessage) { errorMessage in
            if errorMessage != nil {
                showingError = true
            }
        }
        .onAppear {
            print("📧 EmailDetailView appeared for email: \(email.id)")
            print("  - Subject: \(email.subject)")
            print("  - Sender: \(email.sender.displayName)")
            print("  - Date: \(email.date)")
            print("  - IsRead: \(email.isRead)")
            print("  - IsImportant: \(email.isImportant)")
            print("  - Body length: \(email.body.count) characters")
            print("  - Recipients count: \(email.recipients.count)")
            print("  - Attachments count: \(email.attachments.count)")
            
            // Validate email data
            if email.subject.isEmpty {
                print("  ⚠️ Warning: Email subject is empty")
            }
            if email.sender.displayName.isEmpty {
                print("  ⚠️ Warning: Sender display name is empty")
            }
            if email.body.isEmpty {
                print("  ⚠️ Warning: Email body is empty")
            }
            
            isMarkedAsRead = email.isRead
            isMarkedAsImportant = email.isImportant
            
            // Mark as read when opened
            if !email.isRead {
                print("  - Marking email as read...")
                markAsRead()
            } else {
                print("  - Email already marked as read")
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
                        .textPrimary()
                    
                    Text(email.sender.email)
                        .font(DesignSystem.Typography.subheadline)
                        .textSecondary()
                    
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Text(formatDate(email.date))
                            .font(DesignSystem.Typography.caption)
                            .textSecondary()
                        
                        
                        
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
                        .textSecondary()
                    
                    Spacer()
                }
                
                Text(email.subject)
                    .font(DesignSystem.Typography.title3)
                    .fontWeight(.semibold)
                    .textPrimary()
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Recipients
            if email.recipients.count > 1 {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    HStack {
                        Text("To:")
                            .font(DesignSystem.Typography.caption)
                            .fontWeight(.medium)
                            .textSecondary()
                        
                        Spacer()
                    }
                    
                    Text(email.recipients.map { $0.displayName }.joined(separator: ", "))
                        .font(DesignSystem.Typography.subheadline)
                        .textSecondary()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                .fill(DesignSystem.Colors.surfaceSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                        .stroke(DesignSystem.Colors.border, lineWidth: 1)
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
                    .textPrimary()
                
                Spacer()
                
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Text("\(email.body.count) characters")
                        .font(DesignSystem.Typography.caption)
                        .textSecondary()
                    
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
                    }
                    
                    // Action items section (with safety check)
                    if !contentStructure.actionItems.isEmpty && contentStructure.actionItems.count > 0 {
                        ActionItemsSection(actionItems: Array(contentStructure.actionItems.prefix(5).map { $0.text }))
                    }
                    
                    // Important dates (with safety check)
                    if !contentStructure.dates.isEmpty && contentStructure.dates.count > 0 {
                        ImportantDatesSection(dates: Array(contentStructure.dates.prefix(5).map { $0.description }))
                    }
                    
                }
                .padding(DesignSystem.Spacing.lg)
            }
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                    .fill(DesignSystem.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
                    )
            )
            .frame(minHeight: 200)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.top, DesignSystem.Spacing.md)
        .onAppear {
            // Parse content structure
            print("📧 EmailDetailView: Parsing content structure for email body (\(email.body.count) characters)")
            let parsedStructure = EnhancedTextRenderer.extractContentStructure(from: email.body)
            
            // Apply with animation
            withAnimation(AnimationSystem.Curves.smooth.delay(0.3)) {
                contentStructure = parsedStructure
            }
            
            print("✅ Content structure parsed - Action items: \(parsedStructure.actionItems.count), Dates: \(parsedStructure.dates.count)")
        }
    }
    
    // MARK: - Attachments Section
    
    private var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            HStack {
                Text("Attachments")
                    .font(DesignSystem.Typography.bodyMedium)
                    .fontWeight(.semibold)
                    .textPrimary()
                
                Spacer()
                
                Text("\(email.attachments.count) file\(email.attachments.count == 1 ? "" : "s")")
                    .font(DesignSystem.Typography.caption)
                    .textSecondary()
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
                    .textPrimary()
                
                Spacer()
                
                Button("View All") {
                    // Show related emails
                }
                .font(DesignSystem.Typography.caption)
                .textAccent()
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
    
    // MARK: - Enhanced Quick Action Bar
    
    private var quickActionBar: some View {
        HStack(spacing: DesignSystem.Spacing.lg) {
            // Reply - Primary action
            Button(action: replyToEmail) {
                VStack(spacing: DesignSystem.Spacing.xs) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Reply")
                        .font(DesignSystem.Typography.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                        .fill(DesignSystem.Colors.accent.gradient)
                        .shadow(
                            color: DesignSystem.Colors.accent.opacity(0.3),
                            radius: 8,
                            x: 0,
                            y: 3
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                                .stroke(.white.opacity(0.2), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(FloatingButtonStyle())
            
            // Secondary actions
            HStack(spacing: DesignSystem.Spacing.sm) {
                // Forward
                Button(action: forwardEmail) {
                    VStack(spacing: 4) {
                        Image(systemName: "arrowshape.turn.up.right")
                            .font(.title3)
                        Text("Forward")
                            .font(DesignSystem.Typography.caption2)
                    }
                    .textPrimary()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                            .fill(DesignSystem.Colors.surfaceSecondary)
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                                    .stroke(DesignSystem.Colors.border, lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(AnimatedButtonStyle())
                
                // Archive
                Button(action: archiveEmail) {
                    VStack(spacing: 4) {
                        Image(systemName: "archivebox")
                            .font(.title3)
                        Text("Archive")
                            .font(DesignSystem.Typography.caption2)
                    }
                    .foregroundColor(DesignSystem.Colors.success)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                            .fill(DesignSystem.Colors.success.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                                    .stroke(DesignSystem.Colors.success.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(AnimatedButtonStyle())
                
                // Delete
                Button(action: deleteEmail) {
                    VStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.title3)
                        Text("Delete")
                            .font(DesignSystem.Typography.caption2)
                    }
                    .foregroundColor(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                            .fill(Color.red.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(AnimatedButtonStyle())
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, DesignSystem.Spacing.lg)
        .padding(.vertical, DesignSystem.Spacing.lg)
        .background(
            Rectangle()
                .fill(DesignSystem.Colors.surface)
                .shadow(
                    color: DesignSystem.Colors.shadow,
                    radius: 12,
                    x: 0,
                    y: -4
                )
                .overlay(
                    Rectangle()
                        .fill(DesignSystem.Colors.border)
                        .frame(height: 1),
                    alignment: .top
                )
        )
    }
    
    // MARK: - Helper Properties
    
    private var senderColor: Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .red, .pink]
        // FIX: avoid negative index from hash
        let index = abs(email.sender.email.hashValue) % colors.count
        return colors[index]
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
        return EmailFormatters.formatFullDate(date)
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
        Task {
            await viewModel.markEmailAsRead(email.id)
            isMarkedAsRead = true
        }
    }
    
    private func toggleImportant() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        isMarkedAsImportant.toggle()
        viewModel.markEmailAsImportant(email.id)
    }
    
    private func toggleReadStatus() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        isMarkedAsRead.toggle()
        viewModel.toggleReadStatus(email.id, isRead: email.isRead)
    }
    
    private func archiveEmail() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        viewModel.archiveEmail(email.id)
        dismiss()
    }
    
    private func deleteEmail() {
        showingDeleteConfirmation = true
    }
    
    private func confirmDelete() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .heavy)
        impactFeedback.impactOccurred()
        
        Task {
            await viewModel.deleteEmail(email.id)
            dismiss()
        }
    }
    
    private func replyToEmail() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        showingReplyComposer = true
    }
    
    private func forwardEmail() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        showingForwardComposer = true
    }
}

// MARK: - Enhanced Supporting Views
// ... rest of file unchanged ...
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
                            .textPrimary()
                        
                        if let title = meetingInfo.title {
                            Text(title)
                                .font(DesignSystem.Typography.subheadline)
                                .textSecondary()
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
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
                            .foregroundColor(DesignSystem.Colors.textPrimary)
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
                    .textPrimary()
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
                            .textPrimary()
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
                        .textPrimary()
                        .lineLimit(1)
                    
                    Text(url)
                        .font(DesignSystem.Typography.caption)
                        .textSecondary()
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
                    .fill(DesignSystem.Colors.surfaceSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                            .stroke(isHovered ? linkColor.opacity(0.3) : DesignSystem.Colors.border, lineWidth: 1)
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
        } else if url.contains("drive.google.com") || url.contains("dropbox") {
            return "folder.fill"
        } else {
            return "link"
        }
    }
    
    private var linkColor: Color {
        if url.contains("zoom") || url.contains("teams") || url.contains("meet") {
            return .blue
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
                    .textPrimary()
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                
                Text(formatFileSize(attachment.size))
                    .font(DesignSystem.Typography.caption2)
                    .textSecondary()
            }
            .padding(DesignSystem.Spacing.md)
            .frame(minHeight: 80)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .fill(DesignSystem.Colors.surfaceSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
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
        return EmailFormatters.formatFileSize(size)
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
                    .textPrimary()
                
                Text(url)
                    .font(DesignSystem.Typography.caption)
                    .textSecondary()
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button("Open") {
                // Open link
            }
            .font(DesignSystem.Typography.caption)
            .textAccent()
        }
        .padding(DesignSystem.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                .fill(DesignSystem.Colors.surfaceSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                        .stroke(DesignSystem.Colors.border, lineWidth: 1)
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
                    .textPrimary()
                    .lineLimit(1)
                
                Text("From: \(sender)")
                    .font(DesignSystem.Typography.caption)
                    .textSecondary()
            }
            
            Spacer()
            
            Text(RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date()))
                .font(DesignSystem.Typography.caption)
                .textSecondary()
        }
        .padding(DesignSystem.Spacing.sm)
        .background(DesignSystem.Colors.surfaceSecondary)
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
            .textPrimary()
    }
}

struct AttachmentPreviewView: View {
    let attachment: EmailAttachment
    
    var body: some View {
        Text("Attachment Preview: \(attachment.filename)")
            .font(DesignSystem.Typography.title2)
            .textPrimary()
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
        EmailDetailView(
            email: Email(
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
            ),
            viewModel: ContentViewModel()
        )
    }
}
