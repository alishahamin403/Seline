import SwiftUI

struct SunMoonTracker: View {
    @StateObject private var weatherService = WeatherService.shared
    @StateObject private var locationService = LocationService.shared
    @Environment(\.colorScheme) var colorScheme

    @State private var currentTime = Date()

    // Timer to update current time (30 seconds for smoother animation)
    let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    // Computed properties for debugging
    private var currentWeather: WeatherData? {
        weatherService.weatherData
    }

    private var sunrise: Date {
        currentWeather?.sunrise ?? mockSunrise()
    }

    private var sunset: Date {
        currentWeather?.sunset ?? mockSunset()
    }

    private var isDaytime: Bool {
        currentTime >= sunrise && currentTime <= sunset
    }

    private var arcProgress: Double {
        let calendar = Calendar.current
        let now = currentTime

        // Ensure we have valid sunrise/sunset times
        guard sunrise != sunset else { return 0.0 }

        // Check if it's daytime or nighttime
        if now >= sunrise && now <= sunset {
            // Daytime - sun position (left to right across arc)
            let dayDuration = sunset.timeIntervalSince(sunrise)
            guard dayDuration > 0 else { return 0.0 }

            let timeSinceSunrise = now.timeIntervalSince(sunrise)
            return max(0.0, min(1.0, timeSinceSunrise / dayDuration))
        } else {
            // Nighttime - moon position (starts at left, moves right)
            let nightStart: Date
            let nightEnd: Date

            // Determine current night period
            let todaySunrise = calendar.dateInterval(of: .day, for: now)?.start.addingTimeInterval(
                sunrise.timeIntervalSince(calendar.dateInterval(of: .day, for: sunrise)?.start ?? sunrise)
            ) ?? sunrise

            let todaySunset = calendar.dateInterval(of: .day, for: now)?.start.addingTimeInterval(
                sunset.timeIntervalSince(calendar.dateInterval(of: .day, for: sunset)?.start ?? sunset)
            ) ?? sunset

            if now > todaySunset {
                // After sunset today, before sunrise tomorrow
                nightStart = todaySunset
                nightEnd = calendar.date(byAdding: .day, value: 1, to: todaySunrise) ?? todaySunrise
            } else {
                // After midnight, before sunrise today (early morning)
                let yesterdaySunset = calendar.date(byAdding: .day, value: -1, to: todaySunset) ?? todaySunset
                nightStart = yesterdaySunset
                nightEnd = todaySunrise
            }

            let nightDuration = nightEnd.timeIntervalSince(nightStart)
            guard nightDuration > 0 else { return 0.0 }

            let timeSinceNightStart = now.timeIntervalSince(nightStart)
            return max(0.0, min(1.0, timeSinceNightStart / nightDuration))
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(spacing: 12) {
            // The arc view with sunrise/sunset times
            HStack(alignment: .bottom, spacing: 0) {
                // Sunrise on the left
                VStack(spacing: 4) {
                    Image(systemName: "sunrise.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color(red: 1.0, green: 0.8, blue: 0.0))

                    Text(formatTime(sunrise))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.shadcnForeground(colorScheme))
                }
                .frame(width: 60)

                Spacer()

                // Arc in the center
                SunMoonArcView(
                    sunrise: sunrise,
                    sunset: sunset,
                    currentTime: currentTime,
                    colorScheme: colorScheme
                )
                .frame(height: 100)

                Spacer()

                // Sunset on the right
                VStack(spacing: 4) {
                    Image(systemName: "sunset.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Color(red: 1.0, green: 0.6, blue: 0.2))

                    Text(formatTime(sunset))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.shadcnForeground(colorScheme))
                }
                .frame(width: 60)
            }
            .padding(.horizontal, 20)
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
        .onAppear {
            // Request location permission and load weather data
            locationService.requestLocationPermission()

            // Load mock data as fallback
            if weatherService.weatherData == nil {
                weatherService.loadMockWeather()
            }
        }
        .onChange(of: locationService.currentLocation) { location in
            if let location = location {
                Task {
                    await weatherService.fetchWeather(for: location)
                }
            }
        }
    }

    private func mockSunrise() -> Date {
        let calendar = Calendar.current
        return calendar.date(bySettingHour: 6, minute: 30, second: 0, of: Date()) ?? Date()
    }

    private func mockSunset() -> Date {
        let calendar = Calendar.current
        return calendar.date(bySettingHour: 19, minute: 45, second: 0, of: Date()) ?? Date()
    }
}

struct SunMoonArcView: View {
    let sunrise: Date
    let sunset: Date
    let currentTime: Date
    let colorScheme: ColorScheme

    private var arcProgress: Double {
        let calendar = Calendar.current
        let now = currentTime

        // Ensure we have valid sunrise/sunset times
        guard sunrise != sunset else { return 0.0 }

        // Check if it's daytime or nighttime
        if now >= sunrise && now <= sunset {
            // Daytime - sun position (left to right across arc)
            let dayDuration = sunset.timeIntervalSince(sunrise)
            guard dayDuration > 0 else { return 0.0 }

            let timeSinceSunrise = now.timeIntervalSince(sunrise)
            return max(0.0, min(1.0, timeSinceSunrise / dayDuration))
        } else {
            // Nighttime - moon position (starts at left, moves right)
            let nightStart: Date
            let nightEnd: Date

            // Determine current night period
            let todaySunrise = calendar.dateInterval(of: .day, for: now)?.start.addingTimeInterval(
                sunrise.timeIntervalSince(calendar.dateInterval(of: .day, for: sunrise)?.start ?? sunrise)
            ) ?? sunrise

            let todaySunset = calendar.dateInterval(of: .day, for: now)?.start.addingTimeInterval(
                sunset.timeIntervalSince(calendar.dateInterval(of: .day, for: sunset)?.start ?? sunset)
            ) ?? sunset

            if now > todaySunset {
                // After sunset today, before sunrise tomorrow
                nightStart = todaySunset
                nightEnd = calendar.date(byAdding: .day, value: 1, to: todaySunrise) ?? todaySunrise
            } else {
                // After midnight, before sunrise today (early morning)
                let yesterdaySunset = calendar.date(byAdding: .day, value: -1, to: todaySunset) ?? todaySunset
                nightStart = yesterdaySunset
                nightEnd = todaySunrise
            }

            let nightDuration = nightEnd.timeIntervalSince(nightStart)
            guard nightDuration > 0 else { return 0.0 }

            let timeSinceNightStart = now.timeIntervalSince(nightStart)
            return max(0.0, min(1.0, timeSinceNightStart / nightDuration))
        }
    }

    private var isDaytime: Bool {
        currentTime >= sunrise && currentTime <= sunset
    }

    private var iconName: String {
        isDaytime ? "sun.max.fill" : "moon.circle.fill"
    }

    private var iconColor: Color {
        if isDaytime {
            // Sun color - golden yellow
            return Color(red: 1.0, green: 0.8, blue: 0.0)
        } else {
            // Moon color - white
            return Color.white
        }
    }

    var body: some View {
        ZStack {
            // Base half circle with glow effect
            HalfCircleOutline()
                .stroke(
                    Color.gray.opacity(colorScheme == .dark ? 0.4 : 0.2),
                    lineWidth: 1.5
                )
                .frame(width: 200, height: 100)
                .shadcnShadow()

            // Progress arc overlay
            HalfCircleOutline()
                .trim(from: 0, to: arcProgress)
                .stroke(
                    iconColor.opacity(0.4),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .frame(width: 200, height: 100)
                .animation(.easeInOut(duration: 1.0), value: arcProgress)

            // Sun/Moon icon positioned on the arc
            GeometryReader { geometry in
                let center = CGPoint(x: 100, y: 100) // Center at bottom of 200x100 frame
                let radius: CGFloat = 100 // Exactly on the arc line
                // Convert progress to angle: 0 progress = 180° (left), 1 progress = 0° (right)
                let angle = 180 - (arcProgress * 180)
                let radians = angle * .pi / 180
                let iconX = center.x + radius * cos(radians)
                let iconY = center.y - radius * sin(radians) // Subtract to position on arc line

                ZStack {
                    // Circular background to hide line behind icon - match home screen background
                    Circle()
                        .fill(colorScheme == .dark ? Color.shadcnBackground(colorScheme) : Color.white)
                        .frame(width: 30, height: 30)

                    // Icon - make moon much larger to visually match sun
                    Image(systemName: iconName)
                        .font(.system(size: isDaytime ? 20 : 24, weight: .medium))
                        .foregroundStyle(isDaytime ? iconColor : Color.white)
                        .symbolRenderingMode(.monochrome)
                }
                .position(x: iconX, y: iconY)
                .shadow(color: colorScheme == .dark ? Color.black.opacity(0.1) : iconColor.opacity(0.4), radius: 3, x: 0, y: 1)
                .animation(.easeInOut(duration: 1.0), value: arcProgress)
                .animation(.easeInOut(duration: 1.5), value: isDaytime)
            }
            .frame(width: 200, height: 100)
        }
    }

}

#Preview {
    VStack {
        SunMoonTracker()
        Spacer()
    }
    .padding()
}