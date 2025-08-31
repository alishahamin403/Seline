//
//  NetworkManager.swift
//  Seline
//
//  Created by Claude on 2025-08-25.
//

import Foundation
import Network

/// Centralized network management for the app
class NetworkManager: ObservableObject {
    static let shared = NetworkManager()
    
    // MARK: - Properties
    
    @Published var isConnected: Bool = true
    @Published var connectionType: ConnectionType = .unknown
    
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "NetworkMonitor")
    
    // MARK: - Connection Types
    
    enum ConnectionType {
        case wifi
        case cellular
        case ethernet
        case unknown
        
        var description: String {
            switch self {
            case .wifi: return "WiFi"
            case .cellular: return "Cellular"
            case .ethernet: return "Ethernet"
            case .unknown: return "Unknown"
            }
        }
    }
    
    // MARK: - Initialization
    
    private init() {
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Network Monitoring
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied
                self?.updateConnectionType(path)
            }
        }
        monitor.start(queue: monitorQueue)
    }
    
    private func stopMonitoring() {
        monitor.cancel()
    }
    
    private func updateConnectionType(_ path: NWPath) {
        if path.usesInterfaceType(.wifi) {
            connectionType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            connectionType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = .ethernet
        } else {
            connectionType = .unknown
        }
    }
    
    // MARK: - Network Request Helpers
    
    /// Create a URLSession with proper configuration
    func createURLSession(timeout: TimeInterval = 30) -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 2
        config.waitsForConnectivity = true
        config.allowsCellularAccess = true
        config.networkServiceType = .responsiveData
        
        // Add proper user agent
        let appVersion = ConfigurationManager.shared.getAppVersion()
        let buildNumber = ConfigurationManager.shared.getBuildNumber()
        config.httpAdditionalHeaders = [
            "User-Agent": "Seline/\(appVersion) (\(buildNumber)) iOS"
        ]
        
        return URLSession(configuration: config)
    }
    
    /// Check if we're on a metered connection (cellular)
    var isOnMeteredConnection: Bool {
        return connectionType == .cellular
    }
    
    /// Check if we should limit data usage
    var shouldLimitDataUsage: Bool {
        return isOnMeteredConnection
    }
}

// MARK: - API Rate Limiter

/// Manages API rate limiting to prevent quota exhaustion
class APIRateLimiter {
    static let shared = APIRateLimiter()
    
    private var requestCounts: [String: [Date]] = [:]
    private let queue = DispatchQueue(label: "APIRateLimiter", attributes: .concurrent)
    
    private init() {}
    
    /// Check if API request is allowed
    func canMakeRequest(for service: String, maxRequests: Int, timeWindow: TimeInterval) -> Bool {
        return queue.sync {
            let now = Date()
            let cutoffTime = now.addingTimeInterval(-timeWindow)
            
            // Clean old requests
            requestCounts[service] = requestCounts[service]?.filter { $0 > cutoffTime } ?? []
            
            // Check if we can make another request
            let currentCount = requestCounts[service]?.count ?? 0
            return currentCount < maxRequests
        }
    }
    
    /// Record a successful API request
    func recordRequest(for service: String) {
        queue.async(flags: .barrier) {
            if self.requestCounts[service] == nil {
                self.requestCounts[service] = []
            }
            self.requestCounts[service]?.append(Date())
        }
    }
    
    /// Get time until next request is allowed
    func timeUntilNextRequest(for service: String, maxRequests: Int, timeWindow: TimeInterval) -> TimeInterval {
        return queue.sync {
            guard let requests = requestCounts[service], requests.count >= maxRequests else {
                return 0
            }
            
            let oldestRequest = requests.first ?? Date()
            let nextAllowedTime = oldestRequest.addingTimeInterval(timeWindow)
            return max(0, nextAllowedTime.timeIntervalSinceNow)
        }
    }
}

// MARK: - Network Error Handling

enum NetworkError: LocalizedError {
    case noConnection
    case timeout
    case rateLimited
    case serverUnavailable
    case invalidResponse
    case dataCorrupted
    
    var errorDescription: String? {
        switch self {
        case .noConnection:
            return "No internet connection available."
        case .timeout:
            return "Request timed out. Please try again."
        case .rateLimited:
            return "Too many requests. Please wait before trying again."
        case .serverUnavailable:
            return "Server is temporarily unavailable."
        case .invalidResponse:
            return "Received invalid response from server."
        case .dataCorrupted:
            return "Response data is corrupted or invalid."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .noConnection:
            return "Check your internet connection and try again."
        case .timeout:
            return "The request took too long. Please try again."
        case .rateLimited:
            return "Wait a few minutes before making another request."
        case .serverUnavailable:
            return "This is a temporary issue. Please try again later."
        case .invalidResponse, .dataCorrupted:
            return "Please try again. If the problem persists, contact support."
        }
    }
}

// MARK: - Network Request Builder

struct NetworkRequest {
    let url: URL
    let method: HTTPMethod
    let headers: [String: String]
    let body: Data?
    let timeout: TimeInterval
    
    enum HTTPMethod: String {
        case GET = "GET"
        case POST = "POST"
        case PUT = "PUT"
        case DELETE = "DELETE"
        case PATCH = "PATCH"
    }
    
    func toURLRequest() -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = timeout
        
        headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        if let body = body {
            request.httpBody = body
        }
        
        return request
    }
}

// MARK: - Response Validator

struct ResponseValidator {
    /// Validate HTTP response and throw appropriate errors
    static func validate(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200...299:
            return // Success
        case 401:
            throw NetworkError.invalidResponse
        case 429:
            throw NetworkError.rateLimited
        case 500...599:
            throw NetworkError.serverUnavailable
        default:
            throw NetworkError.invalidResponse
        }
    }
}