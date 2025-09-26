import Foundation
import CoreLocation

// MARK: - Weather Data Models
struct WeatherData {
    let temperature: Int
    let description: String
    let iconName: String
    let sunrise: Date
    let sunset: Date
    let locationName: String
}

struct WeatherResponse: Codable {
    let main: MainWeather
    let weather: [Weather]
    let sys: WeatherSys
    let name: String
}

struct MainWeather: Codable {
    let temp: Double
}

struct Weather: Codable {
    let main: String
    let description: String
    let icon: String
}

struct WeatherSys: Codable {
    let sunrise: TimeInterval
    let sunset: TimeInterval
}

@MainActor
class WeatherService: ObservableObject {
    @Published var weatherData: WeatherData?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    static let shared = WeatherService()

    // OpenWeatherMap API - You'll need to get a free API key from openweathermap.org
    private let apiKey = "YOUR_API_KEY_HERE" // Replace with actual API key
    private let baseURL = "https://api.openweathermap.org/data/2.5/weather"

    private init() {}

    func fetchWeather(for location: CLLocation) async {
        isLoading = true
        errorMessage = nil

        do {
            let weatherData = try await performWeatherRequest(for: location)
            self.weatherData = weatherData
        } catch {
            self.errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func performWeatherRequest(for location: CLLocation) async throws -> WeatherData {
        // Build URL with coordinates
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "lat", value: "\(location.coordinate.latitude)"),
            URLQueryItem(name: "lon", value: "\(location.coordinate.longitude)"),
            URLQueryItem(name: "appid", value: apiKey),
            URLQueryItem(name: "units", value: "metric")
        ]

        guard let url = components.url else {
            throw WeatherError.invalidURL
        }

        // Perform network request
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw WeatherError.networkError
        }

        // Decode response
        let weatherResponse = try JSONDecoder().decode(WeatherResponse.self, from: data)

        // Convert to our WeatherData model
        return WeatherData(
            temperature: Int(weatherResponse.main.temp.rounded()),
            description: weatherResponse.weather.first?.description.capitalized ?? "",
            iconName: mapWeatherIcon(weatherResponse.weather.first?.icon ?? ""),
            sunrise: Date(timeIntervalSince1970: weatherResponse.sys.sunrise),
            sunset: Date(timeIntervalSince1970: weatherResponse.sys.sunset),
            locationName: weatherResponse.name
        )
    }

    // Map OpenWeatherMap icons to SF Symbols
    private func mapWeatherIcon(_ apiIcon: String) -> String {
        switch apiIcon {
        case "01d": return "sun.max.fill"           // clear sky day
        case "01n": return "moon.fill"              // clear sky night
        case "02d": return "cloud.sun.fill"         // few clouds day
        case "02n": return "cloud.moon.fill"        // few clouds night
        case "03d", "03n": return "cloud.fill"      // scattered clouds
        case "04d", "04n": return "smoke.fill"      // broken clouds
        case "09d", "09n": return "cloud.drizzle.fill" // shower rain
        case "10d": return "cloud.sun.rain.fill"    // rain day
        case "10n": return "cloud.moon.rain.fill"   // rain night
        case "11d", "11n": return "cloud.bolt.rain.fill" // thunderstorm
        case "13d", "13n": return "snow"            // snow
        case "50d", "50n": return "cloud.fog.fill"  // mist
        default: return "cloud.fill"
        }
    }

    // Mock data for development/testing
    func loadMockWeather() {
        let now = Date()
        let calendar = Calendar.current
        let sunrise = calendar.date(bySettingHour: 6, minute: 30, second: 0, of: now) ?? now
        let sunset = calendar.date(bySettingHour: 19, minute: 45, second: 0, of: now) ?? now

        weatherData = WeatherData(
            temperature: 20,
            description: "Partly Cloudy",
            iconName: "cloud.sun.fill",
            sunrise: sunrise,
            sunset: sunset,
            locationName: "Mississauga, ON"
        )
    }
}

// MARK: - Weather Errors
enum WeatherError: LocalizedError {
    case invalidURL
    case networkError
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid weather API URL"
        case .networkError:
            return "Network error occurred"
        case .decodingError:
            return "Failed to decode weather data"
        }
    }
}