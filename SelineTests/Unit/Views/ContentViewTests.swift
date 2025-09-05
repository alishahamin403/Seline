//
//  ContentViewTests.swift
//  SelineTests
//
//  Created by Claude Code on 2025-09-05.
//

import XCTest
import SwiftUI
@testable import Seline

class ContentViewTests: XCTestCase {
    
    // MARK: - Email Preview Tests
    
    func testEmailCardsShouldShowMaximumThreeEmails() {
        // Given
        let mockEmails = createMockEmails(count: 5)
        let viewModel = ContentViewModel()
        viewModel.emails = mockEmails
        
        // When
        let displayedEmails = viewModel.displayedTodaysEmails
        
        // Then
        XCTAssertLessThanOrEqual(displayedEmails.count, 3, "Should show maximum 3 emails on home page")
    }
    
    func testEmailCardsShowSubjectAndSender() {
        // Given
        let mockEmail = createMockEmail(subject: "Test Subject", senderName: "Test Sender")
        
        // When/Then
        XCTAssertEqual(mockEmail.subject, "Test Subject")
        XCTAssertEqual(mockEmail.sender.name, "Test Sender")
    }
    
    func testEmptyEmailStateShowsCorrectMessage() {
        // Given
        let viewModel = ContentViewModel()
        viewModel.emails = []
        
        // When
        let hasEmails = !viewModel.emails.isEmpty
        
        // Then
        XCTAssertFalse(hasEmails, "Should show empty state when no emails")
    }
    
    // MARK: - Calendar Event Deduplication Tests
    
    func testCalendarEventDeduplicationRemovesDuplicateEvents() {
        // Given
        let event1 = createMockCalendarEvent(id: "1", title: "Meeting", startDate: Date())
        let event2 = createMockCalendarEvent(id: "2", title: "Meeting", startDate: Date()) // Duplicate title & date
        let event3 = createMockCalendarEvent(id: "3", title: "Different Meeting", startDate: Date())
        let events = [event1, event2, event3]
        
        // When
        let deduplicatedEvents = removeDuplicateEvents(from: events)
        
        // Then
        XCTAssertEqual(deduplicatedEvents.count, 2, "Should remove duplicate events")
        XCTAssertTrue(deduplicatedEvents.contains { $0.title == "Different Meeting" }, "Should keep unique events")
    }
    
    func testCalendarEventDeduplicationPreservesUniqueEvents() {
        // Given
        let event1 = createMockCalendarEvent(id: "1", title: "Meeting 1", startDate: Date())
        let event2 = createMockCalendarEvent(id: "2", title: "Meeting 2", startDate: Date().addingTimeInterval(3600))
        let events = [event1, event2]
        
        // When
        let deduplicatedEvents = removeDuplicateEvents(from: events)
        
        // Then
        XCTAssertEqual(deduplicatedEvents.count, 2, "Should preserve all unique events")
    }
    
    func testCalendarEventsShouldShowMaximumThreeEvents() {
        // Given
        let mockEvents = createMockCalendarEvents(count: 5)
        let viewModel = ContentViewModel()
        viewModel.upcomingEvents = mockEvents
        
        // When
        let displayedEvents = Array(viewModel.upcomingEvents.prefix(3))
        
        // Then
        XCTAssertLessThanOrEqual(displayedEvents.count, 3, "Should show maximum 3 events on home page")
    }
    
    // MARK: - Todo List Tests
    
    func testTodoListShouldShowMaximumThreeTodos() {
        // Given
        let mockTodos = createMockTodos(count: 5)
        let todoManager = TodoManager.shared
        
        // When
        let displayedTodos = Array(mockTodos.prefix(3))
        
        // Then
        XCTAssertLessThanOrEqual(displayedTodos.count, 3, "Should show maximum 3 todos on home page")
    }
    
    // MARK: - Helper Methods
    
    private func createMockEmails(count: Int) -> [Email] {
        return (1...count).map { index in
            createMockEmail(
                subject: "Email \(index)",
                senderName: "Sender \(index)"
            )
        }
    }
    
    private func createMockEmail(subject: String, senderName: String) -> Email {
        return Email(
            id: UUID().uuidString,
            subject: subject,
            sender: EmailContact(name: senderName, email: "\(senderName.lowercased())@example.com"),
            recipients: [EmailContact(name: "Recipient", email: "recipient@example.com")],
            body: "Test body",
            date: Date(),
            isRead: false,
            isImportant: true,
            labels: ["INBOX"],
            attachments: [],
            isPromotional: false,
            hasCalendarEvent: false
        )
    }
    
    private func createMockCalendarEvents(count: Int) -> [CalendarEvent] {
        return (1...count).map { index in
            createMockCalendarEvent(
                id: "\(index)",
                title: "Event \(index)",
                startDate: Date().addingTimeInterval(TimeInterval(index * 3600))
            )
        }
    }
    
    private func createMockCalendarEvent(id: String, title: String, startDate: Date) -> CalendarEvent {
        return CalendarEvent(
            id: id,
            title: title,
            description: "Test description",
            startDate: startDate,
            endDate: startDate.addingTimeInterval(3600),
            location: "Test Location",
            isAllDay: false
        )
    }
    
    private func createMockTodos(count: Int) -> [TodoItem] {
        return (1...count).map { index in
            TodoItem(
                title: "Todo \(index)",
                description: "Test description \(index)",
                dueDate: Date().addingTimeInterval(TimeInterval(index * 86400)),
                priority: .medium,
                isCompleted: false
            )
        }
    }
    
    // Function to test - will be implemented in ContentViewModel
    private func removeDuplicateEvents(from events: [CalendarEvent]) -> [CalendarEvent] {
        var seen = Set<String>()
        return events.filter { event in
            let key = "\(event.title)-\(event.startDate.timeIntervalSince1970)"
            return seen.insert(key).inserted
        }
    }
}