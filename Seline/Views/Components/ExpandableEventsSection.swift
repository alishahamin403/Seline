import SwiftUI

struct ExpandableEventsSection: View {
    let events: [CalendarEvent]
    @Binding var isExpanded: Bool
    let onAddEvent: () -> Void
    let onAddEventWithVoice: () -> Void
    let onViewAll: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
            
            if events.isEmpty {
                emptyStateView
            } else {
                eventsPreviewList
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(DesignSystem.Colors.surface)
                .shadow(
                    color: colorScheme == .light ? Color.black.opacity(0.06) : Color.clear,
                    radius: 8,
                    x: 0,
                    y: 4
                )
        )
        .onTapGesture {
            onViewAll()
        }
    }

    private var headerView: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            IconInBoxView(systemName: "calendar")
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Today's Events")
                    .font(DesignSystem.Typography.subheadline)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Text("\(events.count) event\(events.count == 1 ? "" : "s")")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
            
            Spacer()
            
            Button(action: onAddEventWithVoice) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
            }
            .padding(.trailing, 8)

            Button(action: onAddEvent) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
            }
            .padding(.trailing, 8)

        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(DesignSystem.Colors.textSecondary.opacity(0.5))
            
            Text("No events for today")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .frame(height: 80)
        .frame(maxWidth: .infinity)
    }

    private var eventsPreviewList: some View {
        VStack(spacing: 0) {
            ForEach(events) { event in
                EventPreviewRow(event: event)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}

struct ExpandableEventsSection_Previews: PreviewProvider {
    static var previews: some View {
        ExpandableEventsSection(
            events: [],
            isExpanded: .constant(true),
            onAddEvent: {},
            onAddEventWithVoice: {},
            onViewAll: {}
        )
    }
}