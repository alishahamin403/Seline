//
//  SafeArrayAccess.swift
//  Seline
//
//  Created by Claude on 2025-08-27.
//  Defensive programming utilities for safe array access
//

import Foundation

extension Array {
    /// Safely access array element at index, returning nil if index is out of bounds
    func safeElement(at index: Int) -> Element? {
        guard index >= 0 && index < count else {
            print("⚠️ SafeArrayAccess: Index \(index) out of bounds for array with \(count) elements")
            return nil
        }
        return self[index]
    }
    
    /// Safely get array slice from start to end indices
    func safeSlice(from start: Int, to end: Int) -> ArraySlice<Element> {
        let safeStart = Swift.max(0, Swift.min(start, count))
        let safeEnd = Swift.max(safeStart, Swift.min(end, count))
        
        print("🔍 SafeArrayAccess: Slicing array[\(safeStart)..<\(safeEnd)] from original[\(start)..<\(end)] with count=\(count)")
        
        return self[safeStart..<safeEnd]
    }
    
    /// Safe prefix that ensures we don't exceed array bounds
    func safePrefix(_ maxLength: Int) -> Array<Element> {
        let safeLength = Swift.min(maxLength, count)
        print("🔍 SafeArrayAccess: Taking prefix(\(safeLength)) from array with \(count) elements")
        return Array(prefix(safeLength))
    }
    
    /// Safe suffix that ensures we don't exceed array bounds
    func safeSuffix(_ maxLength: Int) -> Array<Element> {
        let safeLength = Swift.min(maxLength, count)
        print("🔍 SafeArrayAccess: Taking suffix(\(safeLength)) from array with \(count) elements")
        return Array(suffix(safeLength))
    }
    
    /// Check if index is valid for this array
    func isValidIndex(_ index: Int) -> Bool {
        return index >= 0 && index < count
    }
    
    /// Get safe enumerated array with bounds checking
    func safeEnumerated() -> [(Int, Element)] {
        print("🔍 SafeArrayAccess: Creating safe enumeration for array with \(count) elements")
        var result: [(Int, Element)] = []
        
        for (index, element) in enumerated() {
            guard isValidIndex(index) else {
                print("⚠️ SafeArrayAccess: Invalid index \(index) during enumeration")
                continue
            }
            result.append((index, element))
        }
        
        return result
    }
}

extension Array where Element: Identifiable {
    /// Safely find element by ID with bounds checking
    func safeFirst(where predicate: (Element) throws -> Bool) rethrows -> Element? {
        print("🔍 SafeArrayAccess: Searching in array with \(count) elements")
        
        for (index, element) in enumerated() {
            guard isValidIndex(index) else {
                print("⚠️ SafeArrayAccess: Invalid index \(index) during search")
                continue
            }
            
            if try predicate(element) {
                return element
            }
        }
        
        return nil
    }
    
    /// Safely get last element with ID check
    func safeLastElement() -> Element? {
        guard !isEmpty else {
            print("🔍 SafeArrayAccess: Cannot get last element from empty array")
            return nil
        }
        
        let lastIndex = count - 1
        guard isValidIndex(lastIndex) else {
            print("⚠️ SafeArrayAccess: Invalid last index \(lastIndex) for array with \(count) elements")
            return nil
        }
        
        return self[lastIndex]
    }
}

// MARK: - Email Array Extensions

extension Array where Element == Email {
    /// Safely sort emails by date with bounds checking
    func safeSortedByDate(ascending: Bool = false) -> [Email] {
        guard !isEmpty else {
            print("🔍 SafeEmailArray: Cannot sort empty email array")
            return []
        }
        
        print("🔍 SafeEmailArray: Sorting \(count) emails by date (ascending: \(ascending))")
        
        return sorted { email1, email2 in
            return ascending ? email1.date < email2.date : email1.date > email2.date
        }
    }
    
    /// Safely filter emails with bounds checking
    func safeFilter(_ isIncluded: (Email) throws -> Bool) rethrows -> [Email] {
        print("🔍 SafeEmailArray: Filtering \(count) emails")
        
        var filteredEmails: [Email] = []
        
        for (index, email) in enumerated() {
            guard isValidIndex(index) else {
                print("⚠️ SafeEmailArray: Invalid index \(index) during filtering")
                continue
            }
            
            if try isIncluded(email) {
                filteredEmails.append(email)
            }
        }
        
        print("🔍 SafeEmailArray: Filtered result: \(filteredEmails.count) emails")
        return filteredEmails
    }
}

// MARK: - Debug Logging

struct ArrayBoundsLogger {
    static func logArrayAccess(arrayName: String, count: Int, requestedIndex: Int? = nil) {
        if let index = requestedIndex {
            let isValid = index >= 0 && index < count
            let status = isValid ? "✅ VALID" : "❌ INVALID"
            print("🔍 ArrayBounds: \(arrayName)[\(index)] - Array count: \(count) - \(status)")
        } else {
            print("🔍 ArrayBounds: \(arrayName) - Array count: \(count)")
        }
    }
    
    static func logArrayOperation(operation: String, arrayName: String, originalCount: Int, resultCount: Int) {
        print("🔍 ArrayBounds: \(operation) on \(arrayName) - \(originalCount) → \(resultCount) elements")
    }
}