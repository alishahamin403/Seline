import SwiftUI

struct SunMoonTimeTracker: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var currentTime = Date()

    // Timer to update current time every minute
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Base half circle with glow effect
            HalfCircleOutline()
                .stroke(strokeColor, lineWidth: 0.5)
                .frame(width: 180, height: 90)
                .shadcnShadow()

            // Sun/Moon icon positioned on the arc
            GeometryReader { geometry in
                let center = CGPoint(x: 90, y: 90) // Center point at bottom of half circle
                let radius: CGFloat = 90 // Position exactly on the arc line

                // Calculate angle based on time progress
                let angle = 180 - (timeProgress * 180) // 0 progress = 180° (left), 1 progress = 0° (right)
                let radians = angle * .pi / 180
                let iconX = center.x + radius * cos(radians)
                let iconY = center.y - radius * sin(radians) // Subtract to position on arc line

                // Sun/Moon icon with background to hide line
                ZStack {
                    // Circular background to hide line behind icon
                    Circle()
                        .fill(colorScheme == .dark ? Color.gmailDarkBackground : Color.white)
                        .frame(width: 32, height: 32)

                    // Icon
                    Image(systemName: iconName)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(iconColor)
                }
                .position(x: iconX, y: iconY)
                .animation(.easeInOut(duration: 0.5), value: timeProgress)


            }
            .frame(width: 180, height: 90)
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }

    // MARK: - Computed Properties

    private var strokeColor: Color {
        colorScheme == .dark ? Color.white : Color.gray
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
            // White moon in dark mode, gray in light mode
            return colorScheme == .dark ? Color.white : Color.gray
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