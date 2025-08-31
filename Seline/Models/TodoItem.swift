//
//  TodoItem.swift
//  Seline
//
//  Created by Claude on 2025-08-29.
//

import Foundation

struct TodoItem: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let dueDate: Date
    let createdDate: Date
    var isCompleted: Bool
    let originalSpeechText: String
    var reminderDate: Date?
    var priority: Priority
    
    enum Priority: String, CaseIterable, Codable {
        case low = "Low"
        case medium = "Medium"
        case high = "High"
        
        var color: String {
            switch self {
            case .low: return "blue"
            case .medium: return "orange"
            case .high: return "red"
            }
        }
    }
    
    init(
        id: String = UUID().uuidString,
        title: String,
        description: String,
        dueDate: Date,
        originalSpeechText: String,
        reminderDate: Date? = nil,
        priority: Priority = .medium
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.dueDate = dueDate
        self.createdDate = Date()
        self.isCompleted = false
        self.originalSpeechText = originalSpeechText
        self.reminderDate = reminderDate
        self.priority = priority
    }
    
    // MARK: - Helper Methods
    
    var isOverdue: Bool {
        return dueDate < Date() && !isCompleted
    }
    
    var isDueToday: Bool {
        return Calendar.current.isDate(dueDate, inSameDayAs: Date())
    }
    
    var isDueTomorrow: Bool {
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) else { return false }
        return Calendar.current.isDate(dueDate, inSameDayAs: tomorrow)
    }
    
    var formattedDueDate: String {
        let formatter = DateFormatter()
        
        if isDueToday {
            return "Today"
        } else if isDueTomorrow {
            return "Tomorrow"
        } else if Calendar.current.isDate(dueDate, equalTo: Date(), toGranularity: .weekOfYear) {
            formatter.dateFormat = "EEEE" // Day name
            return formatter.string(from: dueDate)
        } else if Calendar.current.isDate(dueDate, equalTo: Date(), toGranularity: .year) {
            formatter.dateFormat = "MMM d" // Month day
            return formatter.string(from: dueDate)
        } else {
            formatter.dateFormat = "MMM d, yyyy" // Month day, year
            return formatter.string(from: dueDate)
        }
    }
    
    var formattedDueDateWithTime: String {
        let dateFormatter = DateFormatter()
        let timeFormatter = DateFormatter()
        
        if isDueToday {
            timeFormatter.timeStyle = .short
            return "Today at \(timeFormatter.string(from: dueDate))"
        } else if isDueTomorrow {
            timeFormatter.timeStyle = .short
            return "Tomorrow at \(timeFormatter.string(from: dueDate))"
        } else {
            dateFormatter.dateStyle = .medium
            timeFormatter.timeStyle = .short
            return "\(dateFormatter.string(from: dueDate)) at \(timeFormatter.string(from: dueDate))"
        }
    }
    
    var formattedReminderTime: String? {
        guard let reminderDate = reminderDate else { return nil }
        
        let formatter = DateFormatter()
        
        if Calendar.current.isDate(reminderDate, inSameDayAs: Date()) {
            formatter.timeStyle = .short
            return "Today at \(formatter.string(from: reminderDate))"
        } else if isDueTomorrow {
            formatter.timeStyle = .short
            return "Tomorrow at \(formatter.string(from: reminderDate))"
        } else if Calendar.current.isDate(reminderDate, equalTo: Date(), toGranularity: .weekOfYear) {
            formatter.dateFormat = "EEEE 'at' h:mm a" // Day name with time
            return formatter.string(from: reminderDate)
        } else if Calendar.current.isDate(reminderDate, equalTo: Date(), toGranularity: .year) {
            formatter.dateFormat = "MMM d 'at' h:mm a" // Month day with time
            return formatter.string(from: reminderDate)
        } else {
            formatter.dateFormat = "MMM d, yyyy 'at' h:mm a" // Month day, year with time
            return formatter.string(from: reminderDate)
        }
    }
}

// MARK: - Sample Data for Development

extension TodoItem {
    static var sampleData: [TodoItem] {
        [
            TodoItem(
                title: "Call Mom",
                description: "Remember to call mom about dinner plans this weekend",
                dueDate: Calendar.current.date(byAdding: .hour, value: 2, to: Date()) ?? Date(),
                originalSpeechText: "Remind me to call mom about dinner in 2 hours",
                priority: .medium
            ),
            TodoItem(
                title: "Dentist Appointment",
                description: "Annual dental checkup and cleaning appointment",
                dueDate: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date(),
                originalSpeechText: "I have a dentist appointment tomorrow at 2 PM",
                priority: .high
            ),
            TodoItem(
                title: "Buy Groceries",
                description: "Pick up milk, bread, eggs, and fresh vegetables from the store",
                dueDate: Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date(),
                originalSpeechText: "Add buy groceries to my todo list for this weekend",
                priority: .low
            )
        ]
    }
}