//
//  VoiceMode.swift
//  Seline
//
//  Created by Claude on 2025-08-31.
//

import SwiftUI

enum VoiceMode: String, CaseIterable, Identifiable {
    case calendar = "calendar"
    case todo = "todo"
    case search = "search"
    
    var id: String { rawValue }
    
    // Display properties
    var title: String {
        switch self {
        case .calendar:
            return "Calendar Event"
        case .todo:
            return "Todo Item"
        case .search:
            return "AI Search"
        }
    }
    
    var subtitle: String {
        switch self {
        case .calendar:
            return "Create calendar events and meetings"
        case .todo:
            return "Add tasks and reminders"
        case .search:
            return "Search emails with AI assistance"
        }
    }
    
    var icon: String {
        switch self {
        case .calendar:
            return "calendar.badge.plus"
        case .todo:
            return "checklist"
        case .search:
            return "magnifyingglass.circle"
        }
    }
    
    var color: Color {
        switch self {
        case .calendar:
            return .blue
        case .todo:
            return .green
        case .search:
            return .purple
        }
    }
    
    var gradient: LinearGradient {
        switch self {
        case .calendar:
            return LinearGradient(
                colors: [Color.blue.opacity(0.8), Color.blue.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .todo:
            return LinearGradient(
                colors: [Color.green.opacity(0.8), Color.green.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .search:
            return LinearGradient(
                colors: [Color.purple.opacity(0.8), Color.purple.opacity(0.6)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    // Recording-specific properties
    var recordingPrompt: String {
        switch self {
        case .calendar:
            return "Tell me about your event..."
        case .todo:
            return "What do you need to remember?"
        case .search:
            return "What emails are you looking for?"
        }
    }
    
    var recordingExample: String {
        switch self {
        case .calendar:
            return "\"Meeting with John tomorrow at 3pm\""
        case .todo:
            return "\"Buy groceries for dinner party\""
        case .search:
            return "\"Find emails from Sarah about the project\""
        }
    }
    
    var recordingIcon: String {
        switch self {
        case .calendar:
            return "calendar"
        case .todo:
            return "checkmark.circle"
        case .search:
            return "magnifyingglass"
        }
    }
    
    // Emoji for visual appeal
    var emoji: String {
        switch self {
        case .calendar:
            return "📅"
        case .todo:
            return "✅"
        case .search:
            return "🔍"
        }
    }
}