//
//  PromotionalEmailsView.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-24.
//

import SwiftUI

struct PromotionalEmailsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = ContentViewModel()
    @State private var showingEmailDetail = false
    @State private var selectedEmail: Email?
    @State private var viewMode: ViewMode = .list
    
    enum ViewMode: String, CaseIterable {
        case list = "List"
        case grid = "Grid"
        
        var icon: String {
            switch self {
            case .list: return "list.bullet"
            case .grid: return "square.grid.2x2"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with stats and view toggle
                promotionalEmailsHeader
                
                // Content based on view mode
                if viewModel.isLoading {
                    loadingView
                } else if viewModel.promotionalEmails.isEmpty {
                    emptyStateView
                } else {
                    Group {
                        if viewMode == .list {
                            promotionalEmailsList
                        } else {
                            promotionalEmailsGrid
                        }
                    }
                }
            }
            .designSystemBackground()
            .navigationTitle("Promotional")
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
    
    private var promotionalEmailsHeader: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(viewModel.promotionalEmails.count)")
                        .font(DesignSystem.Typography.title1)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                    
                    Text("Promotional Emails")
                        .font(DesignSystem.Typography.subheadline)
                        .secondaryText()
                }
                
                Spacer()
                
                // Promotional indicator
                ZStack {
                    Circle()
                        .fill(.orange.opacity(0.1))
                        .frame(width: 50, height: 50)
                    
                    Image(systemName: "tag.fill")
                        .font(.title2)
                        .foregroundColor(.orange)
                }
            }
            
            // View mode toggle and stats
            HStack {
                // Quick stats
                if !viewModel.promotionalEmails.isEmpty {
                    HStack(spacing: DesignSystem.Spacing.lg) {
                        StatItem(
                            value: viewModel.promotionalEmails.filter { !$0.isRead }.count,
                            label: "Unread",
                            color: DesignSystem.Colors.accent
                        )
                        
                        StatItem(
                            value: viewModel.promotionalEmails.filter { $0.body.lowercased().contains("sale") || $0.body.lowercased().contains("discount") }.count,
                            label: "Sales",
                            color: .green
                        )
                        
                        Spacer()
                    }
                }
                
                // View mode picker
                HStack(spacing: 0) {
                    ForEach(ViewMode.allCases, id: \.self) { mode in
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewMode = mode
                            }
                        }) {
                            HStack(spacing: DesignSystem.Spacing.xs) {
                                Image(systemName: mode.icon)
                                    .font(.caption)
                                Text(mode.rawValue)
                                    .font(DesignSystem.Typography.caption)
                            }
                            .foregroundColor(viewMode == mode ? .white : DesignSystem.Colors.systemTextSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(viewMode == mode ? DesignSystem.Colors.accent : Color.clear)
                            )
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(DesignSystem.Colors.systemSecondaryBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(DesignSystem.Colors.systemBorder, lineWidth: 1)
                        )
                )
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
    
    // MARK: - List View
    
    private var promotionalEmailsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.promotionalEmails.sorted { $0.date > $1.date }) { email in
                    PromotionalEmailListRow(email: email) {
                        selectedEmail = email
                        showingEmailDetail = true
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                    
                    if email.id != viewModel.promotionalEmails.last?.id {
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
    
    // MARK: - Grid View
    
    private var promotionalEmailsGrid: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: DesignSystem.Spacing.md),
                GridItem(.flexible(), spacing: DesignSystem.Spacing.md)
            ], spacing: DesignSystem.Spacing.md) {
                ForEach(viewModel.promotionalEmails.sorted { $0.date > $1.date }) { email in
                    PromotionalEmailGridCard(email: email) {
                        selectedEmail = email
                        showingEmailDetail = true
                    }
                    .transition(.asymmetric(
                        insertion: .scale.combined(with: .opacity),
                        removal: .scale.combined(with: .opacity)
                    ))
                }
            }
            .padding(DesignSystem.Spacing.lg)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        Group {
            if viewMode == .list {
                VStack(spacing: DesignSystem.Spacing.lg) {
                    ForEach(0..<5, id: \.self) { _ in
                        SkeletonEmailRow()
                    }
                }
                .padding(DesignSystem.Spacing.lg)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: DesignSystem.Spacing.md),
                    GridItem(.flexible(), spacing: DesignSystem.Spacing.md)
                ], spacing: DesignSystem.Spacing.md) {
                    ForEach(0..<6, id: \.self) { _ in
                        SkeletonGridCard()
                    }
                }
                .padding(DesignSystem.Spacing.lg)
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            ZStack {
                Circle()
                    .fill(.orange.opacity(0.1))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "tag")
                    .font(.system(size: 40))
                    .foregroundColor(.orange.opacity(0.6))
            }
            
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text("No Promotional Emails")
                    .font(DesignSystem.Typography.title3)
                    .primaryText()
                
                Text("Promotional offers and deals will appear here")
                    .font(DesignSystem.Typography.body)
                    .secondaryText()
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignSystem.Spacing.lg)
    }
}

