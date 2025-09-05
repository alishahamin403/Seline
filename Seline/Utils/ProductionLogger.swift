
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
    private static var lastLogTime = Date()
    private static var logCounter = 0

    private static func shouldLog() -> Bool {
        let now = Date()
        if now.timeIntervalSince(lastLogTime) > 2 {
            lastLogTime = now
            logCounter = 0
            return true
        }
        
        logCounter += 1
        return logCounter <= 10
    }
    
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
    static func logAppEvent(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard shouldLog() else { return }
        let fileName = (file as NSString).lastPathComponent
        app.info("[\(fileName):\(line)] \(function) - \(message)")
    }
    
    /// Log authentication events (success/failure only)
    static func logAuthEvent(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard shouldLog() else { return }
        let fileName = (file as NSString).lastPathComponent
        auth.info("[\(fileName):\(line)] \(function) - \(message)")
    }
    
    /// Log authentication errors
    static func logAuthError(_ error: Error, context: String = "", file: String = #file, function: String = #function, line: Int = #line) {
        guard shouldLog() else { return }
        let fileName = (file as NSString).lastPathComponent
        auth.error("[\(fileName):\(line)] \(function) - Auth error in \(context): \(error.localizedDescription)")
    }
    
    /// Log email operations (counts and errors only)
    static func logEmailOperation(_ operation: String, count: Int? = nil, file: String = #file, function: String = #function, line: Int = #line) {
        guard shouldLog() else { return }
        let fileName = (file as NSString).lastPathComponent
        if let count = count {
            email.info("[\(fileName):\(line)] \(function) - \(operation) - count: \(count)")
        } else {
            email.info("[\(fileName):\(line)] \(function) - \(operation)")
        }
    }
    
    /// Log email errors
    static func logEmailError(_ error: Error, operation: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard shouldLog() else { return }
        let fileName = (file as NSString).lastPathComponent
        email.error("[\(fileName):\(line)] \(function) - Email \(operation) failed: \(error.localizedDescription)")
    }
    
    /// Log network operations (essential only)
    static func logNetworkOperation(_ operation: String, success: Bool, file: String = #file, function: String = #function, line: Int = #line) {
        guard shouldLog() else { return }
        let fileName = (file as NSString).lastPathComponent
        if success {
            network.info("[\(fileName):\(line)] \(function) - \(operation) succeeded")
        } else {
            network.error("[\(fileName):\(line)] \(function) - \(operation) failed")
        }
    }
    
    /// Log network errors
    static func logNetworkError(_ error: Error, request: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard shouldLog() else { return }
        let fileName = (file as NSString).lastPathComponent
        network.error("[\(fileName):\(line)] \(function) - Network request \(request) failed: \(error.localizedDescription)")
    }
    
    /// Log critical errors that need attention
    static func logCriticalError(_ error: Error, context: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard shouldLog() else { return }
        let fileName = (file as NSString).lastPathComponent
        let callStack = Thread.callStackSymbols.joined(separator: "\n")
        self.error.fault("[\(fileName):\(line)] \(function) - CRITICAL ERROR in \(context): \(error.localizedDescription)\nCall Stack:\n\(callStack)")
    }
    
    /// Log general errors
    static func logError(_ error: Error, context: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard shouldLog() else { return }
        let fileName = (file as NSString).lastPathComponent
        self.error.error("[\(fileName):\(line)] \(function) - Error in \(context): \(error.localizedDescription)")
    }
    
    /// Log UI errors (navigation, state issues)
    static func logUIError(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        guard shouldLog() else { return }
        let fileName = (file as NSString).lastPathComponent
        ui.error("[\(fileName):\(line)] \(function) - UI Error: \(message)")
    }
    
    // MARK: - Development Helpers (Only in Debug)
    
    #if DEBUG
    /// Development-only logging for debugging
    static func debug(_ message: String, category: String = "debug", file: String = #file, function: String = #function, line: Int = #line) {
        let logger = Logger(subsystem: subsystem, category: category)
        let fileName = (file as NSString).lastPathComponent
        logger.debug("[\(fileName):\(line)] \(function) - \(message)")
    }
    #endif
}

// MARK: - Legacy Print Replacement

/// Replace print statements with appropriate logging
extension ProductionLogger {
    
    /// Log array bounds operations (production-safe)
    static func logArrayBounds(_ operation: String, count: Int, context: String, file: String = #file, function: String = #function, line: Int = #line) {
        // Only log if there's an issue
        if count < 0 {
            logError(NSError(domain: "ArrayBounds", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid array count: \(count)"]), context: "\(context) - \(operation)", file: file, function: function, line: line)
        }
    }
    
    /// Log email loading operations
    static func logEmailLoad(_ phase: String, count: Int, file: String = #file, function: String = #function, line: Int = #line) {
        logEmailOperation("Load \(phase)", count: count, file: file, function: function, line: line)
    }
    
    /// Log refresh operations
    static func logRefresh(_ component: String, success: Bool = true, file: String = #file, function: String = #function, line: Int = #line) {
        let fileName = (file as NSString).lastPathComponent
        if success {
            app.info("[\(fileName):\(line)] \(function) - Refresh completed: \(component)")
        } else {
            app.error("[\(fileName):\(line)] \(function) - Refresh failed: \(component)")
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
