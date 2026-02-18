import SwiftUI
import CoreLocation

/// Weather card styled to match the top home card language
struct HomeWeatherWidget: View {
    @StateObject private var weatherService = WeatherService.shared
    @StateObject private var locationService = LocationService.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase

    var isVisible: Bool = true

    @State private var lastWeatherFetch: Date?
    @State private var isExpanded: Bool = false

    private var cardHeadingFont: Font {
        FontManager.geist(size: 20, weight: .semibold)
    }

    private var currentWeather: WeatherData? {
        weatherService.weatherData
    }

    private var highLowText: String {
        guard let hourly = currentWeather?.hourlyForecasts, !hourly.isEmpty else {
            return ""
        }

        let highs = hourly.map { $0.temperature }
        let high = highs.max() ?? 0
        let low = highs.min() ?? 0
        return "H:\(high)° L:\(low)°"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let weather = currentWeather {
                if isExpanded {
                    hoursSection(weather)
                    daysSection(weather)
                }
            } else {
                Text(weatherService.isLoading ? "Loading forecast..." : "Weather unavailable")
                    .font(FontManager.geist(size: 13, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.55) : Color.black.opacity(0.55))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: ShadcnRadius.xl)
                .fill(Color.shadcnTileBackground(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ShadcnRadius.xl)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(
            color: colorScheme == .dark ? .black.opacity(0.18) : .black.opacity(0.08),
            radius: colorScheme == .dark ? 4 : 10,
            x: 0,
            y: colorScheme == .dark ? 2 : 4
        )
        .onAppear {
            guard isVisible else { return }
            locationService.requestLocationPermission()
            if let location = locationService.currentLocation {
                refreshWeatherIfNeeded(location: location)
            }
        }
        .onChange(of: isVisible) { visible in
            guard visible else { return }
            locationService.requestLocationPermission()
            if let location = locationService.currentLocation {
                refreshWeatherIfNeeded(location: location)
            }
        }
        .onChange(of: locationService.currentLocation) { location in
            guard isVisible, let location = location else { return }
            refreshWeatherIfNeeded(location: location)
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active, isVisible, let location = locationService.currentLocation {
                refreshWeatherIfNeeded(location: location)
            }
        }
    }

    private var header: some View {
        Button(action: {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
            HapticManager.shared.selection()
        }) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Weather")
                    .font(FontManager.geist(size: 12, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.62))
                    .textCase(.uppercase)
                    .tracking(0.5)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(currentWeather?.locationName ?? locationService.locationName)
                        .font(cardHeadingFont)
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)

                    Spacer()

                    Text(currentWeather.map { "\($0.temperature)°" } ?? "--°")
                        .font(FontManager.geist(size: 26, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(FontManager.geist(size: 12, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.62))
                }

                HStack(spacing: 8) {
                    Text(currentWeather?.description.capitalized ?? "")
                        .font(FontManager.geist(size: 12, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.62))

                    if !highLowText.isEmpty {
                        Text("•")
                            .font(FontManager.geist(size: 12, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))

                        Text(highLowText)
                            .font(FontManager.geist(size: 12, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.62))
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .allowsParentScrolling()
    }

    private func hoursSection(_ weather: WeatherData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Next Hours")
                .font(FontManager.geist(size: 12, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.62))
                .textCase(.uppercase)
                .tracking(0.5)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(weather.hourlyForecasts.prefix(6).enumerated()), id: \.offset) { _, hour in
                        VStack(spacing: 2) {
                            Text(hour.hour)
                                .font(FontManager.geist(size: 11, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.56) : Color.black.opacity(0.56))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            Text("\(hour.temperature)°")
                                .font(FontManager.geist(size: 13, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                        .frame(width: 60, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.04))
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)
            .allowsParentScrolling()
        }
    }

    private func daysSection(_ weather: WeatherData) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Next Days")
                .font(FontManager.geist(size: 12, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.62))
                .textCase(.uppercase)
                .tracking(0.5)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(weather.dailyForecasts.prefix(6).enumerated()), id: \.offset) { _, day in
                        VStack(spacing: 2) {
                            Text(day.day)
                                .font(FontManager.geist(size: 11, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.56) : Color.black.opacity(0.56))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            Text("\(day.temperature)°")
                                .font(FontManager.geist(size: 13, weight: .semibold))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                        }
                        .frame(width: 60, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.04))
                        )
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)
            .allowsParentScrolling()
        }
    }

    private func refreshWeatherIfNeeded(location: CLLocation) {
        if let lastFetch = lastWeatherFetch,
           Date().timeIntervalSince(lastFetch) < 1800 {
            return
        }

        Task {
            await weatherService.fetchWeather(for: location)
            lastWeatherFetch = Date()
        }
    }
}

#Preview {
    VStack {
        HomeWeatherWidget()
            .padding(.horizontal, 12)
        Spacer()
    }
    .background(Color.shadcnBackground(.dark))
}
