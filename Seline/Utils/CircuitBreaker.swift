//
//  CircuitBreaker.swift
//  Seline
//
//  Created by Gemini on 2025-09-01.
//

import Foundation

class CircuitBreaker {
    enum State {
        case closed
        case open
        case halfOpen
    }
    
    private(set) var state: State = .closed
    private let failureThreshold: Int
    private let recoveryTimeout: TimeInterval
    private var failureCount = 0
    private var lastFailureTime: Date?
    
    init(failureThreshold: Int = 3, recoveryTimeout: TimeInterval = 60) {
        self.failureThreshold = failureThreshold
        self.recoveryTimeout = recoveryTimeout
    }
    
    func recordSuccess() {
        failureCount = 0
        state = .closed
    }
    
    func recordFailure() {
        failureCount += 1
        if failureCount >= failureThreshold {
            state = .open
            lastFailureTime = Date()
        }
    }
    
    func canAttemptRequest() -> Bool {
        switch state {
        case .closed:
            return true
        case .open:
            guard let lastFailureTime = lastFailureTime else {
                return true // Should not happen
            }
            if Date().timeIntervalSince(lastFailureTime) > recoveryTimeout {
                state = .halfOpen
                return true
            }
            return false
        case .halfOpen:
            return true
        }
    }
}