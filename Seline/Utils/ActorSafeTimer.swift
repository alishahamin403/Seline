//
//  ActorSafeTimer.swift
//  Seline
//
//  Created by Gemini on 2025-09-01.
//

import Foundation

/// A helper class to manage a Timer in a way that is safe to access from any actor context.
class ActorSafeTimer {
    private var timer: Timer?
    private let queue = DispatchQueue(label: "com.seline.actorsafetimer")

    func schedule(withTimeInterval interval: TimeInterval, repeats: Bool, block: @escaping @Sendable () -> Void) {
        queue.async {
            self.timer?.invalidate()
            self.timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: repeats) { _ in
                block()
            }
            // Add the timer to the main run loop to ensure it fires
            RunLoop.main.add(self.timer!, forMode: .common)
        }
    }

    func invalidate() {
        queue.async {
            self.timer?.invalidate()
            self.timer = nil
        }
    }
    
    deinit {
        invalidate()
    }
}
