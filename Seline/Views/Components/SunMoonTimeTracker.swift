import SwiftUI

struct SunMoonTimeTracker: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var currentTime = Date()

    // Timer to update current time every minute
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Base straight line - spans width minus space for settings icon
                StraightLine()
                    .stroke(strokeColor, lineWidth: 2.0)
                    .frame(width: geometry.size.width - 40, height: 50) // Reserve 40 points for settings icon

                // Sun/Moon icon positioned on the line
                let lineY: CGFloat = 25 // Middle of the frame (height 50 / 2)
                let lineStartX: CGFloat = 16 // Small padding from edge
                let lineEndX: CGFloat = geometry.size.width - 16 // Small padding from edge

                // Calculate X position based on time progress (0 = left, 1 = right)
                // Reserve space for the settings icon by ending the line earlier
                let actualLineEndX = lineEndX - 40 // Reserve 40 points for settings icon
                let iconX = lineStartX + (timeProgress * (actualLineEndX - lineStartX))

                // Sun/Moon icon with background to hide line
                ZStack {
                    // Circular background - white for moon, match home background for sun
                    Circle()
                        .fill(isDaytime ?
                            (colorScheme == .dark ? Color.gmailDarkBackground : Color.white) :
                            Color.white
                        )
                        .frame(width: isDaytime ? 36 : 22, height: isDaytime ? 36 : 22)

                    // Icon - make moon smaller than sun but not too small
                    Image(systemName: iconName)
                        .font(.system(size: isDaytime ? 18 : 16, weight: .medium))
                        .foregroundColor(iconColor)
                }
                .position(x: iconX, y: lineY)
                .animation(.easeInOut(duration: 0.5), value: timeProgress)
            }
        }
        .frame(height: 50)
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }

    // MARK: - Computed Properties

    private var strokeColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.3) : Color.black.opacity(0.2)
    }

    private var isDaytime: Bool {
        let hour = Calendar.current.component(.hour, from: currentTime)
        return hour >= 6 && hour < 19 // 6 AM to 6:59 PM
    }

    private var iconName: String {
        isDaytime ? "sun.max.fill" : "moon.fill"
    }

    private var iconColor: Color {
        if isDaytime {
            // Golden yellow sun
            return Color(red: 1.0, green: 0.8, blue: 0.0)
        } else {
            // Moon color matches home page background
            return colorScheme == .dark ? Color.gmailDarkBackground : Color.white
        }
    }

    private var timeProgress: Double {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: currentTime)
        let minute = calendar.component(.minute, from: currentTime)
        let totalMinutes = hour * 60 + minute

        if isDaytime {
            // Day: 6:00 AM (360 min) to 7:00 PM (1140 min) = 780 minutes total
            let dayStart = 6 * 60 // 6 AM in minutes
            let dayEnd = 19 * 60 // 7 PM in minutes
            let dayDuration = dayEnd - dayStart // 780 minutes

            let minutesSinceDayStart = totalMinutes - dayStart
            return max(0.0, min(1.0, Double(minutesSinceDayStart) / Double(dayDuration)))
        } else {
            // Night: 7:01 PM to 5:59 AM
            let nightStart = 19 * 60 + 1 // 7:01 PM = 1141 minutes

            var minutesSinceNightStart: Int

            if hour >= 19 || (hour == 19 && minute >= 1) {
                // Evening (7:01 PM - 11:59 PM)
                minutesSinceNightStart = totalMinutes - nightStart
            } else {
                // Early morning (12:00 AM - 5:59 AM)
                let minutesFromNightStartToMidnight = (24 * 60) - nightStart // Minutes from 7:01 PM to midnight
                minutesSinceNightStart = minutesFromNightStartToMidnight + totalMinutes
            }

            // Total night duration: 7:01 PM to 5:59 AM = 10 hours 58 minutes = 658 minutes
            let nightDuration = 658
            return max(0.0, min(1.0, Double(minutesSinceNightStart) / Double(nightDuration)))
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        Text("Sun/Moon Time Tracker")
            .font(.title2)

        SunMoonTimeTracker()
    }
    .padding()
}