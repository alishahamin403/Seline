//
//  EmailFormatters.swift
//  Seline
//
//  Created by Claude on 2025-08-31.
//

import Foundation

struct EmailFormatters {
    
    // MARK: - Date Formatting
    
    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "h:mm a"
        } else if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            formatter.dateFormat = "MMM d"
        } else {
            formatter.dateFormat = "MMM d, yyyy"
        }
        
        return formatter.string(from: date)
    }
    
    static func formatFullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    // MARK: - File Size Formatting
    
    static func formatFileSize(_ size: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(size))
    }
    
    // MARK: - Email Content Processing
    
    static func extractPreviewText(from body: String, maxLength: Int = 150) -> String {
        let cleanBody = body
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        if cleanBody.count <= maxLength {
            return cleanBody
        }
        
        let truncated = String(cleanBody.prefix(maxLength))
        return truncated + "..."
    }
    
    // MARK: - Avatar Color Generation
    
    static func generateAvatarColor(for email: String) -> (red: Double, green: Double, blue: Double) {
        let hash = abs(email.hashValue)
        let red = Double((hash & 0xFF0000) >> 16) / 255.0
        let green = Double((hash & 0x00FF00) >> 8) / 255.0
        let blue = Double(hash & 0x0000FF) / 255.0
        
        return (red: red, green: green, blue: blue)
    }
}