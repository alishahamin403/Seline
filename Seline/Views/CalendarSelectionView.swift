import SwiftUI
import EventKit
import UIKit

/// View for selecting which iPhone calendars to sync with Seline
struct CalendarSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var calendars: [CalendarMetadata] = []
    @State private var preferences: CalendarSyncPreferences = CalendarSyncPreferences.load()
    @State private var isLoading = true
    @State private var hasChanges = false

    private var groupedCalendars: [(CalendarSourceType, [CalendarMetadata])] {
        let grouped = Dictionary(grouping: calendars) { $0.sourceType }
        return grouped.sorted { $0.key.displayName < $1.key.displayName }
            .map { ($0.key, $0.value.sorted { $0.title < $1.title }) }
    }

    private var selectedCount: Int {
        calendars.filter { preferences.isSelected(calendarId: $0.id) }.count
    }

    private var selectionSummaryText: String {
        "\(selectedCount) of \(calendars.count) calendar\(calendars.count == 1 ? "" : "s") selected"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppAmbientBackgroundLayer(colorScheme: colorScheme, variant: .topTrailing)

                content
            }
            .navigationTitle("Calendar Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(FontManager.geist(size: 14, weight: .medium))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(hasChanges ? "Save" : "Done") {
                        saveAndDismiss()
                    }
                    .font(FontManager.geist(size: 14, weight: .semibold))
                }
            }
        }
        .task {
            await loadCalendars()
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            loadingStateView
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 14) {
                    introCard

                    if calendars.isEmpty {
                        emptyStateCard
                    } else {
                        selectionSummaryCard

                        ForEach(groupedCalendars, id: \.0) { sourceType, calendarsInGroup in
                            calendarSection(for: sourceType, calendarsInGroup: calendarsInGroup)
                        }
                    }

                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
    }

    private var loadingStateView: some View {
        VStack {
            VStack(spacing: 14) {
                ProgressView()
                    .tint(Color.homeGlassAccent)
                    .scaleEffect(1.05)

                Text("Loading your calendars")
                    .font(FontManager.geist(size: 16, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary(colorScheme))

                Text("Seline is checking which sources are available on this device.")
                    .font(FontManager.geist(size: 13, weight: .regular))
                    .foregroundColor(Color.appTextSecondary(colorScheme))
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 26)
            .appAmbientCardStyle(
                colorScheme: colorScheme,
                variant: .centerRight,
                cornerRadius: 28,
                highlightStrength: 0.66
            )
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CALENDAR SYNC")
                .font(FontManager.geist(size: 11, weight: .semibold))
                .foregroundColor(Color.appTextSecondary(colorScheme))
                .tracking(0.8)

            Text("Choose the calendars Seline should keep in sync.")
                .font(FontManager.geist(size: 22, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))

            Text("Selected calendars appear in your timeline and planning surfaces, while the rest stay out of your way.")
                .font(FontManager.geist(size: 13, weight: .regular))
                .foregroundColor(Color.appTextSecondary(colorScheme))
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .appAmbientCardStyle(
            colorScheme: colorScheme,
            variant: .topTrailing,
            cornerRadius: 28,
            highlightStrength: 0.72
        )
    }

    private func loadCalendars() async {
        isLoading = true
        defer { isLoading = false }

        calendars = await CalendarSyncService.shared.fetchAvailableCalendars()
    }

    private var selectionSummaryCard: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(selectionSummaryText)
                    .font(FontManager.geist(size: 15, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary(colorScheme))

                Text(selectedCount == 0
                    ? "Nothing is selected yet."
                    : "You can turn everything on, then trim it down.")
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(Color.appTextSecondary(colorScheme))
            }

            Spacer(minLength: 12)

            Button(selectedCount == calendars.count ? "Deselect All" : "Select All") {
                if selectedCount == calendars.count {
                    preferences.deselectAll()
                } else {
                    preferences.selectAll(calendarIds: calendars.map { $0.id })
                }
                hasChanges = true
            }
            .font(FontManager.geist(size: 12, weight: .semibold))
            .foregroundColor(Color.appTextPrimary(colorScheme))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .appAmbientInnerSurfaceStyle(colorScheme: colorScheme, cornerRadius: 16)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .appAmbientCardStyle(
            colorScheme: colorScheme,
            variant: .centerRight,
            cornerRadius: 24,
            highlightStrength: 0.58
        )
    }

    private func calendarSection(
        for sourceType: CalendarSourceType,
        calendarsInGroup: [CalendarMetadata]
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: sourceType.iconName)
                    .font(FontManager.geist(size: 14, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary(colorScheme))
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(Color.appChip(colorScheme))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(sourceType.displayName.uppercased())
                        .font(FontManager.geist(size: 11, weight: .semibold))
                        .foregroundColor(Color.appTextSecondary(colorScheme))
                        .tracking(0.8)

                    Text("\(calendarsInGroup.count) calendar\(calendarsInGroup.count == 1 ? "" : "s")")
                        .font(FontManager.geist(size: 13, weight: .medium))
                        .foregroundColor(Color.appTextPrimary(colorScheme))
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 8)

            ForEach(Array(calendarsInGroup.enumerated()), id: \.element.id) { index, calendar in
                CalendarRow(
                    calendar: calendar,
                    isSelected: preferences.isSelected(calendarId: calendar.id),
                    colorScheme: colorScheme
                ) { isSelected in
                    if isSelected {
                        preferences.select(calendarId: calendar.id)
                    } else {
                        preferences.deselect(calendarId: calendar.id)
                    }
                    hasChanges = true
                }

                if index < calendarsInGroup.count - 1 {
                    Divider()
                        .padding(.leading, 58)
                }
            }
        }
        .appAmbientCardStyle(
            colorScheme: colorScheme,
            variant: .topLeading,
            cornerRadius: 24,
            highlightStrength: 0.54
        )
    }

    private var emptyStateCard: some View {
        VStack(spacing: 18) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(FontManager.geist(size: 38, weight: .regular))
                .foregroundColor(Color.appTextSecondary(colorScheme))

            VStack(spacing: 8) {
                Text("No calendars available")
                    .font(FontManager.geist(size: 18, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary(colorScheme))

                Text("Seline could not find any calendars on this device. Check Calendar access in Settings, then come back and try again.")
                    .font(FontManager.geist(size: 13, weight: .regular))
                    .foregroundColor(Color.appTextSecondary(colorScheme))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }

            Button("Open Settings") {
                openAppSettings()
            }
            .font(FontManager.geist(size: 13, weight: .semibold))
            .foregroundColor(colorScheme == .dark ? .black : .white)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(Color.homeGlassAccent)
            )
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 26)
        .appAmbientCardStyle(
            colorScheme: colorScheme,
            variant: .bottomLeading,
            cornerRadius: 28,
            highlightStrength: 0.62
        )
    }

    private func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }

        UIApplication.shared.open(settingsURL)
    }

    private func saveAndDismiss() {
        if hasChanges {
            preferences.save()
            print("✅ Saved calendar selection: \(preferences.selectedCalendarIds.count) calendars")

            NotificationCenter.default.post(name: .calendarSelectionChanged, object: nil)
        }

        dismiss()
    }
}

