import Foundation
import CoreLocation

// MARK: - Weather Data Models
struct DailyForecast {
    let day: String
    let temperature: Int
    let iconName: String
}

struct HourlyForecast {
    let hour: String  // e.g., "3 PM"
    let temperature: Int
    let iconName: String
}

struct WeatherData {
    let temperature: Int
    let feelsLike: Int
    let description: String
    let iconName: String
    let sunrise: Date
    let sunset: Date
    let locationName: String
    let dailyForecasts: [DailyForecast]
    let hourlyForecasts: [HourlyForecast]
}

// Open-Meteo API Response Models
struct OpenMeteoResponse: Codable {
    let latitude: Double
    let longitude: Double
    let timezone: String
    let current: CurrentWeather
    let hourly: HourlyWeather
    let daily: DailyWeather
}

struct CurrentWeather: Codable {
    let time: String
    let temperature_2m: Double
    let apparent_temperature: Double
    let weather_code: Int
}

struct HourlyWeather: Codable {
    let time: [String]
    let temperature_2m: [Double]
    let weather_code: [Int]
}

struct DailyWeather: Codable {
    let time: [String]
    let temperature_2m_mean: [Double]
    let weather_code: [Int]
    let sunrise: [String]
    let sunset: [String]
}

@MainActor
class WeatherService: ObservableObject {
    @Published var weatherData: WeatherData?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    static let shared = WeatherService()

    // Open-Meteo API (free, no API key required)
    private let baseURL = "https://api.open-meteo.com/v1/forecast"

    private init() {}

    func fetchWeather(for location: CLLocation) async {
        isLoading = true
        errorMessage = nil

        do {
            let weatherData = try await performWeatherRequest(for: location)
            self.weatherData = weatherData
        } catch {
            self.errorMessage = error.localizedDescription
            print("❌ Weather fetch error: \(error.localizedDescription)")
            if let weatherError = error as? WeatherError {
                print("💡 Error type: \(weatherError)")
            }
        }

        isLoading = false
    }

