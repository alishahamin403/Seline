//
//  ProductionLogger.swift
//  Seline
//
//  Created by Claude on 2025-08-27.
//  Production-ready logging system
//

import Foundation
import os.log

/// Production logging system that only logs essential information
struct ProductionLogger {
    
    private static let subsystem = "com.seline.app"
    
    /// Application lifecycle logger
    static let app = Logger(subsystem: subsystem, category: "app")
    
    /// Authentication and security logger
    static let auth = Logger(subsystem: subsystem, category: "auth")
    
    /// Email operations logger
    static let email = Logger(subsystem: subsystem, category: "email")
    
    /// Network operations logger
    static let network = Logger(subsystem: subsystem, category: "network")
    
    /// Error logger
    static let error = Logger(subsystem: subsystem, category: "error")
    
    /// UI interactions logger (minimal for production)
    static let ui = Logger(subsystem: subsystem, category: "ui")
    
    // MARK: - Logging Methods
    
    /// Log application lifecycle events
    static func logAppEvent(_ message: String) {
        app.info("\(message)")
    }
    
    /// Log authentication events (success/failure only)
    static func logAuthEvent(_ message: String) {
        auth.info("\(message)")
    }
    
    /// Log authentication errors
    static func logAuthError(_ error: Error, context: String = "") {
        auth.error("Auth error in \(context): \(error.localizedDescription)")
    }
    
    /// Log email operations (counts and errors only)
    static func logEmailOperation(_ operation: String, count: Int? = nil) {
        if let count = count {
            email.info("\(operation) - count: \(count)")
        } else {
            email.info("\(operation)")
        }
    }
    
    /// Log email errors
    static func logEmailError(_ error: Error, operation: String) {
        email.error("Email \(operation) failed: \(error.localizedDescription)")
    }
    
    /// Log network operations (essential only)
    static func logNetworkOperation(_ operation: String, success: Bool) {
        if success {
            network.info("\(operation) succeeded")
        } else {
            network.error("\(operation) failed")
        }
    }
    
    /// Log network errors
    static func logNetworkError(_ error: Error, request: String) {
        network.error("Network request \(request) failed: \(error.localizedDescription)")
    }
    
    /// Log critical errors that need attention
    static func logCriticalError(_ error: Error, context: String) {
        self.error.fault("CRITICAL ERROR in \(context): \(error.localizedDescription)")
    }
    
    /// Log general errors
    static func logError(_ error: Error, context: String) {
        self.error.error("Error in \(context): \(error.localizedDescription)")
    }
    
    /// Log UI errors (navigation, state issues)
    static func logUIError(_ message: String) {
        ui.error("UI Error: \(message)")
    }
    
    // MARK: - Development Helpers (Only in Debug)
    
    #if DEBUG
    /// Development-only logging for debugging
    static func debug(_ message: String, category: String = "debug") {
        let logger = Logger(subsystem: subsystem, category: category)
        logger.debug("\(message)")
    }
    #endif
}

// MARK: - Legacy Print Replacement

/// Replace print statements with appropriate logging
extension ProductionLogger {
    
    /// Log array bounds operations (production-safe)
    static func logArrayBounds(_ operation: String, count: Int, context: String) {
        // Only log if there's an issue
        if count < 0 {
            logError(NSError(domain: "ArrayBounds", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid array count: \(count)"]), context: "\(context) - \(operation)")
        }
    }
    
    /// Log email loading operations
    static func logEmailLoad(_ phase: String, count: Int) {
        logEmailOperation("Load \(phase)", count: count)
    }
    
    /// Log refresh operations
    static func logRefresh(_ component: String, success: Bool = true) {
        if success {
            app.info("Refresh completed: \(component)")
        } else {
            app.error("Refresh failed: \(component)")
        }
    }
}

// MARK: - Performance Monitoring

extension ProductionLogger {
    
    /// Monitor performance of critical operations
    static func measureTime<T>(operation: String, block: () throws -> T) rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try block()
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        
        // Only log if operation takes longer than expected
        if timeElapsed > 1.0 { // Log operations taking > 1 second
            app.info("Performance: \(operation) took \(String(format: "%.2f", timeElapsed))s")
        }
        
        return result
    }
    
    /// Monitor async performance
    static func measureTimeAsync<T>(operation: String, block: () async throws -> T) async rethrows -> T {
        let startTime = CFAbsoluteTimeGetCurrent()
        let result = try await block()
        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
        
        // Only log if operation takes longer than expected
        if timeElapsed > 2.0 { // Log async operations taking > 2 seconds
            app.info("Async Performance: \(operation) took \(String(format: "%.2f", timeElapsed))s")
        }
        
        return result
    }
}