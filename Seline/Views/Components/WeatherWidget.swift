import SwiftUI

struct WeatherWidget: View {
    @StateObject private var weatherService = WeatherService.shared
    @StateObject private var locationService = LocationService.shared
    @Environment(\.colorScheme) var colorScheme

    private var selectedColor: Color {
        if colorScheme == .dark {
            // Light blue for dark mode - #84cae9
            return Color(red: 0.518, green: 0.792, blue: 0.914)
        } else {
            // Dark blue for light mode - #345766
            return Color(red: 0.20, green: 0.34, blue: 0.40)
        }
    }

    var body: some View {
        // Center-aligned location and weather in one line
        HStack(spacing: 12) {
            // Location text
            Text(weatherService.weatherData?.locationName ?? locationService.locationName)
                .font(.system(size: 16, weight: .regular, design: .default))
                .foregroundColor(colorScheme == .dark ? .white : .gray)

            // Weather info
            HStack(spacing: 6) {
                Image(systemName: weatherService.weatherData?.iconName ?? "cloud.fill")
                    .font(.system(size: 14, weight: .regular, design: .default))
                    .foregroundColor(selectedColor)

                Text("\(weatherService.weatherData?.temperature ?? 20)°")
                    .font(.system(size: 16, weight: .regular, design: .default))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
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