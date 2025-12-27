import SwiftUI

enum CalendarViewMode: String, CaseIterable {
    case week = "Week"
    case month = "Month"
    case ranking = "Stats"
}

struct CalendarHeaderView: View {
    @Binding var selectedDate: Date
    @Binding var viewMode: CalendarViewMode
    @Environment(\.colorScheme) var colorScheme
    
    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: selectedDate)
    }
    
    private var displayMonthString: String {
        return monthYearString
    }
    
    private var primaryTextColor: Color {
        colorScheme == .dark ? .white : .black
    }
    
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6)
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }
    
    private var toggleBackgroundColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)
    }
    
    private var selectedToggleColor: Color {
        colorScheme == .dark ? Color.white : Color.black
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                // Month title - hide for ranking view
                if viewMode != .ranking {
                    Text(displayMonthString)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(primaryTextColor)
                } else {
                    // For ranking view, show "Stats" title
                    Text("Stats")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(primaryTextColor)
                }
                
                Spacer()
                
                // View mode toggle
                viewModeToggle
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(backgroundColor)
        }
    }
    
    // MARK: - View Mode Toggle
    
    private var viewModeToggle: some View {
        HStack(spacing: 0) {
            ForEach(CalendarViewMode.allCases, id: \.self) { mode in
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        viewMode = mode
                    }
                    HapticManager.shared.selection()
                }) {
                    Text(mode.rawValue)
                        .font(.system(size: 13, weight: viewMode == mode ? .semibold : .medium))
                        .foregroundColor(viewMode == mode ? (colorScheme == .dark ? .black : .white) : secondaryTextColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(minWidth: 65) // Increased to fit "Stats"
                        .background(
                            Capsule()
                                .fill(viewMode == mode ? selectedToggleColor : Color.clear)
                        )
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewMode)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(3)
        .background(
            Capsule()
                .fill(toggleBackgroundColor)
        )
    }
    
}

#Preview {
    VStack {
        CalendarHeaderView(
            selectedDate: .constant(Date()),
            viewMode: .constant(.month)
        )
        Spacer()
    }
}

