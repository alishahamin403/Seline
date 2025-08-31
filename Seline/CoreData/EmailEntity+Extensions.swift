//
//  EmailEntity+Extensions.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-28.
//

import Foundation
import CoreData

extension EmailEntity {
    
    // MARK: - Convenience Properties
    
    var sender: EmailContact? {
        guard let senderData = senderData else { return nil }
        return try? JSONDecoder().decode(EmailContact.self, from: senderData)
    }
    
    var recipients: [EmailContact] {
        guard let recipientsData = recipientsData else { return [] }
        return (try? JSONDecoder().decode([EmailContact].self, from: recipientsData)) ?? []
    }
    
    var attachments: [EmailAttachment] {
        guard let attachmentsData = attachmentsData else { return [] }
        return (try? JSONDecoder().decode([EmailAttachment].self, from: attachmentsData)) ?? []
    }
    
    var labels: [String] {
        guard let labelsData = labelsData else { return [] }
        return (try? JSONDecoder().decode([String].self, from: labelsData)) ?? []
    }
    
    // MARK: - Custom Fetch Requests
    
    static func fetchRequestForUser(_ user: UserEntity) -> NSFetchRequest<EmailEntity> {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "user == %@", user)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \EmailEntity.date, ascending: false)]
        return request
    }
    
    static func fetchRequestForUnread(_ user: UserEntity) -> NSFetchRequest<EmailEntity> {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "user == %@ AND isRead == NO", user)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \EmailEntity.date, ascending: false)]
        return request
    }
    
    static func fetchRequestForImportant(_ user: UserEntity) -> NSFetchRequest<EmailEntity> {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "user == %@ AND isImportant == YES", user)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \EmailEntity.date, ascending: false)]
        return request
    }
    
    static func fetchRequestForPromotional(_ user: UserEntity) -> NSFetchRequest<EmailEntity> {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "user == %@ AND isPromotional == YES", user)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \EmailEntity.date, ascending: false)]
        return request
    }
    
    static func fetchRequestForCalendar(_ user: UserEntity) -> NSFetchRequest<EmailEntity> {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "user == %@ AND hasCalendarEvent == YES", user)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \EmailEntity.date, ascending: false)]
        return request
    }
    
    static func fetchRequestForSearch(_ query: String, user: UserEntity) -> NSFetchRequest<EmailEntity> {
        let request = fetchRequest()
        request.predicate = NSPredicate(
            format: "user == %@ AND (subject CONTAINS[cd] %@ OR body CONTAINS[cd] %@)",
            user, query, query
        )
        request.sortDescriptors = [NSSortDescriptor(keyPath: \EmailEntity.date, ascending: false)]
        return request
    }
    
    // MARK: - Batch Operations
    
    static func deleteOldEmails(olderThan date: Date, in context: NSManagedObjectContext) -> Int {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "date < %@", date as NSDate)
        
        do {
            let oldEmails = try context.fetch(request)
            let deleteCount = oldEmails.count
            
            for email in oldEmails {
                context.delete(email)
            }
            
            return deleteCount
        } catch {
            ProductionLogger.logError(error as NSError, context: "EmailEntity batch delete")
            return 0
        }
    }
    
    static func markAsRead(gmailIDs: [String], user: UserEntity, in context: NSManagedObjectContext) {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "user == %@ AND gmailID IN %@", user, gmailIDs)
        
        do {
            let emails = try context.fetch(request)
            for email in emails {
                email.isRead = true
                email.updatedAt = Date()
            }
        } catch {
            ProductionLogger.logError(error as NSError, context: "EmailEntity mark as read batch")
        }
    }
    
    static func markAsImportant(gmailIDs: [String], user: UserEntity, isImportant: Bool, in context: NSManagedObjectContext) {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "user == %@ AND gmailID IN %@", user, gmailIDs)
        
        do {
            let emails = try context.fetch(request)
            for email in emails {
                email.isImportant = isImportant
                email.updatedAt = Date()
            }
        } catch {
            ProductionLogger.logError(error as NSError, context: "EmailEntity mark as important batch")
        }
    }
    
    // MARK: - Statistics
    
    static func getEmailCount(for user: UserEntity, in context: NSManagedObjectContext) -> Int {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "user == %@", user)
        request.includesSubentities = false
        
        do {
            return try context.count(for: request)
        } catch {
            ProductionLogger.logError(error as NSError, context: "EmailEntity count")
            return 0
        }
    }
    
    static func getUnreadCount(for user: UserEntity, in context: NSManagedObjectContext) -> Int {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "user == %@ AND isRead == NO", user)
        request.includesSubentities = false
        
        do {
            return try context.count(for: request)
        } catch {
            ProductionLogger.logError(error as NSError, context: "EmailEntity unread count")
            return 0
        }
    }
}

// MARK: - Sync Status Enum

enum SyncStatus: Int16, CaseIterable {
    case pending = 0
    case syncing = 1
    case synced = 2
    case failed = 3
    
    var description: String {
        switch self {
        case .pending: return "Pending"
        case .syncing: return "Syncing"
        case .synced: return "Synced"
        case .failed: return "Failed"
        }
    }
}