import SwiftUI

/// Displays emails in a 7-day rolling view with collapsible day sections
struct EmailListByDay: View {
    let daySections: [EmailDaySection]
    let loadingState: EmailLoadingState
    let onRefresh: () async -> Void
    let onDeleteEmail: (Email) -> Void
    let onMarkAsUnread: (Email) -> Void
    
    @State private var expandedSections: Set<Date> = []
    @State private var selectedEmail: Email?
    @Environment(\.colorScheme) var colorScheme
    
    init(
        daySections: [EmailDaySection],
        loadingState: EmailLoadingState,
        onRefresh: @escaping () async -> Void,
        onDeleteEmail: @escaping (Email) -> Void,
        onMarkAsUnread: @escaping (Email) -> Void
    ) {
        self.daySections = daySections
        self.loadingState = loadingState
        self.onRefresh = onRefresh
        self.onDeleteEmail = onDeleteEmail
        self.onMarkAsUnread = onMarkAsUnread
        
        // Initialize with today expanded by default
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        _expandedSections = State(initialValue: [today])
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                switch loadingState {
                case .idle:
                    EmptyView()
                    
                case .loading:
                    loadingPlaceholder
                    
                case .loaded(_):
                    if daySections.isEmpty || daySections.allSatisfy({ $0.isEmpty }) {
                        emptyStateView
                    } else {
                        daySectionsList
                    }
                    
                case .error(let message):
                    ErrorView(message: message, onRetry: {
                        Task {
                            await onRefresh()
                        }
                    })
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 80) // Extra padding for compose button
        }
        .refreshable {
            await onRefresh()
        }
        .sheet(item: $selectedEmail) { email in
            EmailDetailView(email: email)
                .presentationBg()
        }
    }
    
    // MARK: - Day Sections List
    
    private var daySectionsList: some View {
        ForEach(daySections) { section in
            let isExpanded = Binding(
                get: {
                    let calendar = Calendar.current
                    let startOfDay = calendar.startOfDay(for: section.date)
                    return expandedSections.contains(startOfDay)
                },
                set: { newValue in
                    let calendar = Calendar.current
                    let startOfDay = calendar.startOfDay(for: section.date)
                    if newValue {
                        expandedSections.insert(startOfDay)
                    } else {
                        expandedSections.remove(startOfDay)
                    }
                }
            )
            
            EmailDaySectionView(
                section: section,
                isExpanded: isExpanded,
                onEmailTap: { email in
                    selectedEmail = email
                },
                onDeleteEmail: onDeleteEmail,
                onMarkAsUnread: onMarkAsUnread
            )
        }
    }
    
    // MARK: - Loading Placeholder
    
    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                DayLoadingPlaceholder()
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.3))
            
            Text("No Emails in the Last 7 Days")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? Color.white : Color.black)
            
            Text("Pull down to refresh")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
        }
        .padding(.top, 60)
    }
}

// MARK: - Day Loading Placeholder

struct DayLoadingPlaceholder: View {
    @Environment(\.colorScheme) var colorScheme
    
    private var cardBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.05) : Color.white
    }
    
    private var strokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header placeholder
            HStack(spacing: 12) {
                Circle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1))
                    .frame(width: 40, height: 40)
                
                VStack(alignment: .leading, spacing: 6) {
                    Rectangle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.15))
                        .frame(width: 100, height: 14)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    
                    Rectangle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1))
                        .frame(width: 80, height: 10)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
                
                Spacer()
                
                Circle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    .frame(width: 24, height: 24)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            // Email row placeholders
            VStack(spacing: 0) {
                ForEach(0..<2, id: \.self) { _ in
                    EmailRowPlaceholder()
                }
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(strokeColor, lineWidth: 1)
        )
    }
}

// MARK: - Preview

#Preview {
    let sampleSections = [
        EmailDaySection(date: Date(), emails: Array(Email.sampleEmails.prefix(2)), isExpanded: true),
        EmailDaySection(date: Calendar.current.date(byAdding: .day, value: -1, to: Date())!, emails: [Email.sampleEmails[2]], isExpanded: false)
    ]
    
    return EmailListByDay(
        daySections: sampleSections,
        loadingState: .loaded(Email.sampleEmails),
        onRefresh: {},
        onDeleteEmail: { _ in },
        onMarkAsUnread: { _ in }
    )
    .background(Color.shadcnBackground(.light))
}
