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
    @State private var selectedEmail: Email?
    @State private var isShowingEmailDetail = false
    
    var body: some View {
        ZStack {
            DesignSystem.Colors.surface.ignoresSafeArea()
            
            if viewModel.isLoading {
                loadingView
            } else if cachedImportantEmails.isEmpty {
                emptyStateView
            } else {
                importantEmailsList
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                        Text("Back")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .foregroundColor(DesignSystem.Colors.accent)
                }
            }
            
            ToolbarItem(placement: .principal) {
                Text("Important Emails")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
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
                print("🔄 ImportantEmailsView: selectedEmail changed to \(email?.id ?? "nil")")
                isShowingEmailDetail = true
            } else {
                print("🔄 ImportantEmailsView: selectedEmail cleared")
                isShowingEmailDetail = false
            }
        }
        .onAppear {
            // Initialize cache immediately if emails are already available
            updateCachedEmails()
            
            Task {
                // Clear any in-memory cached/mock data before reloading
                EmailCacheManager.shared.clearCache()
                // Load category emails which recomputes Important from today's emails only
                await viewModel.loadCategoryEmails()
                await MainActor.run {
                    updateCachedEmails()
                }
            }
        }
        .onChange(of: viewModel.importantEmails) { _ in
            updateCachedEmails()
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 0) {
            // Top SafeArea + navigation
            HStack {
                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
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
                
                Text("Important Emails")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Spacer()
                
                // Placeholder for right button to center title
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.title2)
                    Text("Back")
                        .font(.system(size: 16, weight: .medium))
                }
                .foregroundColor(.clear)
                .foregroundColor(DesignSystem.Colors.accent)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 20)
            .background(DesignSystem.Colors.surface)
        }
    }
    
    // MARK: - Email List
    
    @State private var cachedImportantEmails: [Email] = []
    
    private func updateCachedEmails() {
        // Filter to today's emails only and drop any mock/preloaded IDs
        let today = Calendar.current
        let emails = viewModel.importantEmails
            .filter { today.isDateInToday($0.date) }
            .filter { !($0.id.hasPrefix("gmail_") || $0.id.hasPrefix("important_") || $0.id.hasPrefix("promo_")) }
        ArrayBoundsLogger.logArrayAccess(arrayName: "importantEmails", count: emails.count)
        
        guard !emails.isEmpty else { 
            print("🔍 ImportantEmailsView: No important emails to display")
            cachedImportantEmails = []
            return
        }
        
        print("🔍 ImportantEmailsView: Processing \(emails.count) important emails")
        let sortedEmails = emails.safeSortedByDate(ascending: false)
        ArrayBoundsLogger.logArrayOperation(operation: "Sort", arrayName: "importantEmails", originalCount: emails.count, resultCount: sortedEmails.count)
        
        cachedImportantEmails = sortedEmails
    }
    
    private var importantEmailsList: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 1) {
                ForEach(cachedImportantEmails.indices, id: \.self) { index in
                    let email = cachedImportantEmails[index]
                    CleanEmailRow(email: email) {
                        print("📧 ImportantEmailsView: EmailRow tapped for email: \(email.id)")
                        
                        // Add haptic feedback
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        
                        selectedEmail = email
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            Task {
                                do {
                                    try await GmailService.shared.deleteEmail(emailId: email.id)
                                    await viewModel.refresh()
                                    await MainActor.run { updateCachedEmails() }
                                } catch GmailError.insufficientPermissions {
                                    // Surface hint to user
                                    let alert = UIAlertController(title: "Permission Required", message: "To delete emails, Seline needs Gmail modify permission. Please sign out and sign in again when prompted.", preferredStyle: .alert)
                                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                                    if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                                       let window = scene.windows.first,
                                       let root = window.rootViewController {
                                        root.present(alert, animated: true)
                                    }
                                } catch {
                                    print("❌ Failed to delete email: \(error.localizedDescription)")
                                }
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 100) // Extra bottom padding for safe scrolling
        }
        .refreshable {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            await performEnhancedRefresh()
        }
    }
    
    private func performEnhancedRefresh() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await viewModel.refresh()
            }
            
            // Add a small delay to ensure smooth animation
            group.addTask {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            }
            
            await group.waitForAll()
        }
        
        // Update cached emails after refresh
        await MainActor.run {
            updateCachedEmails()
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            ForEach(0..<5, id: \.self) { index in
                SkeletonEmailRow()
                    .animatedSlideIn(from: .bottom, delay: Double(index) * 0.1)
            }
        }
        .padding(DesignSystem.Spacing.lg)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.05))
                    .frame(width: 80, height: 80)
                    .animatedScaleIn(delay: 0.1)

                Image(systemName: "star.circle")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundColor(.black.opacity(0.7))
                    .animatedScaleIn(delay: 0.3)
            }

            VStack(spacing: 12) {
                Text("No Important Emails")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .animatedSlideIn(from: .bottom, delay: 0.4)

                Text("Important emails and updates will appear here")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .animatedSlideIn(from: .bottom, delay: 0.5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

// MARK: - Important Email Row

struct CleanEmailRow: View {
    let email: Email
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Simple avatar
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 44, height: 44)
                    
                    Text(String(email.sender.displayName.prefix(1).uppercased()))
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    // Unread indicator
                    if !email.isRead {
                        Circle()
                            .fill(DesignSystem.Colors.accent)
                            .frame(width: 8, height: 8)
                            .offset(x: 16, y: -16)
                    }
                }
                
                // Email info
                VStack(alignment: .leading, spacing: 4) {
                    // Sender and time
                    HStack {
                        Text(email.sender.displayName)
                            .font(.system(size: email.isRead ? 15 : 16, weight: email.isRead ? .regular : .semibold, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text(formatEmailTime(email.date))
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    
                    // Subject only
                    Text(email.subject)
                        .font(.system(size: email.isRead ? 14 : 15, weight: email.isRead ? .regular : .medium, design: .rounded))
                        .foregroundColor(email.isRead ? DesignSystem.Colors.textSecondary : DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                }
                
                // Simple chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.clear)
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(Color.white.opacity(0.3))
                    .padding(.horizontal, 16),
                alignment: .bottom
            )
            .scaleEffect(isPressed ? 0.98 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0.0, maximumDistance: .infinity) {
            // Long press action
        } onPressingChanged: { pressing in
            isPressed = pressing
        }
    }
    private func formatEmailTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.dateInterval(of: .weekOfYear, for: now)?.contains(date) == true {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE" // Day name
            return formatter.string(from: date)
        } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d" // Month day
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, yyyy" // Month day, year
            return formatter.string(from: date)
        }
    }
}

// MARK: - Skeleton Email Row

struct SkeletonEmailRow: View {
    @State private var animateGradient = false

    var body: some View {
        HStack(spacing: 16) {
            // Skeleton avatar (minimalist black style)
            Circle()
                .fill(shimmerGradient)
                .frame(width: 48, height: 48)

            // Skeleton content
            VStack(alignment: .leading, spacing: 6) {
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
                        .frame(width: 40, height: 10)
                        .cornerRadius(4)

                    Spacer()

                    Rectangle()
                        .fill(shimmerGradient)
                        .frame(width: 12, height: 12)
                        .cornerRadius(6)
                }
            }

            // Minimalist arrow
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(Color.black.opacity(0.2))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
    }

    private var shimmerGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.black.opacity(0.1),
                Color.black.opacity(0.05),
                Color.black.opacity(0.1)
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