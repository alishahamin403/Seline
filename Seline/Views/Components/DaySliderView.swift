import SwiftUI

struct DaySliderView: View {
    @Binding var selectedDate: Date
    @Environment(\.colorScheme) var colorScheme

    // Generate array of dates (7 days before and 7 days after today)
    private var dateRange: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        return (-7...14).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today)
        }
    }

    private func dayName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE" // Mon, Tue, etc.
        return formatter.string(from: date).uppercased()
    }

    private func dayNumber(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: Date())
    }

    private func isSelected(_ date: Date) -> Bool {
        Calendar.current.isDate(date, inSameDayAs: selectedDate)
    }

    private var accentColor: Color {
        Color(red: 0.2, green: 0.2, blue: 0.2)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(dateRange, id: \.self) { date in
                        dayButton(for: date)
                            .id(date)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }
            .onAppear {
                // Auto-scroll to selected date
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation {
                        proxy.scrollTo(selectedDate, anchor: .center)
                    }
                }
            }
            .onChange(of: selectedDate) { newDate in
                withAnimation {
                    proxy.scrollTo(newDate, anchor: .center)
                }
            }
        }
        .background(
            colorScheme == .dark ?
                Color.black : Color.white
        )
    }

    private func dayButton(for date: Date) -> some View {
        Button(action: {
            HapticManager.shared.selection()
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedDate = date
            }
        }) {
            VStack(spacing: 2) {
                Text(dayName(date))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(
                        isSelected(date) ? Color.white :
                        isToday(date) ? accentColor :
                        (colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                    )

                Text(dayNumber(date))
                    .font(.system(size: 15, weight: isSelected(date) ? .semibold : .regular))
                    .foregroundColor(
                        isSelected(date) ? Color.white :
                        isToday(date) ? accentColor :
                        (colorScheme == .dark ? Color.white : Color.black)
                    )
            }
            .frame(width: 50, height: 48)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected(date) ? accentColor : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isToday(date) && !isSelected(date) ? accentColor.opacity(0.5) : Color.clear,
                        lineWidth: 2
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    VStack {
        DaySliderView(selectedDate: .constant(Date()))
            .background(Color.shadcnBackground(.light))
    }
}
