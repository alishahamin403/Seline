//
//  AISummaryEmailCard.swift
//  Seline
//
//  AI-powered email summary card for Today's Emails view
//

import SwiftUI

struct AISummaryEmailCard: View {
    let email: Email
    let onOpenInGmail: () -> Void
    
    @State private var showingActions = false
    @State private var isPressed = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Email Card Content
            VStack(alignment: .leading, spacing: 10) {
                // Header: Sender and Time
                HStack(alignment: .top, spacing: 10) {
                    // Sender Avatar
                    ZStack {
                        Circle()
                            .fill(DesignSystem.Colors.accent.opacity(0.1))
                            .frame(width: 40, height: 40)
                        
                        Text(String(email.sender.displayName.prefix(1).uppercased()))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.accent)
                        
                        // Unread indicator
                        if !email.isRead {
                            Circle()
                                .fill(DesignSystem.Colors.accent)
                                .frame(width: 6, height: 6)
                                .offset(x: 15, y: -15)
                        }
                    }
                    
                    // Sender Info and Subject
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(email.sender.displayName)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text(formatEmailTime(email.date))
                                .font(.system(size: 10, weight: .regular, design: .rounded))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                        
                        Text(email.subject)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                
                // Attachments (if any) - More compact
                if email.hasAttachments {
                    HStack(spacing: 4) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.7))
                        
                        Text("\(email.attachments.count) attachment\(email.attachments.count == 1 ? "" : "s")")
                            .font(.system(size: 9, weight: .regular, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.7))
                    }
                }
            }
            .padding(10)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DesignSystem.Colors.surface)
        )
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .padding(.horizontal, 4)
        .onTapGesture {
            // Light haptic feedback on card tap
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            onOpenInGmail()
        }
        .onLongPressGesture(
            minimumDuration: 0,
            maximumDistance: .infinity,
            perform: {},
            onPressingChanged: { pressing in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = pressing
                }
            }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Email from \(email.sender.displayName): \(email.subject)")
        .accessibilityHint("Double tap to open in Gmail, swipe up for more actions")
        .accessibilityActions {
            Button("Open in Gmail") { onOpenInGmail() }
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatEmailTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Skeleton Loading Card

struct SkeletonSummaryCard: View {
    @State private var animateGradient = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header skeleton
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(shimmerGradient)
                    .frame(width: 48, height: 48)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Rectangle()
                            .fill(shimmerGradient)
                            .frame(width: 120, height: 16)
                            .cornerRadius(4)
                        
                        Spacer()
                        
                        Rectangle()
                            .fill(shimmerGradient)
                            .frame(width: 50, height: 14)
                            .cornerRadius(4)
                    }
                    
                    Rectangle()
                        .fill(shimmerGradient)
                        .frame(height: 18)
                        .cornerRadius(4)
                }
            }
            
            // Summary skeleton
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Rectangle()
                        .fill(shimmerGradient)
                        .frame(width: 80, height: 12)
                        .cornerRadius(4)
                    
                    Spacer()
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Rectangle()
                        .fill(shimmerGradient)
                        .frame(height: 12)
                        .cornerRadius(4)
                    
                    Rectangle()
                        .fill(shimmerGradient)
                        .frame(width: 200, height: 12)
                        .cornerRadius(4)
                }
            }
            
            // Action buttons skeleton
            HStack(spacing: 12) {
                Rectangle()
                    .fill(shimmerGradient)
                    .frame(width: 120, height: 36)
                    .cornerRadius(18)
                
                Spacer()
                
                HStack(spacing: 16) {
                    Circle()
                        .fill(shimmerGradient)
                        .frame(width: 20, height: 20)
                    
                    Circle()
                        .fill(shimmerGradient)
                        .frame(width: 20, height: 20)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DesignSystem.Colors.surface)
        )
        .padding(.horizontal, 4)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                animateGradient.toggle()
            }
        }
    }
    
    private var shimmerGradient: LinearGradient {
        LinearGradient(
            colors: [
                DesignSystem.Colors.textSecondary.opacity(0.1),
                DesignSystem.Colors.textSecondary.opacity(0.05),
                DesignSystem.Colors.textSecondary.opacity(0.1)
            ],
            startPoint: animateGradient ? .leading : .trailing,
            endPoint: animateGradient ? .trailing : .leading
        )
    }
}

// MARK: - Preview

struct AISummaryEmailCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            AISummaryEmailCard(
                email: Email(
                    id: "1",
                    subject: "Meeting Invitation: Q1 Planning Review",
                    sender: EmailContact(name: "Sarah Johnson", email: "sarah@example.com"),
                    recipients: [EmailContact(name: "Team", email: "team@example.com")],
                    body: "Hi team, I'd like to schedule our Q1 planning review meeting for next Tuesday. Please confirm your availability and review the attached agenda.",
                    date: Date(),
                    isRead: false,
                    isImportant: true,
                    labels: ["INBOX", "IMPORTANT"],
                    attachments: [EmailAttachment(filename: "agenda.pdf", mimeType: "application/pdf", size: 1024)]
                ),
                onOpenInGmail: { }
            )
            
            SkeletonSummaryCard()
        }
        .padding()
        .background(DesignSystem.Colors.background)
        .preferredColorScheme(.dark)
    }
}