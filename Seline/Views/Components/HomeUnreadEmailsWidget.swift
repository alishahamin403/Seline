import SwiftUI

/// A minimalistic unread emails widget for the home screen
struct HomeUnreadEmailsWidget: View {
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var emailService = EmailService.shared
    
    @Binding var selectedTab: TabSelection
    var onEmailSelected: ((Email) -> Void)?
    
    private var unreadEmails: [Email] {
        emailService.inboxEmails.filter { !$0.isRead }
    }
    
    private var unreadCount: Int {
        unreadEmails.count
    }
    
    // Email avatar color based on sender email (Google brand colors)
    private func emailAvatarColor(for email: Email) -> Color {
        let colors: [Color] = [
            Color(red: 0.2588, green: 0.5216, blue: 0.9569),  // Google Blue
            Color(red: 0.9176, green: 0.2627, blue: 0.2078),  // Google Red
            Color(red: 0.9843, green: 0.7373, blue: 0.0157),  // Google Yellow
            Color(red: 0.2039, green: 0.6588, blue: 0.3255),  // Google Green
        ]
        
        let hash = HashUtils.deterministicHash(email.sender.email)
        let colorIndex = abs(hash) % colors.count
        return colors[colorIndex]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 10) {
                Text("Unread Emails")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                
                Spacer()
                
                // Count badge
                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.08))
                        )
                }
            }
            
            // Email list
            if unreadEmails.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(red: 0.2, green: 0.7, blue: 0.4))
                    
                    Text("All caught up!")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(unreadEmails.prefix(4)) { email in
                        emailRow(email)
                    }
                    
                    // Show "more" indicator if there are more emails
                    if unreadCount > 4 {
                        Button(action: {
                            HapticManager.shared.selection()
                            selectedTab = .email
                        }) {
                            HStack(spacing: 6) {
                                Text("+\(unreadCount - 4) more")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.4))
                            }
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .allowsParentScrolling()
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadcnTileStyle(colorScheme: colorScheme)
    }
    
    private func emailRow(_ email: Email) -> some View {
        Button(action: {
            HapticManager.shared.email()
            onEmailSelected?(email)
        }) {
            HStack(spacing: 10) {
                // Avatar
                Circle()
                    .fill(emailAvatarColor(for: email))
                    .frame(width: 28, height: 28)
                    .overlay(
                        Text(email.sender.shortDisplayName.prefix(1).uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    // Sender name
                    Text(email.sender.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                    
                    // Subject
                    Text(email.subject)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Time indicator
                Text(formatEmailTime(email.timestamp))
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.4) : Color.black.opacity(0.4))
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .allowsParentScrolling()
    }
    
    private func formatEmailTime(_ date: Date) -> String {
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }
}

#Preview {
    VStack {
        HomeUnreadEmailsWidget(selectedTab: .constant(.home))
            .padding(.horizontal, 12)
        Spacer()
    }
    .background(Color.shadcnBackground(.dark))
}

