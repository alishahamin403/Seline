//
//  UserEntity+Extensions.swift
//  Seline
//
//  Created by Alishah Amin on 2025-08-28.
//

import Foundation
import CoreData

extension UserEntity {
    
    // MARK: - Convenience Properties
    
    var isTokenExpired: Bool {
        guard let expirationDate = tokenExpirationDate else { return true }
        return Date() >= expirationDate
    }
    
    var emailsArray: [EmailEntity] {
        guard let emailsSet = emails as? Set<EmailEntity> else { return [] }
        // Filter out any nil or invalid objects that might have been added to the set
        let validEmails = emailsSet.compactMap { email -> EmailEntity? in
            guard !email.isDeleted, email.managedObjectContext != nil else { return nil }
            return email
        }
        return validEmails.sorted { $0.date ?? Date.distantPast > $1.date ?? Date.distantPast }
    }
    
    var categoriesArray: [CategoryEntity] {
        guard let categoriesSet = categories as? Set<CategoryEntity> else { return [] }
        // Filter out any nil or invalid objects that might have been added to the set
        let validCategories = categoriesSet.compactMap { category -> CategoryEntity? in
            guard !category.isDeleted, category.managedObjectContext != nil else { return nil }
            return category
        }
        return validCategories.sorted { $0.name ?? "" < $1.name ?? "" }
    }
    
    var syncStatusesArray: [SyncStatusEntity] {
        guard let syncStatusSet = syncStatuses as? Set<SyncStatusEntity> else { return [] }
        // Filter out any nil or invalid objects that might have been added to the set
        let validSyncStatuses = syncStatusSet.compactMap { status -> SyncStatusEntity? in
            guard !status.isDeleted, status.managedObjectContext != nil else { return nil }
            return status
        }
        return validSyncStatuses.sorted { $0.lastSyncDate ?? Date.distantPast > $1.lastSyncDate ?? Date.distantPast }
    }
    
    // MARK: - Custom Fetch Requests
    
    static func fetchRequestForEmail(_ email: String) -> NSFetchRequest<UserEntity> {
        let request = fetchRequest()
        request.predicate = NSPredicate(format: "email == %@", email)
        request.fetchLimit = 1
        return request
    }
    
    static func fetchCurrentUser() -> NSFetchRequest<UserEntity> {
        let request = fetchRequest()
        request.fetchLimit = 1
        request.sortDescriptors = [NSSortDescriptor(keyPath: \UserEntity.email, ascending: true)]
        return request
    }
    
    // MARK: - Conversion Methods
    
    func toSelineUser() -> SelineUser {
        // Avoid direct property access to 'id' to prevent unrecognized selector crashes
        let userID: String
        if let existing = value(forKey: "id") as? UUID {
            userID = existing.uuidString
        } else {
            // Create a new UUID and set it via KVC so the property exists going forward
            let newUUID = UUID()
            setValue(newUUID, forKey: "id")
            userID = newUUID.uuidString
            ProductionLogger.debug("Generated new UUID for UserEntity: \(userID)", category: "coredata")
        }
        
        return SelineUser(
            id: userID,
            email: email ?? "",
            name: name ?? "",
            profileImageURL: profileImageURL,
            accessToken: accessToken ?? "",
            refreshToken: refreshToken,
            tokenExpirationDate: tokenExpirationDate
        )
    }
    
    static func fromSelineUser(_ selineUser: SelineUser, context: NSManagedObjectContext) -> UserEntity {
        let userEntity = UserEntity(context: context)
        
        // Safely set the ID using KVC first to avoid selector mismatches
        let uuid = UUID(uuidString: selineUser.id) ?? UUID()
        userEntity.setValue(uuid, forKey: "id")
        
        userEntity.email = selineUser.email
        userEntity.name = selineUser.name
        userEntity.profileImageURL = selineUser.profileImageURL
        userEntity.accessToken = selineUser.accessToken
        userEntity.refreshToken = selineUser.refreshToken
        userEntity.tokenExpirationDate = selineUser.tokenExpirationDate
        return userEntity
    }
    
    // MARK: - Statistics
    
    var totalEmailCount: Int {
        return safeEmailCount()
    }
    
    private func safeEmailCount() -> Int {
        // Use a more defensive approach to access the relationship
        guard let managedObjectContext = managedObjectContext else { return 0 }
        
        let request: NSFetchRequest<EmailEntity> = EmailEntity.fetchRequest()
        request.predicate = NSPredicate(format: "user == %@", self)
        request.includesSubentities = false
        
        do {
            return try managedObjectContext.count(for: request)
        } catch {
            ProductionLogger.logError(error as NSError, context: "Safe email count")
            // Fallback to relationship access
            guard let emailsSet = emails as? Set<EmailEntity> else { return 0 }
            return emailsSet.count
        }
    }
    