    private func performWeatherRequest(for location: CLLocation) async throws -> WeatherData {
        // Build URL for Open-Meteo API
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: "\(location.coordinate.latitude)"),
            URLQueryItem(name: "longitude", value: "\(location.coordinate.longitude)"),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily", value: "temperature_2m_mean,weather_code,sunrise,sunset"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "7")
        ]

        guard let url = components.url else {
            throw WeatherError.invalidURL
        }

        // Perform network request
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WeatherError.networkError
        }

        if httpResponse.statusCode != 200 {
            if let errorString = String(data: data, encoding: .utf8) {
                print("❌ Open-Meteo API error response: \(errorString)")
            }
            throw WeatherError.networkError
        }

        // Decode response
        let decoder = JSONDecoder()
        let meteoResponse = try decoder.decode(OpenMeteoResponse.self, from: data)

        // Generate next 6 days of forecast
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEE"  // Short day name (Mon, Tue, etc.)

        var dailyForecasts: [DailyForecast] = []

        // Start from day 1 (tomorrow) and show next 6 days
        for i in 1...6 {
            if i < meteoResponse.daily.time.count {
                let dateString = meteoResponse.daily.time[i]

                // Parse date from "YYYY-MM-DD" format
                let dateFormatter2 = DateFormatter()
                dateFormatter2.dateFormat = "yyyy-MM-dd"
                if let date = dateFormatter2.date(from: dateString) {
                    let dayName = dateFormatter.string(from: date)
                    let avgTemp = Int(meteoResponse.daily.temperature_2m_mean[i].rounded())
                    let weatherCode = meteoResponse.daily.weather_code[i]
                    let icon = mapWeatherCodeToIcon(weatherCode)

                    dailyForecasts.append(DailyForecast(day: dayName, temperature: avgTemp, iconName: icon))
                }
            }
        }

        // Parse sunrise and sunset
        // Open-Meteo returns format: "2025-10-05T07:21"
        let sunDateFormatter = DateFormatter()
        sunDateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        sunDateFormatter.timeZone = TimeZone.current // Use local timezone

        let sunrise = sunDateFormatter.date(from: meteoResponse.daily.sunrise[0]) ?? Date()
        let sunset = sunDateFormatter.date(from: meteoResponse.daily.sunset[0]) ?? Date()

        // Get location name via reverse geocoding
        let geocoder = CLGeocoder()
        var locationName = "Unknown"
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let placemark = placemarks.first {
                locationName = placemark.locality ?? placemark.name ?? "Unknown"
            }
        } catch {
            print("⚠️ Geocoding failed: \(error.localizedDescription)")
        }

        // Generate next 12 hours of hourly forecast
        let hourFormatter = DateFormatter()
        hourFormatter.dateFormat = "h a"  // e.g., "3 PM"
        
        let hourDateFormatter = DateFormatter()
        hourDateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        
        var hourlyForecasts: [HourlyForecast] = []
        let currentDate = Date()
        
        // Find current hour index
        var currentHourIndex = 0
        for (index, timeString) in meteoResponse.hourly.time.enumerated() {
            if let hourDate = hourDateFormatter.date(from: timeString),
               hourDate >= currentDate {
                currentHourIndex = index
                break
            }
        }
        
        // Get next 12 hours
        for i in currentHourIndex..<min(currentHourIndex + 12, meteoResponse.hourly.time.count) {
            let timeString = meteoResponse.hourly.time[i]
            if let hourDate = hourDateFormatter.date(from: timeString) {
                let hourLabel = hourFormatter.string(from: hourDate)
                let temp = Int(meteoResponse.hourly.temperature_2m[i].rounded())
                let weatherCode = meteoResponse.hourly.weather_code[i]
                let icon = mapWeatherCodeToIcon(weatherCode)
                
                hourlyForecasts.append(HourlyForecast(hour: hourLabel, temperature: temp, iconName: icon))
            }
        }

        // Convert to our WeatherData model
        return WeatherData(
            temperature: Int(meteoResponse.current.temperature_2m.rounded()),
            feelsLike: Int(meteoResponse.current.apparent_temperature.rounded()),
            description: weatherCodeToDescription(meteoResponse.current.weather_code),
            iconName: mapWeatherCodeToIcon(meteoResponse.current.weather_code),
            sunrise: sunrise,
            sunset: sunset,
            locationName: locationName,
            dailyForecasts: dailyForecasts,
            hourlyForecasts: hourlyForecasts
        )
    }

    // Map Open-Meteo weather codes to SF Symbols
    // Weather codes: https://open-meteo.com/en/docs
    private func mapWeatherCodeToIcon(_ code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"                    // Clear sky
        case 1, 2, 3: return "cloud.sun.fill"            // Mainly clear, partly cloudy, overcast
        case 45, 48: return "cloud.fog.fill"             // Fog
        case 51, 53, 55: return "cloud.drizzle.fill"     // Drizzle
        case 56, 57: return "cloud.sleet.fill"           // Freezing drizzle
        case 61, 63, 65: return "cloud.rain.fill"        // Rain
        case 66, 67: return "cloud.sleet.fill"           // Freezing rain
        case 71, 73, 75: return "cloud.snow.fill"        // Snow fall
        case 77: return "cloud.snow.fill"                // Snow grains
        case 80, 81, 82: return "cloud.heavyrain.fill"   // Rain showers
        case 85, 86: return "cloud.snow.fill"            // Snow showers
        case 95: return "cloud.bolt.rain.fill"           // Thunderstorm
        case 96, 99: return "cloud.bolt.rain.fill"       // Thunderstorm with hail
        default: return "cloud.fill"
        }
    }

    // Convert weather code to description
    private func weatherCodeToDescription(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mainly Clear"
        case 2: return "Partly Cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Foggy"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing Drizzle"
        case 61: return "Light Rain"
        case 63: return "Moderate Rain"
        case 65: return "Heavy Rain"
        case 66, 67: return "Freezing Rain"
        case 71, 73, 75: return "Snow"
        case 77: return "Snow Grains"
        case 80, 81, 82: return "Rain Showers"
        case 85, 86: return "Snow Showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm with Hail"
        default: return "Unknown"
        }
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
