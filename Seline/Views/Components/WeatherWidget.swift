import SwiftUI

struct WeatherWidget: View {
    @StateObject private var weatherService = WeatherService.shared
    @StateObject private var locationService = LocationService.shared
    @Environment(\.colorScheme) var colorScheme

    @State private var currentTime = Date()
    let timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var weatherIconColor: Color {
        colorScheme == .dark ? Color.white : Color.black
    }

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

    private var dayProgress: Double {
        let now = currentTime
        guard sunrise != sunset else { return 0.0 }

        if now >= sunrise && now <= sunset {
            // Daytime - sun position
            let dayDuration = sunset.timeIntervalSince(sunrise)
            guard dayDuration > 0 else { return 0.0 }
            let timeSinceSunrise = now.timeIntervalSince(sunrise)
            return max(0.0, min(1.0, timeSinceSunrise / dayDuration))
        } else {
            // Nighttime - moon position
            let calendar = Calendar.current
            let nightStart: Date
            let nightEnd: Date

            let todaySunrise = calendar.dateInterval(of: .day, for: now)?.start.addingTimeInterval(
                sunrise.timeIntervalSince(calendar.dateInterval(of: .day, for: sunrise)?.start ?? sunrise)
            ) ?? sunrise

            let todaySunset = calendar.dateInterval(of: .day, for: now)?.start.addingTimeInterval(
                sunset.timeIntervalSince(calendar.dateInterval(of: .day, for: sunset)?.start ?? sunset)
            ) ?? sunset

            if now > todaySunset {
                nightStart = todaySunset
                nightEnd = calendar.date(byAdding: .day, value: 1, to: todaySunrise) ?? todaySunrise
            } else {
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

    private var sunMoonIconName: String {
        isDaytime ? "sun.max.fill" : "moon.circle.fill"
    }

    private var sunMoonIconColor: Color {
        if isDaytime {
            return Color(red: 1.0, green: 0.8, blue: 0.0) // Golden sun
        } else {
            return colorScheme == .dark ? Color.white : Color.gray
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            // Center-aligned location and weather in one line
            HStack(spacing: 12) {
                // Location text - smaller and lighter
                Text(weatherService.weatherData?.locationName ?? locationService.locationName)
                    .font(.system(size: 14, weight: .regular, design: .default))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.8))

                // Weather info
                HStack(spacing: 6) {
                    Image(systemName: weatherService.weatherData?.iconName ?? "cloud.fill")
                        .font(.system(size: 12, weight: .regular, design: .default))
                        .foregroundColor(weatherIconColor)

                    Text("\(weatherService.weatherData?.temperature ?? 20)°")
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.8))
                }
            }
            .padding(.horizontal, 20)

            // Full-width horizontal progression line with sun/moon icon
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Base line - full width
                    Rectangle()
                        .fill(Color.gray.opacity(colorScheme == .dark ? 0.3 : 0.2))
                        .frame(height: 1)

                    // Progress line - full width
                    Rectangle()
                        .fill(sunMoonIconColor.opacity(0.6))
                        .frame(width: geometry.size.width * dayProgress, height: 1.5)
                        .animation(.easeInOut(duration: 1.0), value: dayProgress)

                    // Sun/Moon icon positioned along the line
                    HStack {
                        Spacer(minLength: 0)

                        ZStack {
                            // Even bigger circular background - match home screen background
                            Circle()
                                .fill(colorScheme == .dark ? Color.shadcnBackground(colorScheme) : Color.white)
                                .frame(width: 32, height: 32)

                            // Even bigger icon - make moon much larger to visually match sun
                            Image(systemName: sunMoonIconName)
                                .font(.system(size: isDaytime ? 20 : 26, weight: .medium))
                                .foregroundStyle(sunMoonIconColor)
                                .symbolRenderingMode(.monochrome)
                        }
                        .offset(x: (geometry.size.width - 32) * dayProgress - (geometry.size.width - 32) * 0.5)
                        .animation(.easeInOut(duration: 1.0), value: dayProgress)
                        .animation(.easeInOut(duration: 1.5), value: isDaytime)

                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(height: 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .onReceive(timer) { _ in
            currentTime = Date()
        }
        .onAppear {
            // Load mock data for development
            weatherService.loadMockWeather()
            locationService.requestLocationPermission()
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

#Preview {
    WeatherWidget()
}