// MARK: - Calendar Row

struct CalendarRow: View {
    let calendar: CalendarMetadata
    let isSelected: Bool
    let colorScheme: ColorScheme
    let onToggle: (Bool) -> Void

    var body: some View {
        Button {
            onToggle(!isSelected)
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(hexToColor(calendar.color))
                    .frame(width: 12, height: 12)

                VStack(alignment: .leading, spacing: 4) {
                    Text(calendar.title)
                        .font(FontManager.geist(size: 15, weight: .medium))
                        .foregroundColor(Color.appTextPrimary(colorScheme))

                    HStack(spacing: 6) {
                        Text(calendar.sourceTitle)
                            .font(FontManager.geist(size: 12, weight: .regular))
                            .foregroundColor(Color.appTextSecondary(colorScheme))

                        if !calendar.allowsContentModifications {
                            Text("Read-only")
                                .font(FontManager.geist(size: 11, weight: .medium))
                                .foregroundColor(Color.appTextSecondary(colorScheme))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color.appChip(colorScheme))
                                )
                        }
                    }
                }

                Spacer(minLength: 12)

                if isSelected {
                    ZStack {
                        Circle()
                            .fill(Color.homeGlassAccent)
                            .frame(width: 28, height: 28)

                        Image(systemName: "checkmark")
                            .font(FontManager.geist(size: 12, weight: .semibold))
                            .foregroundColor(.black)
                    }
                } else {
                    Circle()
                        .fill(Color.appInnerSurface(colorScheme))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Circle()
                                .stroke(Color.appBorder(colorScheme), lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func hexToColor(_ hex: String) -> Color {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return .gray
        }

        return Color(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let calendarSelectionChanged = Notification.Name("calendarSelectionChanged")
}

// MARK: - Preview

#Preview {
    CalendarSelectionView()
}