    var unreadEmailCount: Int {
        return safeEmailCount(predicate: "isRead == NO")
    }
    
    var importantEmailCount: Int {
        return safeEmailCount(predicate: "isImportant == YES")
    }
    
    var promotionalEmailCount: Int {
        return safeEmailCount(predicate: "isPromotional == YES")
    }
    
    
    
    private func safeEmailCount(predicate: String) -> Int {
        guard let managedObjectContext = managedObjectContext else { return 0 }
        
        let request: NSFetchRequest<EmailEntity> = EmailEntity.fetchRequest()
        request.predicate = NSPredicate(format: "user == %@ AND \(predicate)", self)
        request.includesSubentities = false
        
        do {
            return try managedObjectContext.count(for: request)
        } catch {
            ProductionLogger.logError(error as NSError, context: "Safe email count with predicate: \(predicate)")
            // Fallback to relationship access
            guard let emailsSet = emails as? Set<EmailEntity> else { return 0 }
            
            switch predicate {
            case "isRead == NO":
                return emailsSet.filter { !$0.isRead }.count
            case "isImportant == YES":
                return emailsSet.filter { $0.isImportant }.count
            case "isPromotional == YES":
                return emailsSet.filter { $0.isPromotional }.count
            
            default:
                return emailsSet.count
            }
        }
    }
    
    // MARK: - Storage Management
    
    func getStorageUsage() -> Int64 {
        guard let emails = emails as? Set<EmailEntity> else { return 0 }
        
        var totalSize: Int64 = 0
        
        // Estimate size based on content length
        for email in emails {
            let subjectSize = Int64((email.subject?.count ?? 0) * 2) // UTF-16
            let bodySize = Int64((email.body?.count ?? 0) * 2)
            let senderSize = Int64(email.senderData?.count ?? 0)
            let recipientsSize = Int64(email.recipientsData?.count ?? 0)
            let attachmentsSize = Int64(email.attachmentsData?.count ?? 0)
            let labelsSize = Int64(email.labelsData?.count ?? 0)
            
            totalSize += subjectSize + bodySize + senderSize + recipientsSize + attachmentsSize + labelsSize
        }
        
        return totalSize
    }
    
    func shouldCleanupOldEmails() -> Bool {
        let maxSize: Int64 = 100 * 1024 * 1024 // 100MB
        return getStorageUsage() > maxSize
    }
    
    // MARK: - Sync Management
    
    func getLastSyncDate(for syncType: String) -> Date? {
        guard let syncStatusSet = syncStatuses as? Set<SyncStatusEntity> else { return nil }
        
        // Filter out any nil or invalid objects and find the matching sync type
        let validSyncStatuses = syncStatusSet.compactMap { status -> SyncStatusEntity? in
            guard !status.isDeleted, 
                  status.managedObjectContext != nil,
                  status.syncType == syncType else { return nil }
            return status
        }
        
        return validSyncStatuses.first?.lastSyncDate
    }
    
    func updateSyncDate(for syncType: String, date: Date, in context: NSManagedObjectContext) {
        // Ensure self is valid and has a context
        guard let selfContext = self.managedObjectContext,
              !self.isDeleted,
              self.objectID.isTemporaryID == false || selfContext.hasChanges else { 
            ProductionLogger.logError(
                NSError(domain: "UserEntity", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid UserEntity state for sync update"]), 
                context: "updateSyncDate"
            )
            return 
        }
        
        // Use the self's context to prevent cross-context issues
        let targetContext = selfContext
        
        let fetch: NSFetchRequest<SyncStatusEntity> = SyncStatusEntity.fetchRequest()
        fetch.predicate = NSPredicate(format: "user == %@ AND syncType == %@", self, syncType)
        fetch.fetchLimit = 1
        
        do {
            if let existing = try targetContext.fetch(fetch).first {
                existing.lastSyncDate = date
            } else {
                let status = SyncStatusEntity(context: targetContext)
                status.setValue(UUID(), forKey: "id")
                status.syncType = syncType
                status.lastSyncDate = date
                
                // Additional validation before setting relationship
                if !self.isDeleted && self.managedObjectContext == targetContext {
                    status.user = self
                } else {
                    ProductionLogger.logError(
                        NSError(domain: "UserEntity", code: -2, userInfo: [NSLocalizedDescriptionKey: "Cannot set user relationship - context mismatch or deleted object"]), 
                        context: "updateSyncDate relationship"
                    )
                    targetContext.delete(status) // Clean up the orphaned status object
                    return
                }
            }
        } catch {
            ProductionLogger.logError(error as NSError, context: "UserEntity updateSyncDate fetch")
        }
    }
}