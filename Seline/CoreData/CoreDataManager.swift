//
//  CoreDataManager.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-28.
//

import CoreData
import Foundation
import UIKit

class CoreDataManager: ObservableObject {
    static let shared = CoreDataManager()
    
    // MARK: - Core Data Stack
    
    lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "SelineDataModel")
        
        // Configure for better performance
        let description = container.persistentStoreDescriptions.first
        description?.shouldInferMappingModelAutomatically = true
        description?.shouldMigrateStoreAutomatically = true
        description?.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description?.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        
        container.loadPersistentStores { _, error in
            if let error = error as NSError? {
                ProductionLogger.logError(error, context: "Core Data persistent store loading")
                
                // Try to handle migration issues by clearing and recreating the store
                if error.code == NSPersistentStoreIncompatibleVersionHashError || 
                   error.code == NSMigrationMissingSourceModelError {
                    self.clearPersistentStore(container)
                    // Try loading again after clearing
                    container.loadPersistentStores { _, secondError in
                        if let secondError = secondError as NSError? {
                            ProductionLogger.logError(secondError, context: "Core Data persistent store loading after clear")
                            fatalError("Core Data error after clear: \(secondError), \(secondError.userInfo)")
                        }
                    }
                } else {
                    fatalError("Core Data error: \(error), \(error.userInfo)")
                }
            }
        }
        
        // Configure for concurrency
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        
        return container
    }()
    
    var viewContext: NSManagedObjectContext {
        return persistentContainer.viewContext
    }
    
    var backgroundContext: NSManagedObjectContext {
        let context = persistentContainer.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }
    
    private init() {
        setupNotifications()
    }
    
    // MARK: - Save Context
    
    func save() {
        let context = viewContext
        
        if context.hasChanges {
            do {
                // Validate objects before saving to prevent nil insertion errors
                for object in context.insertedObjects {
                    do {
                        try object.validateForInsert()
                        
                        // Additional check for relationship integrity
                        if let userEntity = object as? UserEntity {
                            // Ensure user relationships don't contain invalid objects
                            validateUserRelationships(userEntity, in: context)
                        } else if let syncStatus = object as? SyncStatusEntity {
                            // Ensure sync status has a valid user
                            if syncStatus.user?.isDeleted == true || syncStatus.user?.managedObjectContext == nil {
                                ProductionLogger.logError(
                                    NSError(domain: "CoreDataManager", code: -5, userInfo: [NSLocalizedDescriptionKey: "SyncStatusEntity has invalid user relationship"]), 
                                    context: "Core Data validation sync status"
                                )
                                context.delete(object)
                            }
                        } else if let emailEntity = object as? EmailEntity {
                            // Ensure email has a valid user
                            if emailEntity.user?.isDeleted == true || emailEntity.user?.managedObjectContext == nil {
                                ProductionLogger.logError(
                                    NSError(domain: "CoreDataManager", code: -6, userInfo: [NSLocalizedDescriptionKey: "EmailEntity has invalid user relationship"]), 
                                    context: "Core Data validation email"
                                )
                                context.delete(object)
                            }
                        }
                    } catch {
                        ProductionLogger.logError(error as NSError, context: "Core Data validation failed for insert")
                        context.delete(object)
                    }
                }
                
                for object in context.updatedObjects {
                    do {
                        try object.validateForUpdate()
                    } catch {
                        ProductionLogger.logError(error as NSError, context: "Core Data validation failed for update")
                        // Refresh the object to discard invalid changes
                        context.refresh(object, mergeChanges: false)
                    }
                }
                
                try context.save()
                ProductionLogger.logCoreDataEvent("Main context saved successfully")
            } catch {
                let nsError = error as NSError
                ProductionLogger.logError(nsError, context: "Core Data save - main context")
                
                // If save fails, rollback to prevent corruption
                context.rollback()
            }
        }
    }
    
    func saveBackground(_ context: NSManagedObjectContext) {
        if context.hasChanges {
            do {
                try context.save()
                ProductionLogger.logCoreDataEvent("Background context saved successfully")
            } catch {
                let nsError = error as NSError
                ProductionLogger.logError(nsError, context: "Core Data save - background context")
            }
        }
    }
    
    // MARK: - User Management
    
    func createOrUpdateUser(_ selineUser: SelineUser) -> UserEntity? {
        let context = viewContext
        
        // Check if user already exists
        let request: NSFetchRequest<UserEntity> = UserEntity.fetchRequest()
        request.predicate = NSPredicate(format: "email == %@", selineUser.email)
        
        do {
            let existingUsers = try context.fetch(request)
            let userEntity: UserEntity
            
            if let existingUser = existingUsers.first {
                userEntity = existingUser
                ProductionLogger.logCoreDataEvent("Updating existing user: \(selineUser.email)")
            } else {
                userEntity = UserEntity(context: context)
                // Safely set the ID using direct assignment or KVC fallback
                let uuid = UUID()
                if userEntity.responds(to: #selector(setter: UserEntity.id)) {
                    userEntity.id = uuid
                } else {
                    userEntity.setValue(uuid, forKey: "id")
                }
                ProductionLogger.logCoreDataEvent("Creating new user: \(selineUser.email)")
            }
            
            // Update user properties
            userEntity.email = selineUser.email
            userEntity.name = selineUser.name
            userEntity.profileImageURL = selineUser.profileImageURL
            userEntity.accessToken = selineUser.accessToken
            userEntity.refreshToken = selineUser.refreshToken
            userEntity.tokenExpirationDate = selineUser.tokenExpirationDate
            
            save()
            return userEntity
            
        } catch {
            ProductionLogger.logError(error as NSError, context: "Core Data user creation/update")
            return nil
        }
    }
    
    func getCurrentUser() -> UserEntity? {
        let context = viewContext
        let request: NSFetchRequest<UserEntity> = UserEntity.fetchRequest()
        request.fetchLimit = 1
        request.sortDescriptors = [NSSortDescriptor(keyPath: \UserEntity.email, ascending: true)]
        
        do {
            let users = try context.fetch(request)
            return users.first
        } catch {
            ProductionLogger.logError(error as NSError, context: "Core Data getCurrentUser")
            return nil
        }
    }
    
    // MARK: - Email Management
    
    func saveEmails(_ emails: [Email], for user: UserEntity) {
        let backgroundContext = self.backgroundContext
        
        backgroundContext.perform {
            guard let userInContext = backgroundContext.object(with: user.objectID) as? UserEntity else {
                ProductionLogger.logError(NSError(domain: "CoreDataManager", code: -1), context: "User not found in background context")
                return
            }
            
            var savedCount = 0
            var updatedCount = 0
            
            for email in emails {
                if let emailEntity = self.createOrUpdateEmailEntity(email, user: userInContext, context: backgroundContext) {
                    if emailEntity.isInserted {
                        savedCount += 1
                    } else {
                        updatedCount += 1
                    }
                }
            }
            
            self.saveBackground(backgroundContext)
            ProductionLogger.logCoreDataEvent("Saved \(savedCount) new emails, updated \(updatedCount) emails")
            
            // Notify main thread of changes
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }

    /// Delete a single email by its Gmail message ID for the current user
    /// Returns true if an email record was deleted
    func deleteEmailByGmailID(_ gmailID: String) -> Bool {
        let context = viewContext
        let request: NSFetchRequest<EmailEntity> = EmailEntity.fetchRequest()
        request.predicate = NSPredicate(format: "gmailID == %@", gmailID)
        request.fetchLimit = 1
        
        do {
            if let emailEntity = try context.fetch(request).first {
                context.delete(emailEntity)
                save()
                ProductionLogger.logCoreDataEvent("Deleted local email with gmailID: \(gmailID)")
                return true
            }
        } catch {
            ProductionLogger.logError(error as NSError, context: "Core Data deleteEmailByGmailID")
        }
        return false
    }
    
    private func createOrUpdateEmailEntity(_ email: Email, user: UserEntity, context: NSManagedObjectContext) -> EmailEntity? {
        // Validate email data first to prevent nil insertions
        guard !email.id.isEmpty,
              !email.subject.isEmpty else {
            ProductionLogger.logError(NSError(domain: "CoreDataManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid email data - missing required fields"]), context: "Email validation")
            return nil
        }
        
        // Check if email already exists
        let request: NSFetchRequest<EmailEntity> = EmailEntity.fetchRequest()
        request.predicate = NSPredicate(format: "gmailID == %@ AND user == %@", email.id, user)
        
        do {
            let existingEmails = try context.fetch(request)
            let emailEntity: EmailEntity
            
            if let existingEmail = existingEmails.first {
                emailEntity = existingEmail
            } else {
                emailEntity = EmailEntity(context: context)
                // Safely set the ID using direct assignment or KVC fallback
                let uuid = UUID()
                if emailEntity.responds(to: #selector(setter: EmailEntity.id)) {
                    emailEntity.id = uuid
                } else {
                    emailEntity.setValue(uuid, forKey: "id")
                }
                emailEntity.gmailID = email.id
                
                // Validate user before setting relationship
                if !user.isDeleted && user.managedObjectContext == context {
                    emailEntity.user = user
                } else {
                    ProductionLogger.logError(
                        NSError(domain: "CoreDataManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Cannot set email user relationship - invalid user state"]), 
                        context: "createOrUpdateEmailEntity"
                    )
                    context.delete(emailEntity)
                    return nil
                }
            }
            
            // Update email properties with nil safety
            emailEntity.subject = email.subject
            emailEntity.body = email.body
            emailEntity.date = email.date
            emailEntity.isRead = email.isRead
            emailEntity.isImportant = email.isImportant
            emailEntity.isPromotional = email.isPromotional
            emailEntity.hasCalendarEvent = email.hasCalendarEvent
            
            emailEntity.updatedAt = Date()
            
            // Safely encode complex objects as Data with nil checks
            if let senderData = try? JSONEncoder().encode(email.sender) {
                emailEntity.senderData = senderData
            }
            
            if let recipientsData = try? JSONEncoder().encode(email.recipients) {
                emailEntity.recipientsData = recipientsData
            }
            
            if let attachmentsData = try? JSONEncoder().encode(email.attachments) {
                emailEntity.attachmentsData = attachmentsData
            }
            
            if let labelsData = try? JSONEncoder().encode(email.labels) {
                emailEntity.labelsData = labelsData
            }
            
            // Safely handle categories relationship - clear existing to prevent nil insertions
            if let categories = emailEntity.categories {
                emailEntity.removeFromCategories(categories)
            }
            
            return emailEntity
            
        } catch {
            ProductionLogger.logError(error as NSError, context: "Core Data email creation/update")
            return nil
        }
    }
    
    // MARK: - Email Fetching
    
    func fetchEmails(for user: UserEntity, limit: Int = 50, offset: Int = 0) -> [Email] {
        let context = viewContext
        let request: NSFetchRequest<EmailEntity> = EmailEntity.fetchRequest()
        
        request.predicate = NSPredicate(format: "user == %@", user)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \EmailEntity.date, ascending: false)]
        request.fetchLimit = limit
        request.fetchOffset = offset
        
        do {
            let emailEntities = try context.fetch(request)
            return emailEntities.compactMap { convertToEmail($0) }
        } catch {
            ProductionLogger.logError(error as NSError, context: "Core Data fetchEmails")
            return []
        }
    }
    
    func fetchEmailsBy(category: EmailCategory, for user: UserEntity, limit: Int = 50) -> [Email] {
        let context = viewContext
        let request: NSFetchRequest<EmailEntity> = EmailEntity.fetchRequest()
        
        var predicate = NSPredicate(format: "user == %@", user)
        
        switch category {
        case .important:
            predicate = NSPredicate(format: "user == %@ AND isImportant == YES", user)
        case .promotional:
            predicate = NSPredicate(format: "user == %@ AND isPromotional == YES", user)
        
        case .unread:
            predicate = NSPredicate(format: "user == %@ AND isRead == NO", user)
        case .calendar:
            predicate = NSPredicate(format: "user == %@ AND hasCalendarEvent == YES", user)
        case .all:
            break
        }
        
        request.predicate = predicate
        request.sortDescriptors = [NSSortDescriptor(keyPath: \EmailEntity.date, ascending: false)]
        request.fetchLimit = limit
        
        do {
            let emailEntities = try context.fetch(request)
            return emailEntities.compactMap { convertToEmail($0) }
        } catch {
            ProductionLogger.logError(error as NSError, context: "Core Data fetchEmailsBy category")
            return []
        }
    }
    
    func fetchAllEmails(for user: UserEntity, limit: Int = 200) -> [Email] {
        let context = viewContext
        let request: NSFetchRequest<EmailEntity> = EmailEntity.fetchRequest()
        
        request.predicate = NSPredicate(format: "user == %@", user)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \EmailEntity.date, ascending: false)]
        request.fetchLimit = limit
        
        do {
            let emailEntities = try context.fetch(request)
            return emailEntities.compactMap { convertToEmail($0) }
        } catch {
            ProductionLogger.logError(error as NSError, context: "Core Data fetchAllEmails")
            return []
        }
    }
    
    func searchEmails(query: String, for user: UserEntity, limit: Int = 50) -> [Email] {
        let context = viewContext
        let request: NSFetchRequest<EmailEntity> = EmailEntity.fetchRequest()
        
        let searchPredicate = NSPredicate(
            format: "user == %@ AND (subject CONTAINS[cd] %@ OR body CONTAINS[cd] %@)",
            user, query, query
        )
        
        request.predicate = searchPredicate
        request.sortDescriptors = [NSSortDescriptor(keyPath: \EmailEntity.date, ascending: false)]
        request.fetchLimit = limit
        
        do {
            let emailEntities = try context.fetch(request)
            return emailEntities.compactMap { convertToEmail($0) }
        } catch {
            ProductionLogger.logError(error as NSError, context: "Core Data searchEmails")
            return []
        }
    }
    
    // MARK: - Email Conversion
    
    private func convertToEmail(_ emailEntity: EmailEntity) -> Email? {
        guard let gmailID = emailEntity.gmailID,
              let subject = emailEntity.subject,
              let body = emailEntity.body,
              let date = emailEntity.date else {
            return nil
        }
        
        // Decode sender
        var sender = EmailContact(name: "Unknown", email: "unknown@email.com")
        if let senderData = emailEntity.senderData,
           let decodedSender = try? JSONDecoder().decode(EmailContact.self, from: senderData) {
            sender = decodedSender
        }
        
        // Decode recipients
        var recipients: [EmailContact] = []
        if let recipientsData = emailEntity.recipientsData,
           let decodedRecipients = try? JSONDecoder().decode([EmailContact].self, from: recipientsData) {
            recipients = decodedRecipients
        }
        
        // Decode attachments
        var attachments: [EmailAttachment] = []
        if let attachmentsData = emailEntity.attachmentsData,
           let decodedAttachments = try? JSONDecoder().decode([EmailAttachment].self, from: attachmentsData) {
            attachments = decodedAttachments
        }
        
        // Decode labels
        var labels: [String] = []
        if let labelsData = emailEntity.labelsData,
           let decodedLabels = try? JSONDecoder().decode([String].self, from: labelsData) {
            labels = decodedLabels
        }
        
        return Email(
            id: gmailID,
            subject: subject,
            sender: sender,
            recipients: recipients,
            body: body,
            date: date,
            isRead: emailEntity.isRead,
            isImportant: emailEntity.isImportant,
            labels: labels,
            attachments: attachments,
            isPromotional: emailEntity.isPromotional,
            hasCalendarEvent: emailEntity.hasCalendarEvent
        )
    }
    
    // MARK: - Cleanup Management
    
    func cleanupOldEmails() {
        let backgroundContext = self.backgroundContext
        
        backgroundContext.perform {
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            
            let request: NSFetchRequest<EmailEntity> = EmailEntity.fetchRequest()
            request.predicate = NSPredicate(format: "date < %@", thirtyDaysAgo as NSDate)
            
            do {
                let oldEmails = try backgroundContext.fetch(request)
                let deleteCount = oldEmails.count
                
                for email in oldEmails {
                    backgroundContext.delete(email)
                }
                
                self.saveBackground(backgroundContext)
                ProductionLogger.logCoreDataEvent("Cleaned up \(deleteCount) old emails")
                
            } catch {
                ProductionLogger.logError(error as NSError, context: "Core Data cleanup old emails")
            }
        }
    }
    
    func getStorageSize() -> Int64 {
        guard let url = persistentContainer.persistentStoreDescriptions.first?.url else { return 0 }
        
        do {
            let fileAttributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let fileSize = fileAttributes[FileAttributeKey.size] as? Int64 {
                return fileSize
            }
        } catch {
            ProductionLogger.logError(error as NSError, context: "Core Data storage size calculation")
        }
        
        return 0
    }
    
    func enforceStorageLimit() {
        let maxSize: Int64 = 100 * 1024 * 1024 // 100MB
        let currentSize = getStorageSize()
        
        ProductionLogger.logCoreDataEvent("Current storage size: \(currentSize / 1024 / 1024)MB")
        
        if currentSize > maxSize {
            let backgroundContext = self.backgroundContext
            
            backgroundContext.perform {
                // Delete oldest emails beyond the 30-day window
                let request: NSFetchRequest<EmailEntity> = EmailEntity.fetchRequest()
                request.sortDescriptors = [NSSortDescriptor(keyPath: \EmailEntity.date, ascending: true)]
                request.fetchLimit = 1000
                
                do {
                    let oldestEmails = try backgroundContext.fetch(request)
                    let deleteCount = min(500, oldestEmails.count) // Delete in batches
                    
                    for i in 0..<deleteCount {
                        backgroundContext.delete(oldestEmails[i])
                    }
                    
                    self.saveBackground(backgroundContext)
                    ProductionLogger.logCoreDataEvent("Enforced storage limit: deleted \(deleteCount) emails")
                    
                } catch {
                    ProductionLogger.logError(error as NSError, context: "Core Data storage limit enforcement")
                }
            }
        }
    }
    
    // MARK: - Sync Status Management
    
    func updateSyncStatus(type: String, date: Date, for user: UserEntity) {
        let context = viewContext
        
        // Ensure we operate on the same context instance for both sides of the relationship
        guard let userInContext = try? context.existingObject(with: user.objectID) as? UserEntity else {
            ProductionLogger.logError(NSError(domain: "CoreDataManager", code: -10, userInfo: [NSLocalizedDescriptionKey: "User not found in viewContext for sync update"]), context: "updateSyncStatus")
            return
        }
        
        let request: NSFetchRequest<SyncStatusEntity> = SyncStatusEntity.fetchRequest()
        request.predicate = NSPredicate(format: "user == %@ AND syncType == %@", userInContext, type)
        
        do {
            let existingSyncStatuses = try context.fetch(request)
            let syncStatus: SyncStatusEntity
            
            if let existing = existingSyncStatuses.first {
                syncStatus = existing
            } else {
                syncStatus = SyncStatusEntity(context: context)
                // Safely set the ID using KVC
                syncStatus.setValue(UUID(), forKey: "id")
                syncStatus.syncType = type
                
                // Validate userInContext before setting relationship
                if !userInContext.isDeleted && userInContext.managedObjectContext == context {
                    syncStatus.user = userInContext
                } else {
                    ProductionLogger.logError(
                        NSError(domain: "CoreDataManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "Cannot set sync status user relationship - invalid user state"]), 
                        context: "updateSyncStatus"
                    )
                    context.delete(syncStatus)
                    return
                }
            }
            
            syncStatus.lastSyncDate = date
            save()
            
        } catch {
            ProductionLogger.logError(error as NSError, context: "Core Data sync status update")
        }
    }
    
    func getLastSyncDate(type: String, for user: UserEntity) -> Date? {
        let context = viewContext
        
        let request: NSFetchRequest<SyncStatusEntity> = SyncStatusEntity.fetchRequest()
        request.predicate = NSPredicate(format: "user == %@ AND syncType == %@", user, type)
        request.fetchLimit = 1
        
        do {
            let syncStatuses = try context.fetch(request)
            return syncStatuses.first?.lastSyncDate
        } catch {
            ProductionLogger.logError(error as NSError, context: "Core Data get last sync date")
            return nil
        }
    }
    
    // MARK: - Store Management
    
    private func clearPersistentStore(_ container: NSPersistentContainer) {
        guard let storeURL = container.persistentStoreDescriptions.first?.url else { return }
        
        do {
            // Remove the existing store files
            if FileManager.default.fileExists(atPath: storeURL.path) {
                try FileManager.default.removeItem(at: storeURL)
            }
            
            // Remove additional SQLite files
            let shmURL = storeURL.appendingPathExtension("shm")
            let walURL = storeURL.appendingPathExtension("wal")
            
            if FileManager.default.fileExists(atPath: shmURL.path) {
                try FileManager.default.removeItem(at: shmURL)
            }
            
            if FileManager.default.fileExists(atPath: walURL.path) {
                try FileManager.default.removeItem(at: walURL)
            }
            
            ProductionLogger.logCoreDataEvent("Cleared persistent store due to migration issues")
            
        } catch {
            ProductionLogger.logError(error as NSError, context: "Core Data store clearing")
        }
    }
    
    // MARK: - Notifications
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contextDidSave),
            name: .NSManagedObjectContextDidSave,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }
    
    @objc private func contextDidSave(_ notification: Notification) {
        guard let context = notification.object as? NSManagedObjectContext else { return }
        
        if context !== viewContext {
            DispatchQueue.main.async {
                self.viewContext.mergeChanges(fromContextDidSave: notification)
            }
        }
    }
    
    @objc private func applicationWillTerminate(_ notification: Notification) {
        save()
    }
    
    @objc private func applicationDidEnterBackground(_ notification: Notification) {
        save()
    }
    
    // MARK: - Relationship Validation
    
    private func validateUserRelationships(_ userEntity: UserEntity, in context: NSManagedObjectContext) {
        // Check emails relationship for invalid objects
        if let emailsSet = userEntity.emails as? Set<EmailEntity> {
            let invalidEmails = emailsSet.filter { email in
                email.isDeleted || email.managedObjectContext == nil || email.managedObjectContext != context
            }
            
            if !invalidEmails.isEmpty {
                ProductionLogger.logError(
                    NSError(domain: "CoreDataManager", code: -7, userInfo: [NSLocalizedDescriptionKey: "Found \(invalidEmails.count) invalid emails in user relationship"]), 
                    context: "validateUserRelationships emails"
                )
                
                // Remove invalid emails from the relationship
                for invalidEmail in invalidEmails {
                    userEntity.removeFromEmails(invalidEmail)
                }
            }
        }
        
        // Check sync statuses relationship for invalid objects  
        if let syncStatusSet = userEntity.syncStatuses as? Set<SyncStatusEntity> {
            let invalidStatuses = syncStatusSet.filter { status in
                status.isDeleted || status.managedObjectContext == nil || status.managedObjectContext != context
            }
            
            if !invalidStatuses.isEmpty {
                ProductionLogger.logError(
                    NSError(domain: "CoreDataManager", code: -8, userInfo: [NSLocalizedDescriptionKey: "Found \(invalidStatuses.count) invalid sync statuses in user relationship"]), 
                    context: "validateUserRelationships syncStatuses"
                )
                
                // Remove invalid sync statuses from the relationship
                for invalidStatus in invalidStatuses {
                    userEntity.removeFromSyncStatuses(invalidStatus)
                }
            }
        }
        
        // Check categories relationship for invalid objects
        if let categoriesSet = userEntity.categories as? Set<CategoryEntity> {
            let invalidCategories = categoriesSet.filter { category in
                category.isDeleted || category.managedObjectContext == nil || category.managedObjectContext != context
            }
            
            if !invalidCategories.isEmpty {
                ProductionLogger.logError(
                    NSError(domain: "CoreDataManager", code: -9, userInfo: [NSLocalizedDescriptionKey: "Found \(invalidCategories.count) invalid categories in user relationship"]), 
                    context: "validateUserRelationships categories"
                )
                
                // Remove invalid categories from the relationship
                for invalidCategory in invalidCategories {
                    userEntity.removeFromCategories(invalidCategory)
                }
            }
        }
    }
}

// MARK: - Email Category Enum

enum EmailCategory {
    case all
    case unread
    case important
    case promotional
    case calendar
    
}

// MARK: - Production Logger Extension

extension ProductionLogger {
    static func logCoreDataEvent(_ message: String) {
        #if DEBUG
        print("📦 Core Data: \(message)")
        #endif
    }
}