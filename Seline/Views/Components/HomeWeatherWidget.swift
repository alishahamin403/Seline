import SwiftUI
import CoreLocation

/// A minimalistic weather widget for the home screen
struct HomeWeatherWidget: View {
    @StateObject private var weatherService = WeatherService.shared
    @StateObject private var locationService = LocationService.shared
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.scenePhase) var scenePhase
    
    var isVisible: Bool = true
    
    @State private var lastWeatherFetch: Date?
    
    private var currentWeather: WeatherData? {
        weatherService.weatherData
    }
    
    private var weatherConditionIcon: String {
        let description = weatherService.weatherData?.description.lowercased() ?? ""
        let now = Date()
        
        // Check if it's day or night
        var isDaytime = true
        if let weather = currentWeather {
            isDaytime = now >= weather.sunrise && now < weather.sunset
        }
        
        if description.contains("rain") || description.contains("drizzle") {
            return "cloud.rain.fill"
        } else if description.contains("snow") {
            return "cloud.snow.fill"
        } else if description.contains("cloud") || description.contains("overcast") {
            return "cloud.fill"
        } else if description.contains("clear") {
            // Show moon at night, sun during day for clear conditions
            return isDaytime ? "sun.max.fill" : "moon.fill"
        } else if description.contains("sun") {
            return "sun.max.fill"
        } else if description.contains("thunder") || description.contains("storm") {
            return "cloud.bolt.fill"
        } else if description.contains("fog") || description.contains("mist") {
            return "cloud.fog.fill"
        } else if description.contains("partly") {
            return isDaytime ? "cloud.sun.fill" : "cloud.moon.fill"
        } else {
            return isDaytime ? "sun.max.fill" : "moon.fill"
        }
    }
    
    private var weatherIconColor: Color {
        let icon = weatherConditionIcon
        switch icon {
        case "sun.max.fill":
            return Color(red: 1.0, green: 0.8, blue: 0.0)
        case "moon.fill", "moon.stars.fill":
            return Color(red: 0.7, green: 0.75, blue: 0.9)
        case "cloud.sun.fill":
            return Color(red: 0.95, green: 0.75, blue: 0.3)
        case "cloud.moon.fill":
            return Color(red: 0.6, green: 0.65, blue: 0.8)
        case "cloud.rain.fill", "cloud.drizzle.fill":
            return Color(red: 0.4, green: 0.6, blue: 0.9)
        case "cloud.snow.fill":
            return Color(red: 0.7, green: 0.85, blue: 1.0)
        case "cloud.bolt.fill":
            return Color(red: 0.6, green: 0.5, blue: 0.8)
        default:
            return colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.6)
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
                // Header row
                HStack(spacing: 8) {
                    Image(systemName: weatherConditionIcon)
                        .font(FontManager.geist(size: 20, weight: .medium))
                        .foregroundColor(weatherIconColor)
                    
                    // Location and condition on same line
                    HStack(alignment: .bottom, spacing: 6) {
                        Text(currentWeather?.locationName ?? locationService.locationName)
                            .font(FontManager.geist(size: 15, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .lineLimit(1)
                        
                        // Condition text removed as requested
                    }
                    
                    Spacer()
                    
                    // Temperature
                    if let temperature = currentWeather?.temperature {
                        Text("\(temperature)°")
                            .font(FontManager.geist(size: 28, weight: .light))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                    } else {
                        Text("--°")
                            .font(FontManager.geist(size: 28, weight: .light))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                    }
                }
                
                // Sunrise/Sunset row - moved above hourly forecast
                if let weather = currentWeather {
                    HStack(spacing: 16) {
                        // Sunrise
                        HStack(spacing: 6) {
                            Image(systemName: "sunrise.fill")
                                .font(FontManager.geist(size: 12, weight: .medium))
                                .foregroundColor(Color(red: 1.0, green: 0.75, blue: 0.2))
                            
                            Text(formatTime(weather.sunrise))
                                .font(FontManager.geist(size: 11, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        }
                        
                        // Sunset
                        HStack(spacing: 6) {
                            Image(systemName: "sunset.fill")
                                .font(FontManager.geist(size: 12, weight: .medium))
                                .foregroundColor(Color(red: 1.0, green: 0.5, blue: 0.2))
                            
                            Text(formatTime(weather.sunset))
                                .font(FontManager.geist(size: 11, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                        }
                        
                        Spacer()
                    }
                }
                
                // 6-hour forecast (aligned with daily)
                if let hourlyForecasts = currentWeather?.hourlyForecasts, !hourlyForecasts.isEmpty {
                    HStack(spacing: 0) {
                        ForEach(hourlyForecasts.prefix(6).indices, id: \.self) { index in
                            let forecast = hourlyForecasts[index]
                            VStack(spacing: 4) {
                                Text(forecast.hour)
                                    .font(FontManager.geist(size: 10, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.6))
                                
                                Image(systemName: forecast.iconName)
                                    .font(FontManager.geist(size: 14, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                                
                                Text("\(forecast.temperature)°")
                                    .font(FontManager.geist(size: 12, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? .white : .black)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                // 6-day forecast
                if let forecasts = currentWeather?.dailyForecasts, !forecasts.isEmpty {
                    HStack(spacing: 0) {
                        ForEach(forecasts.prefix(6), id: \.day) { forecast in
                            VStack(spacing: 4) {
                                Text(forecast.day)
                                    .font(FontManager.geist(size: 10, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                                
                                Image(systemName: forecast.iconName)
                                    .font(FontManager.geist(size: 14, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7))
                                
                                Text("\(forecast.temperature)°")
                                    .font(FontManager.geist(size: 12, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.8))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.top, 4)
                }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .shadcnTileStyle(colorScheme: colorScheme)
        .onAppear {
            guard isVisible else { return }
            
            locationService.requestLocationPermission()
            
            if let location = locationService.currentLocation {
                refreshWeatherIfNeeded(location: location)
            }
        }
        .onChange(of: isVisible) { visible in
            if visible {
                locationService.requestLocationPermission()
                
                if let location = locationService.currentLocation {
                    refreshWeatherIfNeeded(location: location)
                }
            }
        }
        .onChange(of: locationService.currentLocation) { location in
            guard isVisible, let location = location else { return }
            refreshWeatherIfNeeded(location: location)
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active, isVisible {
                if let location = locationService.currentLocation {
                    refreshWeatherIfNeeded(location: location)
                }
            }
        }
    }
    
    private func refreshWeatherIfNeeded(location: CLLocation) {
        // Only fetch if we haven't fetched in the last 30 minutes
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

