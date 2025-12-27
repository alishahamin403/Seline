import SwiftUI

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
        .padding(.horizontal, 12)
    }
    
    // MARK: - Header Row
    
    private var headerRow: some View {
        HStack(spacing: 12) {
            // Date badge
            VStack(spacing: 2) {
                Text(section.dayLabel.uppercased())
                    .font(.system(size: 10, weight: isToday ? .bold : .medium))
                    .foregroundColor(isToday ? primaryTextColor : tertiaryTextColor)
                
                Text(section.dateNumber)
                    .font(.system(size: 18, weight: isToday ? .bold : .medium))
                    .foregroundColor(primaryTextColor)
            }
            .frame(width: 44)
            
            // Day name and email count
            HStack(spacing: 8) {
                Text(dayDisplayName)
                    .font(.system(size: 15, weight: isToday ? .semibold : .medium))
                    .foregroundColor(primaryTextColor)
                
                if section.emailCount > 0 {
                    Circle()
                        .fill(tertiaryTextColor)
                        .frame(width: 3, height: 3)
                    
                    Text("\(section.emailCount) email\(section.emailCount == 1 ? "" : "s")")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(secondaryTextColor)
                    
                    if section.unreadCount > 0 {
                        Text("•")
                            .font(.system(size: 13))
                            .foregroundColor(tertiaryTextColor)
                        
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 6, height: 6)
                            Text("\(section.unreadCount) new")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color.blue)
                        }
                    }
                } else {
                    Text("No emails")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(tertiaryTextColor)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.25)) {
                isExpanded.toggle()
            }
        }
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
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color.green.opacity(0.7))
            
            Text("All caught up!")
                .font(.system(size: 13, weight: .medium))
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
    @State private var profilePictureUrl: String?
    @State private var isLoadingProfilePicture = false
    @State private var isSummaryExpanded = false
    @State private var aiSummary: String?
    @State private var isLoadingSummary = false
    @StateObject private var openAIService = DeepSeekService.shared
    @StateObject private var emailService = EmailService.shared
    
    private var avatarColor: Color {
        let colors: [Color] = [
            Color(red: 0.2588, green: 0.5216, blue: 0.9569),
            Color(red: 0.9176, green: 0.2627, blue: 0.2078),
            Color(red: 0.9843, green: 0.7373, blue: 0.0157),
            Color(red: 0.2039, green: 0.6588, blue: 0.3255),
        ]
        let hash = HashUtils.deterministicHash(email.sender.email)
        return colors[abs(hash) % colors.count]
    }
    
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
                            .font(.system(size: 14, weight: email.isRead ? .medium : .semibold))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text(email.formattedTime)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                    }
                    
                    Text(email.subject)
                        .font(.system(size: 13, weight: email.isRead ? .regular : .medium))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.8))
                        .lineLimit(1)
                }
                
                // Indicators and expand button
                HStack(spacing: 8) {
                    if email.isImportant {
                        Image(systemName: "exclamationmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.orange)
                    }
                    
                    if email.hasAttachments {
                        Image(systemName: "paperclip")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                    }
                    
                    // AI Summary expand button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isSummaryExpanded.toggle()
                        }
                        if isSummaryExpanded && aiSummary == nil && email.aiSummary == nil {
                            Task {
                                await loadAISummary()
                            }
                        }
                    }) {
                        Image(systemName: isSummaryExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(12)
            .contentShape(Rectangle())
            .onTapGesture {
                onTap()
            }
            
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
                                        
                                        // Bullet text
                                        Text(bullet)
                                            .font(FontManager.geist(size: 12, weight: .regular))
                                            .foregroundColor(Color.shadcnForeground(colorScheme))
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                    } else {
                        Text("Tap to generate summary")
                            .font(FontManager.geist(size: .small, weight: .regular))
                            .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                            .onTapGesture {
                                Task {
                                    await loadAISummary()
                                }
                            }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(email.isRead ? readBackgroundColor : unreadBackgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: colorScheme == .dark ? .clear : Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
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
        .task {
            await fetchProfilePicture()
        }
    }
    
    // MARK: - Avatar View
    
    @ViewBuilder
    private var avatarView: some View {
        if let profilePictureUrl = profilePictureUrl, !profilePictureUrl.isEmpty {
            AsyncImage(url: URL(string: profilePictureUrl)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                case .failure(_), .empty:
                    fallbackAvatar
                @unknown default:
                    fallbackAvatar
                }
            }
        } else if isLoadingProfilePicture {
            loadingAvatar
        } else {
            fallbackAvatar
        }
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
        Circle()
            .fill(avatarColor)
            .frame(width: 40, height: 40)
            .overlay(
                Text(email.sender.shortDisplayName.prefix(1).uppercased())
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            )
    }
    
    // MARK: - Fetch Profile Picture
    
    private func fetchProfilePicture() async {
        guard !isLoadingProfilePicture else { return }
        isLoadingProfilePicture = true
        
        do {
            if let picUrl = try await GmailAPIClient.shared.fetchProfilePicture(for: email.sender.email) {
                await MainActor.run {
                    self.profilePictureUrl = picUrl
                }
            }
        } catch {
            // Silently fail
        }
        
        await MainActor.run {
            isLoadingProfilePicture = false
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
