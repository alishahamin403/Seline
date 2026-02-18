import SwiftUI
import UIKit

/// A section view for displaying emails grouped by day
struct EmailDaySectionView: View {
    let section: EmailDaySection
    @Binding var isExpanded: Bool
    let onEmailTap: (Email) -> Void
    let onDeleteEmail: (Email) -> Void
    let onMarkAsUnread: (Email) -> Void
    @Environment(\.colorScheme) var colorScheme
    
    // MARK: - Theme Colors
    
    private var primaryTextColor: Color {
        colorScheme == .dark ? Color.white : Color.black
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6)
    }
    
    private var tertiaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.4)
    }
    
    private var isToday: Bool {
        Calendar.current.isDateInToday(section.date)
    }
    
    private var isYesterday: Bool {
        Calendar.current.isDateInYesterday(section.date)
    }
    
    private var dayDisplayName: String {
        if isToday {
            return "Today"
        } else if isYesterday {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE" // Full day name like "Wednesday"
            return formatter.string(from: section.date)
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row with date badge and day name
            headerRow
            
            // Expanded content - emails list
            if isExpanded {
                if section.emailCount > 0 {
                    emailList
                } else {
                    emptyStateView
                }
            }
        }
        .padding(.horizontal, 8)
    }
    
    // MARK: - Header Row
    
    private var headerRow: some View {
        HStack(spacing: 12) {
            // Date badge
            VStack(spacing: 2) {
                Text(section.dayLabel.uppercased())
                    .font(FontManager.geist(size: 10, systemWeight: isToday ? .bold : .medium))
                    .foregroundColor(isToday ? primaryTextColor : tertiaryTextColor)
                
                Text(section.dateNumber)
                    .font(FontManager.geist(size: 18, systemWeight: isToday ? .bold : .medium))
                    .foregroundColor(primaryTextColor)
            }
            .frame(width: 44)
            
            // Day name and email count
            HStack(spacing: 8) {
                Text(dayDisplayName)
                    .font(FontManager.geist(size: 15, systemWeight: isToday ? .semibold : .medium))
                    .foregroundColor(primaryTextColor)
                
                if section.emailCount > 0 {
                    Circle()
                        .fill(tertiaryTextColor)
                        .frame(width: 3, height: 3)
                    
                    Text("\(section.emailCount) email\(section.emailCount == 1 ? "" : "s")")
                        .font(FontManager.geist(size: 13, weight: .regular))
                        .foregroundColor(secondaryTextColor)
                    
                    if section.unreadCount > 0 {
                        Text("•")
                            .font(FontManager.geist(size: 13, weight: .regular))
                            .foregroundColor(tertiaryTextColor)
                        
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 6, height: 6)
                            Text("\(section.unreadCount) new")
                                .font(FontManager.geist(size: 13, weight: .medium))
                                .foregroundColor(Color.blue)
                        }
                    }
                } else {
                    Text("No emails")
                        .font(FontManager.geist(size: 13, weight: .regular))
                        .foregroundColor(tertiaryTextColor)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .scrollSafeTapAction(minimumDragDistance: 3) {
            withAnimation(.easeInOut(duration: 0.25)) {
                isExpanded.toggle()
            }
        }
        .allowsParentScrolling()
    }
    
    // MARK: - Email List
    
    private var emailList: some View {
        VStack(spacing: 8) {
            ForEach(section.emails) { email in
                EmailRowWithSummary(
                    email: email,
                    onTap: {
                        HapticManager.shared.email()
                        onEmailTap(email)
                    },
                    onDelete: onDeleteEmail,
                    onMarkAsUnread: onMarkAsUnread
                )
            }
        }
        .padding(.bottom, 12)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(FontManager.geist(size: 14, weight: .medium))
                .foregroundColor(Color.green.opacity(0.7))
            
            Text("All caught up!")
                .font(FontManager.geist(size: 13, weight: .medium))
                .foregroundColor(secondaryTextColor)
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Email Row With Expandable AI Summary

struct EmailRowWithSummary: View {
    let email: Email
    let onTap: () -> Void
    let onDelete: (Email) -> Void
    let onMarkAsUnread: (Email) -> Void
    
    @Environment(\.colorScheme) var colorScheme
    @State private var isSummaryExpanded = false
    @State private var aiSummary: String?
    @State private var isLoadingSummary = false
    @StateObject private var openAIService = GeminiService.shared
    @StateObject private var emailService = EmailService.shared
    

    
    private var unreadBackgroundColor: Color {
        colorScheme == .dark ? Color(red: 0.15, green: 0.2, blue: 0.35) : Color(red: 0.93, green: 0.95, blue: 1.0)
    }
    
    private var readBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.white
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main email row
            HStack(spacing: 10) {
                // Avatar
                avatarView
                
                // Content
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(email.sender.shortDisplayName)
                            .font(FontManager.geist(size: 13, systemWeight: email.isRead ? .medium : .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text(email.formattedTime)
                            .font(FontManager.geist(size: 10, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                    }
                    
                    Text(email.subject)
                        .font(FontManager.geist(size: 12, systemWeight: email.isRead ? .regular : .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.8))
                        .lineLimit(1)
                }
                
                // Indicators and expand button
                HStack(spacing: 8) {
                    if email.isImportant {
                        Image(systemName: "exclamationmark")
                            .font(FontManager.geist(size: 10, weight: .bold))
                            .foregroundColor(.orange)
                    }
                    
                    if email.hasAttachments {
                        Image(systemName: "paperclip")
                            .font(FontManager.geist(size: 10, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                    }
                    
                    // AI Summary expand button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSummaryExpanded.toggle()
                        }
                        if isSummaryExpanded {
                            // Mark as read when expanded
                            if !email.isRead {
                                Task {
                                    // Wait slightly for expansion animation to settle
                                    try? await Task.sleep(nanoseconds: 400_000_000)
                                    await MainActor.run {
                                        emailService.markAsRead(email)
                                    }
                                }
                            }
                            // Load AI summary if needed
                            if aiSummary == nil && email.aiSummary == nil {
                                Task {
                                    await loadAISummary()
                                }
                            }
                        }
                    }) {
                        Image(systemName: isSummaryExpanded ? "chevron.up" : "chevron.down")
                            .font(FontManager.geist(size: 12, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .allowsParentScrolling()
                }
            }
            .padding(8)
            .contentShape(Rectangle())
            .scrollSafeTapAction(minimumDragDistance: 3) {
                onTap()
            }
            .allowsParentScrolling()
            
            // Expanded AI Summary section - matches AISummaryCard styling
            if isSummaryExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Divider()
                        .opacity(0.3)
                    
                    // Header
                    Text("AI Summary")
                        .font(FontManager.geist(size: .small, weight: .semibold))
                        .foregroundColor(Color.shadcnForeground(colorScheme))
                    
                    if isLoadingSummary {
                        HStack(spacing: 12) {
                            ShadcnSpinner(size: .small)
                            Text("Generating AI summary...")
                                .font(FontManager.geist(size: .small, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                    } else if let summary = aiSummary ?? email.aiSummary {
                        // Parse into bullet points like AISummaryCard
                        let bullets = parseSummaryIntoBullets(summary)
                        
                        if bullets.isEmpty {
                            Text("No content available")
                                .font(FontManager.geist(size: .small, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(Array(bullets.enumerated()), id: \.offset) { index, bullet in
                                    HStack(alignment: .top, spacing: 10) {
                                        // Bullet point
                                        Circle()
                                            .fill(Color.shadcnForeground(colorScheme))
                                            .frame(width: 5, height: 5)
                                            .padding(.top, 5)
                                        
                                        // Bullet text with clickable links
                                        parseMarkdownText(bullet)
                                            .font(FontManager.geist(size: 12, weight: .regular))
                                            .foregroundColor(Color.shadcnForeground(colorScheme))
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                        
                        // Smart Reply Section
                        SmartReplySection(email: email)
                            .padding(.top, 8)
                    } else {
                        Text("Tap to generate summary")
                            .font(FontManager.geist(size: .small, weight: .regular))
                            .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                            .scrollSafeTapAction(minimumDragDistance: 3) {
                                Task {
                                    await loadAISummary()
                                }
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: ShadcnRadius.xl)
                .fill(email.isRead ? readBackgroundColor : unreadBackgroundColor)
        )
        .shadow(
            color: colorScheme == .dark ? .black.opacity(0.2) : .gray.opacity(0.15),
            radius: colorScheme == .dark ? 4 : 12,
            x: 0,
            y: colorScheme == .dark ? 2 : 4
        )
        .shadow(
            color: colorScheme == .dark ? .black.opacity(0.1) : .gray.opacity(0.08),
            radius: colorScheme == .dark ? 2 : 6,
            x: 0,
            y: colorScheme == .dark ? 1 : 2
        )
        .contextMenu {
            if email.isRead {
                Button {
                    onMarkAsUnread(email)
                } label: {
                    Label("Mark as Unread", systemImage: "envelope.badge")
                }
            }
            
            Button(role: .destructive) {
                onDelete(email)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    // MARK: - Avatar View
    
    @ViewBuilder
    private var avatarView: some View {
        // Sender avatar - colored circle with initials
        fallbackAvatar
    }
    
    private var loadingAvatar: some View {
        Circle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
            .frame(width: 40, height: 40)
            .overlay(
                ProgressView()
                    .scaleEffect(0.6)
            )
    }
    
    private var fallbackAvatar: some View {
        // Use neutral, muted colors for a professional look
        let neutralColors: [Color] = [
            Color(red: 0.45, green: 0.52, blue: 0.60),  // Slate blue-gray
            Color(red: 0.55, green: 0.55, blue: 0.55),  // Neutral gray
            Color(red: 0.40, green: 0.55, blue: 0.55),  // Muted teal
            Color(red: 0.55, green: 0.50, blue: 0.45),  // Warm taupe
            Color(red: 0.50, green: 0.45, blue: 0.55),  // Muted purple
            Color(red: 0.45, green: 0.55, blue: 0.50),  // Sage green
        ]
        
        let hash = abs(email.sender.email.hashValue)
        let color = neutralColors[hash % neutralColors.count]
        
        // Generate initials from sender name (e.g., "Wealthsimple" -> "WS", "John Doe" -> "JD")
        let initials = generateInitials(from: email.sender.shortDisplayName)
        
        return Circle()
            .fill(color)
            .frame(width: 40, height: 40)
            .overlay(
                Text(initials)
                    .font(FontManager.geist(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            )
    }
    
    /// Generate initials from a name (e.g., "Wealthsimple" -> "WS", "John Doe" -> "JD")
    private func generateInitials(from name: String) -> String {
        let words = name.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        
        if words.count >= 2 {
            // Multiple words: take first letter of first two words
            let first = String(words[0].prefix(1).uppercased())
            let second = String(words[1].prefix(1).uppercased())
            return first + second
        } else if words.count == 1 {
            // Single word: take first two letters if long enough, otherwise just first
            let word = words[0]
            if word.count >= 2 {
                return String(word.prefix(2).uppercased())
            } else {
                return String(word.prefix(1).uppercased())
            }
        } else {
            // Fallback: use first character of email
            return String(email.sender.email.prefix(1).uppercased())
        }
    }
    
    // MARK: - Parse Summary Into Bullets
    
    private func parseSummaryIntoBullets(_ summary: String) -> [String] {
        // Split the summary into bullet points by newlines (same logic as AISummaryCard)
        return summary
            .components(separatedBy: .newlines)
            .map { line in
                // Remove bullet point characters (•, *, -, etc.) since UI adds its own
                var cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if cleaned.hasPrefix("•") || cleaned.hasPrefix("*") || cleaned.hasPrefix("-") {
                    cleaned = String(cleaned.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
                }
                return cleaned
            }
            .filter { !$0.isEmpty }
    }
    
    // MARK: - Parse Markdown Links and Bold
    
    /// Parse markdown links [text](url) and bold **text**, make them clickable/rendered properly
    private func parseMarkdownText(_ text: String) -> some View {
        // First, remove bold markers **text** -> text (we'll render as bold)
        var processedText = text
        let boldPattern = #"\*\*([^\*]+)\*\*"#
        
        // Remove bold markers for now (we can enhance later to actually render bold)
        if let boldRegex = try? NSRegularExpression(pattern: boldPattern, options: []) {
            let nsString = processedText as NSString
            let boldMatches = boldRegex.matches(in: processedText, options: [], range: NSRange(location: 0, length: nsString.length))
            
            // Process in reverse to preserve indices
            for match in boldMatches.reversed() {
                if match.numberOfRanges >= 2 {
                    let fullRange = match.range
                    let textRange = match.range(at: 1)
                    let boldText = nsString.substring(with: textRange)
                    // Replace **text** with just text
                    processedText = (processedText as NSString).replacingCharacters(in: fullRange, with: boldText)
                }
            }
        }
        
        // Pattern: [text](url)
        let linkPattern = #"\[([^\]]+)\]\(([^\)]+)\)"#
        
        guard let regex = try? NSRegularExpression(pattern: linkPattern, options: []) else {
            return AnyView(Text(processedText))
        }
        
        let nsString = processedText as NSString
        let matches = regex.matches(in: processedText, options: [], range: NSRange(location: 0, length: nsString.length))
        
        if matches.isEmpty {
            return AnyView(Text(processedText))
        }
        
        // Build attributed string with clickable links
        let attributedString = NSMutableAttributedString(string: processedText)
        let textColor = colorScheme == .dark ? UIColor.white : UIColor.black
        attributedString.addAttribute(.foregroundColor, value: textColor, range: NSRange(location: 0, length: processedText.count))
        
        // Process matches in reverse to preserve indices
        for match in matches.reversed() {
            if match.numberOfRanges >= 3 {
                let fullRange = match.range
                let linkTextRange = match.range(at: 1)
                let urlRange = match.range(at: 2)
                
                let linkText = nsString.substring(with: linkTextRange)
                let urlString = nsString.substring(with: urlRange)
                
                // Replace [text](url) with just the link text
                attributedString.replaceCharacters(in: fullRange, with: linkText)
                
                // Make the link text blue and clickable
                let newRange = NSRange(location: fullRange.location, length: linkText.count)
                if let url = URL(string: urlString) {
                    attributedString.addAttribute(.link, value: url, range: newRange)
                    attributedString.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: newRange)
                    attributedString.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: newRange)
                }
            }
        }
        
        return AnyView(
            Text(AttributedString(attributedString))
                .onOpenURL { url in
                    UIApplication.shared.open(url)
                }
        )
    }
    
    // MARK: - Load AI Summary
    
    private func loadAISummary() async {
        // Check if already have a summary
        if let existing = email.aiSummary {
            aiSummary = existing
            return
        }
        
        isLoadingSummary = true
        
        do {
            // Use snippet for quick summary
            let body = email.body ?? email.snippet
            let summary = try await openAIService.summarizeEmail(
                subject: email.subject,
                body: body
            )
            
            let finalSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No content available" : summary
            
            await MainActor.run {
                self.aiSummary = finalSummary
            }
            
            // Cache it
            await emailService.updateEmailWithAISummary(email, summary: finalSummary)
        } catch {
            await MainActor.run {
                self.aiSummary = "Failed to generate summary"
            }
        }
        
        await MainActor.run {
            isLoadingSummary = false
        }
    }
}

// MARK: - Smart Reply Section

struct SmartReplySection: View {
    let email: Email
    @Environment(\.colorScheme) var colorScheme
    @State private var replyPrompt: String = ""
    @State private var generatedReply: String = ""
    @State private var isGenerating: Bool = false
    @State private var isSending: Bool = false
    @State private var showConfirmation: Bool = false
    @State private var showSentSuccess: Bool = false
    @State private var errorMessage: String?
    @StateObject private var openAIService = GeminiService.shared
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Divider
            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                .frame(height: 1)
            
            // Smart Reply Header
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(FontManager.geist(size: 12, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Text("Smart Reply")
                    .font(FontManager.geist(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            }
            
            if !showConfirmation {
                // Input State
                VStack(alignment: .leading, spacing: 10) {
                    // Text input
                    HStack(spacing: 10) {
                        TextField("Describe how you'd like to reply...", text: $replyPrompt)
                            .font(FontManager.geist(size: 14, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.04))
                            )
                            .focused($isInputFocused)
                        
                        // Generate button
                        Button(action: {
                            Task {
                                await generateSmartReply()
                            }
                        }) {
                            if isGenerating {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .frame(width: 40, height: 40)
                            } else {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(FontManager.geist(size: 28, weight: .medium))
                                    .foregroundColor(replyPrompt.isEmpty ? 
                                        (colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3)) :
                                        (colorScheme == .dark ? .white : .black))
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(replyPrompt.isEmpty || isGenerating)
                    }
                    
                    // Quick suggestions
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            QuickReplyChip(text: "Sounds good", colorScheme: colorScheme) {
                                replyPrompt = "Agree politely and confirm"
                            }
                            QuickReplyChip(text: "Need more info", colorScheme: colorScheme) {
                                replyPrompt = "Ask for more details or clarification"
                            }
                            QuickReplyChip(text: "Decline politely", colorScheme: colorScheme) {
                                replyPrompt = "Politely decline the request"
                            }
                            QuickReplyChip(text: "Schedule meeting", colorScheme: colorScheme) {
                                replyPrompt = "Suggest scheduling a meeting to discuss"
                            }
                        }
                    }
                    
                    if let error = errorMessage {
                        Text(error)
                            .font(FontManager.geist(size: 12, weight: .regular))
                            .foregroundColor(.red)
                    }
                }
            } else if showSentSuccess {
                // Success State
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(FontManager.geist(size: 20, weight: .medium))
                        .foregroundColor(.green)
                    
                    Text("Reply sent successfully!")
                        .font(FontManager.geist(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                }
                .padding(.vertical, 8)
                .onAppear {
                    // Auto-dismiss after 2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSentSuccess = false
                            showConfirmation = false
                            generatedReply = ""
                            replyPrompt = ""
                        }
                    }
                }
            } else {
                // Confirmation State
                VStack(alignment: .leading, spacing: 12) {
                    // Generated reply preview
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Preview")
                            .font(FontManager.geist(size: 11, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                            .textCase(.uppercase)
                        
                        Text(generatedReply)
                            .font(FontManager.geist(size: 14, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                            )
                    }
                    
                    // Error message if any
                    if let error = errorMessage {
                        Text(error)
                            .font(FontManager.geist(size: 12, weight: .regular))
                            .foregroundColor(.red)
                    }
                    
                    // Action buttons
                    HStack(spacing: 12) {
                        // Cancel button
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showConfirmation = false
                                generatedReply = ""
                                errorMessage = nil
                            }
                        }) {
                            Text("Edit")
                                .font(FontManager.geist(size: 14, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2), lineWidth: 1)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(isSending)
                        .opacity(isSending ? 0.5 : 1)
                        
                        // Send button
                        Button(action: {
                            Task {
                                await sendReply()
                            }
                        }) {
                            HStack(spacing: 6) {
                                if isSending {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 12, height: 12)
                                } else {
                                    Image(systemName: "paperplane.fill")
                                        .font(FontManager.geist(size: 12, weight: .medium))
                                }
                                Text(isSending ? "Sending..." : "Send Reply")
                                    .font(FontManager.geist(size: 14, weight: .semibold))
                            }
                            .foregroundColor(colorScheme == .dark ? .black : .white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(colorScheme == .dark ? .white : .black)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(isSending)
                        
                        Spacer()
                    }
                }
            }
        }
    }
    
    // MARK: - Generate Smart Reply
    
    private func generateSmartReply() async {
        guard !replyPrompt.isEmpty else { return }
        
        isGenerating = true
        errorMessage = nil
        isInputFocused = false
        
        do {
            let prompt = """
            Generate a professional email reply based on the user's intent.
            
            ORIGINAL EMAIL:
            From: \(email.sender.displayName) <\(email.sender.email)>
            Subject: \(email.subject)
            Content: \(email.body ?? email.snippet)
            
            USER'S INTENT FOR REPLY: \(replyPrompt)
            
            INSTRUCTIONS:
            - Write a natural, professional email reply
            - Keep it concise but friendly
            - Don't include subject line or email headers
            - Don't include placeholder text like [Your Name]
            - Just write the email body text
            - Match the tone of the original email (formal/casual)
            """
            
            let response = try await openAIService.answerQuestion(
                query: prompt,
                conversationHistory: [],
                operationType: "smart_reply"
            )
            
            await MainActor.run {
                generatedReply = response.trimmingCharacters(in: .whitespacesAndNewlines)
                withAnimation(.easeInOut(duration: 0.2)) {
                    showConfirmation = true
                }
                isGenerating = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to generate reply. Please try again."
                isGenerating = false
            }
        }
    }
    
    // MARK: - Send Reply
    
    private func sendReply() async {
        guard !generatedReply.isEmpty else { return }
        
        isSending = true
        errorMessage = nil
        
        do {
            // Send via Gmail API
            _ = try await GmailAPIClient.shared.replyToEmail(
                originalEmail: email,
                body: generatedReply,
                htmlBody: nil,
                replyAll: false
            )
            
            await MainActor.run {
                isSending = false
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSentSuccess = true
                }
                HapticManager.shared.success()
            }
        } catch {
            await MainActor.run {
                isSending = false
                errorMessage = "Failed to send reply. Please try again."
                HapticManager.shared.error()
            }
            print("❌ Failed to send reply: \(error)")
        }
    }
}

// MARK: - Quick Reply Chip

struct QuickReplyChip: View {
    let text: String
    let colorScheme: ColorScheme
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(FontManager.geist(size: 12, weight: .medium))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06))
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

#Preview {
    let calendar = Calendar.current
    let today = Date()
    let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
    
    return ScrollView {
        VStack(spacing: 0) {
            EmailDaySectionView(
                section: EmailDaySection(
                    date: today,
                    emails: Array(Email.sampleEmails.prefix(3)),
                    isExpanded: true
                ),
                isExpanded: .constant(true),
                onEmailTap: { _ in },
                onDeleteEmail: { _ in },
                onMarkAsUnread: { _ in }
            )
            
            EmailDaySectionView(
                section: EmailDaySection(
                    date: yesterday,
                    emails: [Email.sampleEmails[2]],
                    isExpanded: false
                ),
                isExpanded: .constant(false),
                onEmailTap: { _ in },
                onDeleteEmail: { _ in },
                onMarkAsUnread: { _ in }
            )
        }
        .padding(.horizontal, 8)
    }
    .background(Color.shadcnBackground(.light))
}
