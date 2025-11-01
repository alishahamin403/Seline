import Foundation

// Utility functions for hashing
struct HashUtils {
    /// Generates a deterministic hash that remains consistent across app rebuilds
    /// Uses DJB2 hash algorithm for stability
    static func deterministicHash(_ string: String) -> Int {
        var hash: UInt64 = 5381
        for byte in string.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        // Convert to Int safely by truncating to fit in range
        return Int(bitPattern: UInt(truncatingIfNeeded: hash))
    }
}
