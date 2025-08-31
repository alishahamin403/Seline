//
//  SettingsView.swift
//  Seline
//
//  Created by Claude on 2025-08-24.
//

import SwiftUI

struct AdvancedSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var authService = AuthenticationService.shared
    @StateObject private var themeManager = ThemeManager.shared
    @State private var notificationsEnabled = true
    @State private var importantEmailsNotifications = true
    @State private var promotionalEmailsNotifications = true
    @State private var calendarEmailsNotifications = true
    @State private var emailSyncInterval = 15 // minutes
    @State private var showingEmailAccounts = false
    @State private var showingDataUsage = false
    @State private var showingAbout = false
    @State private var hapticFeedbackEnabled = true
    @State private var smartCategorization = true
    @State private var readReceiptsEnabled = false
    @State private var openAIKeyInput = ""
    @State private var showingOpenAIAlert = false
    @State private var openAIAlertMessage = ""
    
    private let syncIntervals = [5, 15, 30, 60]

    // MARK: - Notification Settings

    private func loadNotificationSettings() {
        notificationsEnabled = NotificationManager.shared.notificationsEnabled
        importantEmailsNotifications = NotificationManager.shared.importantEmailsEnabled
        promotionalEmailsNotifications = NotificationManager.shared.promotionalEmailsEnabled
        calendarEmailsNotifications = NotificationManager.shared.calendarEmailsEnabled
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Clean header with proper SafeArea handling
            headerSection
            
            // Settings content
            ScrollView {
                VStack(spacing: 32) {
                    // User Profile Section
                    userProfileSection
                    
                    // App Settings
                    appSettingsSection

                    // AI & Search Settings
                    aiSettingsSection
                    
                    // Email Settings
                    emailSettingsSection
                    
                    // Support & About
                    supportSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 100) // Extra bottom padding
            }
        }
        .linearBackground()
        .sheet(isPresented: $showingEmailAccounts) {
            EmailAccountsView()
        }
        .sheet(isPresented: $showingDataUsage) {
            DataUsageView()
        }
        .sheet(isPresented: $showingAbout) {
            AboutView()
        }
        .onAppear {
            loadNotificationSettings()
            // Preload existing OpenAI key state (masked)
            if SecureStorage.shared.hasOpenAIKey() {
                openAIKeyInput = "••••••••••••••••••••••••••"
            } else {
                openAIKeyInput = ""
            }
        }
        .onChange(of: notificationsEnabled) { newValue in
            NotificationManager.shared.notificationsEnabled = newValue
        }
        .onChange(of: importantEmailsNotifications) { newValue in
            NotificationManager.shared.importantEmailsEnabled = newValue
        }
        .onChange(of: promotionalEmailsNotifications) { newValue in
            NotificationManager.shared.promotionalEmailsEnabled = newValue
        }
        .onChange(of: calendarEmailsNotifications) { newValue in
            NotificationManager.shared.calendarEmailsEnabled = newValue
        }
    }

    // MARK: - AI & Search Settings Section
    
    private var aiSettingsSection: some View {
        VStack(spacing: 16) {
            sectionHeader("AI & Search")
            
            VStack(spacing: 0) {
                // OpenAI Status
                SettingsRow(
                    icon: "sparkles",
                    title: "OpenAI Integration",
                    subtitle: OpenAIService.shared.isConfigured ? "Enabled (Real API)" : "Disabled (Mock)",
                    iconColor: .purple,
                    showChevron: false,
                    accessory: {
                        // no-op
                    }
                )
                
                Divider()
                    .padding(.leading, 56)
                
                // API Key Input + Save
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "key.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.orange)
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.orange.opacity(0.15))
                            )
                        
                        TextField("Enter OpenAI API Key (sk-...)", text: $openAIKeyInput)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            Task {
                                await saveOpenAIKey()
                            }
                        }) {
                            HStack {
                                Image(systemName: "bolt.fill")
                                Text(OpenAIService.shared.isConfigured ? "Update Key & Enable" : "Enable Real API")
                            }
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(DesignSystem.Colors.accent)
                            )
                        }

                        if SecureStorage.shared.hasOpenAIKey() {
                            Button(action: {
                                SecureStorage.shared.clearOpenAIKey()
                                OpenAIService.shared.refreshConfiguration()
                                openAIKeyInput = ""
                            }) {
                                HStack {
                                    Image(systemName: "xmark.circle.fill")
                                    Text("Remove Key")
                                }
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.red)
                                )
                            }
                        }
                    }
                    .padding(.bottom, 12)
                }
                .padding(.top, 12)
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(DesignSystem.Colors.surfaceSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(DesignSystem.Colors.border.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .alert("OpenAI", isPresented: $showingOpenAIAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(openAIAlertMessage)
        }
    }
    
    private func saveOpenAIKey() async {
        let trimmed = openAIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            openAIAlertMessage = "Please enter your OpenAI API key (starts with sk-)."
            showingOpenAIAlert = true
            return
        }
        
        do {
            try await OpenAIService.shared.configureAPIKey(trimmed)
            OpenAIService.shared.refreshConfiguration()
            openAIAlertMessage = "OpenAI enabled. Real API will be used for searches."
            showingOpenAIAlert = true
            // Mask the field after saving
            openAIKeyInput = "••••••••••••••••••••••••••"
        } catch {
            openAIAlertMessage = error.localizedDescription
            showingOpenAIAlert = true
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
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
            
            Text("Settings")
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
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 20)
        .background(DesignSystem.Colors.surface)
    }
    
    // MARK: - User Profile Section
    
    private var userProfileSection: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Profile")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Spacer()
            }
            
            HStack(spacing: 16) {
                // Profile Avatar
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.accent)
                        .frame(width: 60, height: 60)
                    
                    Text(userInitials)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(userName)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    Text(userEmail)
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    
                    HStack(spacing: 8) {
                        Text(connectionStatus)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(connectionStatusColor)
                        
                        Circle()
                            .fill(connectionStatusColor)
                            .frame(width: 6, height: 6)
                    }
                }
                
                Spacer()
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DesignSystem.Colors.surfaceSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(DesignSystem.Colors.border.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    // MARK: - App Settings Section
    
    private var appSettingsSection: some View {
        VStack(spacing: 16) {
            sectionHeader("Appearance & Behavior")
            
            VStack(spacing: 0) {
                // Theme selector with manual controls
                SettingsRow(
                    icon: themeManager.selectedTheme.icon,
                    title: "Appearance",
                    subtitle: themeManager.selectedTheme.displayName,
                    iconColor: themeManager.selectedTheme == .dark ? .indigo : (themeManager.selectedTheme == .light ? .orange : .blue),
                    showChevron: false
                ) {
                    // No action needed, handled by accessory
                } accessory: {
                    Menu {
                        ForEach(ThemeMode.allCases, id: \.self) { theme in
                            Button(action: {
                                themeManager.selectedTheme = theme
                            }) {
                                HStack {
                                    Image(systemName: theme.icon)
                                    Text(theme.displayName)
                                    if themeManager.selectedTheme == theme {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                            .foregroundColor(DesignSystem.Colors.accent)
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(themeManager.selectedTheme.displayName)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                            
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(DesignSystem.Colors.textTertiary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(DesignSystem.Colors.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(DesignSystem.Colors.border, lineWidth: 1)
                                )
                        )
                    }
                }
                
                Divider()
                    .padding(.leading, 56)
                
                // Haptic Feedback
                SettingsRow(
                    icon: "iphone.radiowaves.left.and.right",
                    title: "Haptic Feedback",
                    subtitle: hapticFeedbackEnabled ? "Enabled" : "Disabled",
                    iconColor: .blue,
                    showChevron: false
                ) {
                    // No action needed
                } accessory: {
                    Toggle("", isOn: $hapticFeedbackEnabled)
                        .labelsHidden()
                }
                
                Divider()
                    .padding(.leading, 56)
                
                // Email Notifications
                VStack(spacing: 16) {
                    // Main notifications toggle
                    SettingsRow(
                        icon: "bell.fill",
                        title: "Email Notifications",
                        subtitle: notificationsEnabled ? "Enabled" : "Disabled",
                        iconColor: .red,
                        showChevron: false
                    ) {
                        // No action needed
                    } accessory: {
                        Toggle("", isOn: $notificationsEnabled)
                            .labelsHidden()
                    }

                    if notificationsEnabled {
                        // Individual category toggles
                        VStack(spacing: 12) {
                            Divider()
                                .padding(.leading, 56)

                            SettingsRow(
                                icon: "exclamationmark.circle.fill",
                                title: "Important Emails",
                                subtitle: importantEmailsNotifications ? "Enabled" : "Disabled",
                                iconColor: .red,
                                showChevron: false
                            ) {
                                // No action needed
                            } accessory: {
                                Toggle("", isOn: $importantEmailsNotifications)
                                    .labelsHidden()
                            }

                            SettingsRow(
                                icon: "tag.fill",
                                title: "Promotional Emails",
                                subtitle: promotionalEmailsNotifications ? "Enabled" : "Disabled",
                                iconColor: .orange,
                                showChevron: false
                            ) {
                                // No action needed
                            } accessory: {
                                Toggle("", isOn: $promotionalEmailsNotifications)
                                    .labelsHidden()
                            }

                            SettingsRow(
                                icon: "calendar",
                                title: "Calendar Emails",
                                subtitle: calendarEmailsNotifications ? "Enabled" : "Disabled",
                                iconColor: .blue,
                                showChevron: false
                            ) {
                                // No action needed
                            } accessory: {
                                Toggle("", isOn: $calendarEmailsNotifications)
                                    .labelsHidden()
                            }
                        }
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(DesignSystem.Colors.surfaceSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(DesignSystem.Colors.border.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }
    
    // MARK: - Email Settings Section
    
    private var emailSettingsSection: some View {
        VStack(spacing: 16) {
            sectionHeader("Email")
            
            VStack(spacing: 0) {
                // Smart Categorization
                SettingsRow(
                    icon: "brain.head.profile",
                    title: "Smart Categorization",
                    subtitle: smartCategorization ? "Enabled" : "Disabled",
                    iconColor: .purple,
                    showChevron: false
                ) {
                    // No action needed
                } accessory: {
                    Toggle("", isOn: $smartCategorization)
                        .labelsHidden()
                }
                
                Divider()
                    .padding(.leading, 56)
                
                // Sync Interval
                SettingsRow(
                    icon: "arrow.clockwise",
                    title: "Sync Interval",
                    subtitle: "\(emailSyncInterval) minutes",
                    iconColor: .green,
                    action: {
                        // Sync interval action
                    }
                )
                
                Divider()
                    .padding(.leading, 56)
                
                // Read Receipts
                SettingsRow(
                    icon: "checkmark.circle.fill",
                    title: "Read Receipts",
                    subtitle: readReceiptsEnabled ? "Enabled" : "Disabled",
                    iconColor: .blue,
                    showChevron: false
                ) {
                    // No action needed
                } accessory: {
                    Toggle("", isOn: $readReceiptsEnabled)
                        .labelsHidden()
                }
                
                Divider()
                    .padding(.leading, 56)
                
                // Email Accounts
                SettingsRow(
                    icon: "person.crop.circle",
                    title: "Email Accounts",
                    subtitle: "Manage connected accounts",
                    iconColor: .orange
                ) {
                    showingEmailAccounts = true
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(DesignSystem.Colors.surfaceSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(DesignSystem.Colors.border.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }
    
    // MARK: - Support Section
    
    private var supportSection: some View {
        VStack(spacing: 16) {
            sectionHeader("Support & Info")
            
            VStack(spacing: 0) {
                // Data Usage
                SettingsRow(
                    icon: "chart.bar.fill",
                    title: "Data Usage",
                    subtitle: "View storage and bandwidth",
                    iconColor: .cyan
                ) {
                    showingDataUsage = true
                }
                
                Divider()
                    .padding(.leading, 56)
                
                // About
                SettingsRow(
                    icon: "info.circle.fill",
                    title: "About",
                    subtitle: "Version 1.0.0",
                    iconColor: .gray
                ) {
                    showingAbout = true
                }
                
                Divider()
                    .padding(.leading, 56)
                
                // Privacy Policy
                SettingsRow(
                    icon: "hand.raised.fill",
                    title: "Privacy Policy",
                    subtitle: "How we protect your data",
                    iconColor: .indigo,
                    action: {
                        // Open privacy policy
                    }
                )
                
                Divider()
                    .padding(.leading, 56)
                
                // Help & Support
                SettingsRow(
                    icon: "questionmark.circle.fill",
                    title: "Help & Support",
                    subtitle: "Get help with Seline",
                    iconColor: .green,
                    action: {
                        // Open help
                    }
                )
                
                Divider()
                    .padding(.leading, 56)
                
                // Sign Out
                SettingsRow(
                    icon: "rectangle.portrait.and.arrow.right",
                    title: "Sign Out",
                    subtitle: "Sign out of your account",
                    iconColor: .red,
                    showChevron: false,
                    action: {
                        Task {
                            await authService.signOut()
                        }
                    }
                )
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(DesignSystem.Colors.surfaceSecondary)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(DesignSystem.Colors.border.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }
    
    // MARK: - Helper Views
    
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textSecondary)
            
            Spacer()
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - User Data Computed Properties
    
    private var userName: String {
        authService.user?.name ?? "User"
    }
    
    private var userEmail: String {
        authService.user?.email ?? "Not connected"
    }
    
    private var userInitials: String {
        let name = userName
        let components = name.components(separatedBy: " ")
        if components.count >= 2 {
            let firstInitial = String(components[0].prefix(1)).uppercased()
            let lastInitial = String(components[1].prefix(1)).uppercased()
            return firstInitial + lastInitial
        } else {
            return String(name.prefix(2)).uppercased()
        }
    }
    
    private var connectionStatus: String {
        authService.isAuthenticated ? "Connected" : "Not Connected"
    }
    
    private var connectionStatusColor: Color {
        authService.isAuthenticated ? .green : .red
    }
}

// MARK: - Settings Row Component

struct SettingsRow<Content: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    let iconColor: Color
    var showChevron: Bool = true
    let action: (() -> Void)?
    let accessory: () -> Content
    
    init(
        icon: String,
        title: String,
        subtitle: String,
        iconColor: Color,
        showChevron: Bool = true,
        action: (() -> Void)? = nil,
        @ViewBuilder accessory: @escaping () -> Content = { EmptyView() }
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.iconColor = iconColor
        self.showChevron = showChevron
        self.action = action
        self.accessory = accessory
    }
    
    var body: some View {
        Button(action: {
            action?()
        }) {
            HStack(spacing: 16) {
                // Icon with adaptive black & white theme
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(DesignSystem.Colors.primaryGradient)
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(
                            Color(UIColor { traitCollection in
                                traitCollection.userInterfaceStyle == .dark ? 
                                UIColor.black : UIColor.white
                            })
                        )
                }
                
                // Content
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                    
                    Text(subtitle)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                
                Spacer()
                
                // Accessory content (like Toggle)
                accessory()
                
                // Chevron
                if showChevron && action != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.6))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(action == nil && Content.self == EmptyView.self)
    }
}

// MARK: - Additional Views (Placeholders)

struct EmailAccountsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Text("Email Accounts")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(DesignSystem.Colors.accent)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    Image(systemName: "envelope.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gmail Account")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        
                        Text(AuthenticationService.shared.user?.email ?? "Not connected")
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                    
                    Spacer()
                    
                    Text(AuthenticationService.shared.isAuthenticated ? "Connected" : "Not Connected")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(AuthenticationService.shared.isAuthenticated ? .green : .red)
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(DesignSystem.Colors.surfaceSecondary)
                )
            }
            .padding(.horizontal, 24)
            
            Spacer()
        }
        .background(DesignSystem.Colors.surface)
    }
}

struct DataUsageView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var quotaManager = GmailQuotaManager.shared
    @StateObject private var cacheManager = EmailCacheManager.shared
    
    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Text("Data Usage")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(DesignSystem.Colors.accent)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            
            VStack(spacing: 20) {
                // API Quota Status Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("API Quota Status")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        
                        Spacer()
                        
                        HStack(spacing: 8) {
                            Circle()
                                .fill(quotaStatusColor)
                                .frame(width: 8, height: 8)
                            
                            Text(quotaManager.quotaStatus.rawValue)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(quotaStatusColor)
                        }
                    }
                    
                    Text(quotaManager.quotaStatus.description)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
                
                Divider()
                
                // API Usage Metrics
                VStack(spacing: 12) {
                    HStack {
                        Text("Requests in Last Minute")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                        
                        Spacer()
                        
                        Text("\(quotaManager.requestsInLastMinute)")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.accent)
                    }
                    
                    HStack {
                        Text("API Usage Today")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                        
                        Spacer()
                        
                        Text("\(quotaManager.apiUsageToday)")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.accent)
                    }
                }
                
                Divider()
                
                // Cache Performance
                VStack(spacing: 12) {
                    HStack {
                        Text("Cache Hit Rate")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                        
                        Spacer()
                        
                        Text(String(format: "%.1f%%", cacheManager.cacheHitRate * 100))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(cacheHitRateColor)
                    }
                    
                    HStack {
                        Text("Emails Cached")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                        
                        Spacer()
                        
                        Text("\(cacheManager.currentCacheSize)")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.accent)
                    }
                    
                    HStack {
                        Text("Cache Requests")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                        
                        Spacer()
                        
                        Text("\(cacheManager.totalCacheRequests)")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.accent)
                    }
                }
                
                if cacheManager.currentCacheSize > 0 {
                    Button(action: {
                        cacheManager.clearCache()
                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                        impactFeedback.impactOccurred()
                    }) {
                        HStack {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 14, weight: .medium))
                            
                            Text("Clear Cache")
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.red)
                        )
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(DesignSystem.Colors.surfaceSecondary)
            )
            .padding(.horizontal, 24)
            
            Spacer()
        }
        .background(DesignSystem.Colors.surface)
    }
    
    // MARK: - Computed Properties
    
    private var quotaStatusColor: Color {
        switch quotaManager.quotaStatus {
        case .normal: return .green
        case .warning: return .yellow
        case .limited: return .orange
        case .exceeded: return .red
        }
    }
    
    private var cacheHitRateColor: Color {
        let rate = cacheManager.cacheHitRate
        if rate >= 0.8 { return .green }
        else if rate >= 0.5 { return .orange }
        else { return .red }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Text("About")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundColor(DesignSystem.Colors.accent)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            
            VStack(spacing: 20) {
                Image(systemName: "envelope.fill")
                    .font(.system(size: 60))
                    .foregroundColor(DesignSystem.Colors.accent)
                
                VStack(spacing: 8) {
                    Text("Seline")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    
                    Text("Version 1.0.0")
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    
                    Text("Smart email management for iOS")
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(30)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(DesignSystem.Colors.surfaceSecondary)
            )
            .padding(.horizontal, 24)
            
            Spacer()
        }
        .background(DesignSystem.Colors.surface)
    }
}

// MARK: - Preview

struct AdvancedSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        AdvancedSettingsView()
    }
}