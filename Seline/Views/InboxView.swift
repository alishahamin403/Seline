//
//  InboxView.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-24.
//

import SwiftUI
import UIKit

struct InboxView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ContentViewModel()
    @State private var selectedFilter: InboxFilter = .all
    @State private var selectedEmail: Email?
    @State private var isShowingEmailDetail = false
    @State private var useFullScreenCover = false
    @State private var cachedFilteredEmails: [Email] = []
    @State private var searchText = ""
    @State private var isSearching = false
    
    var body: some View {
        // Snapshot once per body evaluation for stability
        let emailsSnapshot = filteredEmailsForSearch
        
        ZStack {
            // Consistent background from design system
            DesignSystem.Colors.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with back button and search
                headerSection
                
                // Email list
                if viewModel.isLoading {
                    loadingView
                } else if let errorMessage = viewModel.errorMessage {
                    errorStateView(errorMessage)
                } else if emailsSnapshot.isEmpty {
                    emptyStateView
                } else {
                    emailListSection(emailsSnapshot: emailsSnapshot)
                }
            }
            
            // Compose button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    composeButton
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                }
            }
        }
        .fullScreenCover(item: $selectedEmail) { email in
            NavigationView {
                GmailStyleEmailDetailView(email: email, viewModel: viewModel)
                    .navigationBarHidden(true)
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .trailing)))
        }
        .onChange(of: selectedEmail) { email in
            if email != nil {
                print("🔄 InboxView: selectedEmail changed to \(email?.id ?? "nil")")
                isShowingEmailDetail = true
            } else {
                print("🔄 InboxView: selectedEmail cleared")
                isShowingEmailDetail = false
            }
        }
        .onChange(of: selectedFilter) { _ in
            updateCachedFilteredEmails()
        }
        .onChange(of: viewModel.emails) { _ in
            updateCachedFilteredEmails()
        }
        .onChange(of: viewModel.importantEmails) { _ in
            updateCachedFilteredEmails()
        }
        .onChange(of: viewModel.calendarEmails) { _ in
            updateCachedFilteredEmails()
        }
        .onAppear {
            Task {
                await viewModel.loadEmails()
                await MainActor.run {
                    updateCachedFilteredEmails()
                }
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            // Top header with back button and profile
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
                
                // Profile avatar
                Button(action: {}) {
                    Circle()
                        .fill(Color.purple)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text("A")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                        )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                
                TextField("Search in mail", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .onTapGesture {
                        isSearching = true
                    }
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.gray.opacity(0.2))
            .cornerRadius(25)
            .padding(.horizontal, 20)
            
            // Section header
            HStack {
                Text("All inboxes")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(DesignSystem.Colors.background)
    }
    
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(DesignSystem.Colors.textPrimary)
            
            Text("Loading emails...")
                .font(.system(size: 16))
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty State View
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            VStack(spacing: 8) {
                Text("No emails found")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("Your inbox is empty or all emails have been read")
                    .font(.system(size: 16))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
    
    // MARK: - Email List Section
    
    private func emailListSection(emailsSnapshot: [Email]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Iterate over a stable snapshot with stable IDs (no enumerated indexing)
                ForEach(emailsSnapshot, id: \.id) { email in
                    ModernEmailRow(email: email) {
                        // Add haptic feedback
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        
                        // Preload email content in background for smooth opening
                        Task {
                            _ = await viewModel.preloadEmailContent(for: email.id)
                        }
                        
                        // Force update with animation to ensure state change is detected
                        withAnimation(.easeInOut(duration: 0.1)) {
                            selectedEmail = email
                        }
                    }
                    .onAppear {
                        // Preload email content when it appears on screen for smoother opening
                        Task {
                            _ = await viewModel.preloadEmailContent(for: email.id)
                        }
                    }
                }
                
                // Load More button
                if viewModel.hasMoreEmails && !viewModel.isLoadingMore && !emailsSnapshot.isEmpty {
                    loadMoreButton
                }
            }
        }
        .refreshable {
            await viewModel.refresh()
            updateCachedFilteredEmails()
        }
        .onAppear {
            updateCachedFilteredEmails()
            let visibleEmailIds = Array(emailsSnapshot.prefix(10).map { $0.id })
            viewModel.preloadEmailsInBackground(for: visibleEmailIds, priority: .utility)
        }
    }
    
    private var filteredEmails: [Email] {
        let allEmails = viewModel.emails
        ArrayBoundsLogger.logArrayAccess(arrayName: "allEmails", count: allEmails.count)
        
        let filtered: [Email]
        switch selectedFilter {
        case .all:
            filtered = allEmails
        case .unread:
            filtered = allEmails.safeFilter { !$0.isRead }
        case .important:
            let importantEmails = viewModel.importantEmails
            ArrayBoundsLogger.logArrayAccess(arrayName: "importantEmails", count: importantEmails.count)
            filtered = importantEmails
        case .calendar:
            let calendarEmails = viewModel.calendarEmails
            ArrayBoundsLogger.logArrayAccess(arrayName: "calendarEmails", count: calendarEmails.count)
            filtered = calendarEmails
        }
        
        ArrayBoundsLogger.logArrayOperation(operation: "Filter", arrayName: "emails", originalCount: allEmails.count, resultCount: filtered.count)
        print("📬 InboxView filteredEmails: \(allEmails.count) total -> \(filtered.count) filtered (filter: \(selectedFilter))")
        return filtered
    }
    
    private func updateCachedFilteredEmails() {
        let filtered = filteredEmails
        ArrayBoundsLogger.logArrayOperation(operation: "Cache Update", arrayName: "filteredEmails", originalCount: cachedFilteredEmails.count, resultCount: filtered.count)
        cachedFilteredEmails = filtered
        print("📦 InboxView: Cached \(filtered.count) filtered emails (filter: \(selectedFilter))")
    }
    
    // MARK: - Search Functionality
    
    private var filteredEmailsForSearch: [Email] {
        if searchText.isEmpty {
            return cachedFilteredEmails
        } else {
            return cachedFilteredEmails.filter { email in
                email.subject.localizedCaseInsensitiveContains(searchText) ||
                email.body.localizedCaseInsensitiveContains(searchText) ||
                email.sender.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    // MARK: - UI Components
    
    private func errorStateView(_ errorMessage: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text("Error Loading Emails")
                .font(.headline)
                .foregroundColor(DesignSystem.Colors.textPrimary)
            
            Text(errorMessage)
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            
            Button("Retry") {
                Task {
                    await viewModel.loadEmails()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var loadMoreButton: some View {
        Button(action: {
            Task {
                await viewModel.loadMoreEmails()
            }
        }) {
            HStack {
                if viewModel.isLoadingMore {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(DesignSystem.Colors.textPrimary)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.title3)
                }
                
                Text(viewModel.isLoadingMore ? "Loading..." : "Load More")
                    .font(.system(size: 16, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
        }
        .disabled(viewModel.isLoadingMore)
    }
    
    private var composeButton: some View {
        Button(action: {
            // Handle compose action
        }) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18, weight: .medium))
                Text("Compose")
                    .font(.system(size: 16, weight: .medium))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.blue)
            .cornerRadius(25)
        }
    }
}

// MARK: - Inbox Filter

enum InboxFilter: String, CaseIterable {
    case all = "All"
    case unread = "Unread"
    case important = "Important"
    case calendar = "Calendar"
    
    var icon: String {
        switch self {
        case .all:
            return "tray.fill"
        case .unread:
            return "envelope.fill"
        case .important:
            return "exclamationmark.circle.fill"
        case .calendar:
            return "calendar.circle.fill"
        }
    }
}


// MARK: - Modern Email Row

struct ModernEmailRow: View {
    let email: Email
    let onTap: () -> Void
    
    private var avatarColor: Color {
        let colors: [Color] = [.blue, .purple, .green, .orange, .red, .pink, .indigo]
        let index = abs(email.sender.displayName.hashValue) % colors.count
        return colors[index]
    }
    
    private var isImportant: Bool {
        email.isImportant || email.subject.lowercased().contains("urgent") || email.subject.lowercased().contains("important")
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Avatar with letter
                Circle()
                    .fill(avatarColor)
                    .frame(width: 48, height: 48)
                    .overlay(
                        Text(String(email.sender.displayName.prefix(1).uppercased()))
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    // First row: Important indicator + Sender + Date
                    HStack(spacing: 4) {
                        if isImportant {
                            Image(systemName: "chevron.right.2")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.yellow)
                        }
                        
                        Text(email.sender.displayName)
                            .font(.system(size: 16, weight: email.isRead ? .regular : .semibold))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text(formatDate(email.date))
                            .font(.system(size: 14))
                            .foregroundColor(.gray)
                    }
                    
                    // Subject line
                    Text(email.subject)
                        .font(.system(size: 15, weight: email.isRead ? .regular : .medium))
                        .foregroundColor(email.isRead ? .gray : .white)
                        .lineLimit(1)
                    
                    // Preview text
                    Text(email.body)
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .lineLimit(2)
                    
                    // Attachments row
                    if !email.attachments.isEmpty {
                        HStack(spacing: 8) {
                            ForEach(email.attachments.prefix(2), id: \.id) { attachment in
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.red)
                                    Text(attachmentName(attachment))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundColor(DesignSystem.Colors.textPrimary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.gray.opacity(0.3))
                                        .cornerRadius(12)
                                }
                            }
                            
                            if email.attachments.count > 2 {
                                Text("...")
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }
                            
                            Spacer()
                        }
                        .padding(.top, 4)
                    }
                }
                
                // Star indicator
                VStack {
                    Button(action: {
                        // Handle star toggle
                    }) {
                        Image(systemName: email.isImportant ? "star.fill" : "star")
                            .font(.system(size: 18))
                            .foregroundColor(email.isImportant ? .yellow : .gray)
                    }
                    
                    Spacer()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        let relative = formatter.localizedString(for: date, relativeTo: Date())
        
        if relative.contains("day") {
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "MMM d"
            return dayFormatter.string(from: date)
        }
        
        return relative
    }
    
    private func attachmentName(_ attachment: EmailAttachment) -> String {
        return attachment.filename
    }
}

// MARK: - Preview

struct InboxView_Previews: PreviewProvider {
    static var previews: some View {
        InboxView()
    }
}
