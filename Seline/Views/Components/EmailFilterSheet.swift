import SwiftUI

struct EmailFilterSheet: View {
    @StateObject private var filterManager = EmailFilterManager.shared
    @StateObject private var emailService = EmailService.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss

    let onFiltersChanged: () -> Void

    private var filteredEmailCount: Int {
        let allEmails = emailService.inboxEmails + emailService.sentEmails
        return filterManager.getFilteredEmailCount(from: allEmails)
    }

    private var totalEmailCount: Int {
        return emailService.inboxEmails.count + emailService.sentEmails.count
    }

    private var allEmails: [Email] {
        return emailService.inboxEmails + emailService.sentEmails
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with email count
                headerSection

                // Filter categories list
                ScrollView {
                    LazyVStack(spacing: ShadcnSpacing.sm) {
                        ForEach(EmailCategory.allCases) { category in
                            EmailFilterRow(
                                category: category,
                                isEnabled: filterManager.isCategoryEnabled(category),
                                emailCount: filterManager.getEmailCountForCategory(category, from: allEmails),
                                onToggle: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        filterManager.toggleCategory(category)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, ShadcnSpacing.md)
                }

                Spacer()

                // Bottom action buttons
                bottomActionSection
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
            .navigationTitle("Email Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        onFiltersChanged()
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color(red: 0.518, green: 0.792, blue: 0.914) : Color(red: 0.20, green: 0.34, blue: 0.40))
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(Color.gray)
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: ShadcnSpacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Showing \(filteredEmailCount) of \(totalEmailCount) emails")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.shadcnForeground(colorScheme))

                    Text("Choose which types of emails to display")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, ShadcnSpacing.md)
        }
    }

    private var bottomActionSection: some View {
        VStack(spacing: ShadcnSpacing.md) {
            Divider()
                .background(Color.shadcnBorder(colorScheme))

            HStack(spacing: ShadcnSpacing.md) {
                // Select All button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        filterManager.enableAllCategories()
                    }
                }) {
                    Text("Select All")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.black : Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: ShadcnRadius.lg)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.9))
                        )
                }

                // Reset to Defaults button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        filterManager.resetToDefaults()
                    }
                }) {
                    Text("Reset")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? Color.shadcnForeground(colorScheme) : Color.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: ShadcnRadius.lg)
                                .fill(colorScheme == .dark ?
                                    Color.shadcnMuted(colorScheme) :
                                    Color.shadcnBorder(colorScheme))
                        )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, ShadcnSpacing.lg)
        }
    }
}

struct EmailFilterRow: View {
    let category: EmailCategory
    let isEnabled: Bool
    let emailCount: Int
    let onToggle: () -> Void

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: ShadcnSpacing.md) {
                // Category icon
                Image(systemName: category.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isEnabled ?
                        (colorScheme == .dark ? Color(red: 0.518, green: 0.792, blue: 0.914) : Color(red: 0.20, green: 0.34, blue: 0.40)) :
                        Color.gray
                    )
                    .frame(width: 24, height: 24)

                // Category info
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.displayName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color.shadcnForeground(colorScheme))

                    Text(category.description)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                        .lineLimit(2)
                }

                Spacer()

                // Email count
                Text("\(emailCount)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.shadcnMutedForeground(colorScheme))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(colorScheme == .dark ?
                                Color.shadcnMuted(colorScheme).opacity(0.3) :
                                Color.shadcnMuted(colorScheme).opacity(0.2))
                    )

                // Checkbox
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            isEnabled ?
                                (colorScheme == .dark ? Color(red: 0.518, green: 0.792, blue: 0.914) : Color(red: 0.20, green: 0.34, blue: 0.40)) :
                                Color.gray.opacity(0.5),
                            lineWidth: 1.5
                        )
                        .frame(width: 20, height: 20)

                    if isEnabled {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(colorScheme == .dark ? Color(red: 0.518, green: 0.792, blue: 0.914) : Color(red: 0.20, green: 0.34, blue: 0.40))
                            .frame(width: 20, height: 20)

                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(.vertical, ShadcnSpacing.md)
            .padding(.horizontal, ShadcnSpacing.md)
            .background(
                RoundedRectangle(cornerRadius: ShadcnRadius.xl)
                    .fill(colorScheme == .dark ? Color.black : Color.white)
            )
            .shadow(
                color: colorScheme == .dark ? .white.opacity(0.08) : .gray.opacity(0.15),
                radius: colorScheme == .dark ? 8 : 12,
                x: 0,
                y: colorScheme == .dark ? 3 : 4
            )
            .shadow(
                color: colorScheme == .dark ? .white.opacity(0.04) : .gray.opacity(0.08),
                radius: colorScheme == .dark ? 4 : 6,
                x: 0,
                y: colorScheme == .dark ? 1 : 2
            )
            .shadow(
                color: colorScheme == .dark ? .white.opacity(0.02) : .clear,
                radius: colorScheme == .dark ? 8 : 0,
                x: 0,
                y: colorScheme == .dark ? 2 : 0
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    EmailFilterSheet(onFiltersChanged: {})
}