// MARK: - Promotional Email List Row

struct PromotionalEmailListRow: View {
    let email: Email
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: DesignSystem.Spacing.md) {
                // Promotional avatar with brand color
                ZStack {
                    Circle()
                        .fill(brandColor.opacity(0.1))
                        .frame(width: 50, height: 50)
                        .overlay(
                            Circle()
                                .stroke(brandColor.opacity(0.3), lineWidth: 2)
                        )
                    
                    if !email.isRead {
                        // Unread indicator
                        Circle()
                            .fill(DesignSystem.Colors.accent)
                            .frame(width: 12, height: 12)
                            .offset(x: 15, y: -15)
                    }
                    
                    Image(systemName: "tag.fill")
                        .font(.title3)
                        .foregroundColor(brandColor)
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
                        
                        Text(RelativeDateTimeFormatter().localizedString(for: email.date, relativeTo: Date()))
                            .font(DesignSystem.Typography.caption)
                            .secondaryText()
                    }
                    
                    // Subject with offer highlighting
                    Text(highlightOffers(in: email.subject))
                        .font(email.isRead ? DesignSystem.Typography.subheadline : DesignSystem.Typography.callout)
                        .lineLimit(1)
                    
                    // Preview
                    Text(email.body)
                        .font(DesignSystem.Typography.footnote)
                        .secondaryText()
                        .lineLimit(2)
                    
                    // Offer tags
                    if !offerTags.isEmpty {
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            ForEach(offerTags, id: \.self) { tag in
                                Text(tag)
                                    .font(DesignSystem.Typography.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(tagColor(for: tag).gradient)
                                    )
                            }
                            
                            Spacer()
                        }
                    }
                }
                
                // Action indicator
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(DesignSystem.Colors.systemTextSecondary)
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
    
    private var brandColor: Color {
        // Simple hash-based color generation from sender domain
        let domain = email.sender.email.components(separatedBy: "@").last ?? ""
        let colors: [Color] = [.orange, .red, .purple, .blue, .green, .pink]
        return colors[domain.hash % colors.count]
    }
    
    private var offerTags: [String] {
        let content = (email.subject + " " + email.body).lowercased()
        var tags: [String] = []
        
        if content.contains("free") { tags.append("FREE") }
        if content.contains("sale") { tags.append("SALE") }
        if content.contains("discount") || content.contains("%") { tags.append("DISCOUNT") }
        if content.contains("limited") { tags.append("LIMITED") }
        if content.contains("deal") { tags.append("DEAL") }
        
        return Array(tags.prefix(3)) // Limit to 3 tags
    }
    
    private func tagColor(for tag: String) -> Color {
        switch tag {
        case "FREE": return .green
        case "SALE": return .red
        case "DISCOUNT": return .orange
        case "LIMITED": return .purple
        case "DEAL": return .blue
        default: return .gray
        }
    }
    
    private func highlightOffers(in text: String) -> AttributedString {
        var attributedString = AttributedString(text)
        let offerKeywords = ["free", "sale", "discount", "deal", "off", "%"]
        
        for keyword in offerKeywords {
            if let range = attributedString.range(of: keyword, options: .caseInsensitive) {
                attributedString[range].foregroundColor = .orange
                attributedString[range].font = .system(size: 16, weight: .semibold)
            }
        }
        
        return attributedString
    }
}

// MARK: - Promotional Email Grid Card

