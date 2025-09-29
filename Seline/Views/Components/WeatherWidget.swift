import SwiftUI

struct WeatherWidget: View {
    @StateObject private var weatherService = WeatherService.shared
    @StateObject private var locationService = LocationService.shared
    @Environment(\.colorScheme) var colorScheme

    private var weatherIconColor: Color {
        colorScheme == .dark ? Color.white : Color.black
    }

    var body: some View {
        // Center-aligned location and weather in one line
        HStack(spacing: 12) {
            // Location text - smaller and lighter
            Text(weatherService.weatherData?.locationName ?? locationService.locationName)
                .font(.system(size: 14, weight: .regular, design: .default))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.gray.opacity(0.8))

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
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
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
}

#Preview {
    WeatherWidget()
}