struct PromotionalEmailGridCard: View {
    let email: Email
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                // Header with brand and date
                HStack {
                    // Brand avatar
                    ZStack {
                        Circle()
                            .fill(brandColor.opacity(0.1))
                            .frame(width: 32, height: 32)
                        
                        if !email.isRead {
                            Circle()
                                .fill(DesignSystem.Colors.accent)
                                .frame(width: 8, height: 8)
                                .offset(x: 10, y: -10)
                        }
                        
                        Image(systemName: "tag.fill")
                            .font(.caption)
                            .foregroundColor(brandColor)
                    }
                    
                    Spacer()
                    
                    Text(RelativeDateTimeFormatter().localizedString(for: email.date, relativeTo: Date()))
                        .font(DesignSystem.Typography.caption2)
                        .secondaryText()
                }
                
                // Brand name
                Text(email.sender.displayName)
                    .font(DesignSystem.Typography.caption)
                    .fontWeight(.medium)
                    .primaryText()
                    .lineLimit(1)
                
                // Subject
                Text(email.subject)
                    .font(DesignSystem.Typography.subheadline)
                    .fontWeight(email.isRead ? .regular : .semibold)
                    .foregroundColor(email.isRead ? DesignSystem.Colors.systemTextSecondary : DesignSystem.Colors.systemTextPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Preview
                Text(email.body)
                    .font(DesignSystem.Typography.footnote)
                    .secondaryText()
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                
                Spacer()
                
                // Offer indicator
                if let mainOffer = offerTags.first {
                    HStack {
                        Text(mainOffer)
                            .font(DesignSystem.Typography.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(tagColor(for: mainOffer).gradient)
                            )
                        
                        Spacer()
                    }
                }
            }
            .padding(DesignSystem.Spacing.md)
            .frame(minHeight: 160)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .fill(DesignSystem.Colors.systemSecondaryBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                            .stroke(isPressed ? brandColor.opacity(0.5) : DesignSystem.Colors.systemBorder, lineWidth: 1)
                    )
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
            .shadow(color: DesignSystem.Shadow.light, radius: 2, x: 0, y: 1)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(minimumDuration: 0.0, maximumDistance: .infinity) {
            // Long press action
        } onPressingChanged: { pressing in
            isPressed = pressing
        }
    }
    
    private var brandColor: Color {
        let domain = email.sender.email.components(separatedBy: "@").last ?? ""
        let colors: [Color] = [.orange, .red, .purple, .blue, .green, .pink]
        return colors[domain.hash % colors.count]
    }
    
    private var offerTags: [String] {
        let content = (email.subject + " " + email.body).lowercased()
        var tags: [String] = []
        
        if content.contains("free") { tags.append("FREE") }
        if content.contains("sale") { tags.append("SALE") }
        if content.contains("discount") || content.contains("%") { tags.append("DISCOUNT") }
        if content.contains("limited") { tags.append("LIMITED") }
        if content.contains("deal") { tags.append("DEAL") }
        
        return Array(tags.prefix(2)) // Limit to 2 tags for grid
    }
    
    private func tagColor(for tag: String) -> Color {
        switch tag {
        case "FREE": return .green
        case "SALE": return .red
        case "DISCOUNT": return .orange
        case "LIMITED": return .purple
        case "DEAL": return .blue
        default: return .gray
        }
    }
}

// MARK: - Skeleton Grid Card

struct SkeletonGridCard: View {
    @State private var animateGradient = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Circle()
                    .fill(shimmerGradient)
                    .frame(width: 32, height: 32)
                
                Spacer()
                
                Rectangle()
                    .fill(shimmerGradient)
                    .frame(width: 40, height: 10)
                    .cornerRadius(4)
            }
            
            Rectangle()
                .fill(shimmerGradient)
                .frame(width: 80, height: 12)
                .cornerRadius(4)
            
            Rectangle()
                .fill(shimmerGradient)
                .frame(height: 14)
                .cornerRadius(4)
            
            Rectangle()
                .fill(shimmerGradient)
                .frame(height: 12)
                .cornerRadius(4)
            
            Rectangle()
                .fill(shimmerGradient)
                .frame(width: 100, height: 12)
                .cornerRadius(4)
            
            Spacer()
            
            Capsule()
                .fill(shimmerGradient)
                .frame(width: 50, height: 16)
        }
        .padding(DesignSystem.Spacing.md)
        .frame(minHeight: 160)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                .fill(DesignSystem.Colors.systemSecondaryBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                        .stroke(DesignSystem.Colors.systemBorder, lineWidth: 1)
                )
        )
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

struct PromotionalEmailsView_Previews: PreviewProvider {
    static var previews: some View {
        PromotionalEmailsView()
    }
}