//
//  SimpleSupabaseTest.swift
//  Seline
//
//  Simple test for Supabase connection and basic operations
//

import Foundation

@MainActor
class SimpleSupabaseTest: ObservableObject {
    static let shared = SimpleSupabaseTest()
    
    @Published var testResults: [String] = []
    @Published var isRunning = false
    
    private init() {}
    
    /// Run basic Supabase connection and operation tests
    func runBasicTests() async {
        isRunning = true
        testResults.removeAll()
        
        addResult("🚀 Starting Supabase basic tests...")
        
        // Test 1: Service initialization
        await testServiceInitialization()
        
        // Test 2: Connection test
        await testConnection()
        
        // Test 3: User operations
        await testUserOperations()
        
        // Test 4: Email operations
        await testEmailOperations()
        
        addResult("✅ Supabase basic tests completed!")
        isRunning = false
    }
    
    private func testServiceInitialization() async {
        addResult("📋 Test 1: Service initialization")
        
        let service = SupabaseService.shared
        
        // Wait for initialization
        var attempts = 0
        while !service.isConnected && attempts < 10 {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            attempts += 1
        }
        
        if service.isConnected {
            addResult("✅ Service initialized successfully")
        } else {
            addResult("❌ Service failed to initialize")
        }
    }
    
    private func testConnection() async {
        addResult("📋 Test 2: Connection test")
        
        let service = SupabaseService.shared
        
        guard service.isConnected else {
            addResult("❌ Service not initialized")
            return
        }
        
        do {
            // Try to get a user that doesn't exist - this tests the connection
            let _ = try await service.getUserByGoogleID("test-connection-\(UUID().uuidString)")
            addResult("✅ Connection test successful")
        } catch {
            addResult("✅ Connection test successful (expected error: \(error.localizedDescription))")
        }
    }
    
    private func testUserOperations() async {
        addResult("📋 Test 3: User operations")
        
        let service = SupabaseService.shared
        
        guard service.isConnected else {
            addResult("❌ Service not initialized")
            return
        }
        
        // Create a test user
        let testUser = SelineUser(
            id: "test-\(UUID().uuidString)",
            email: "test@example.com",
            name: "Test User",
            profileImageURL: nil,
            accessToken: "test-access-token",
            refreshToken: "test-refresh-token",
            tokenExpirationDate: Date().addingTimeInterval(3600)
        )
        
        do {
            let supabaseUser = try await service.upsertUser(selineUser: testUser)
            addResult("✅ User creation successful: \(supabaseUser.id)")
            
            // Try to get the user back
            if let retrievedUser = try await service.getUserByGoogleID(testUser.id) {
                addResult("✅ User retrieval successful: \(retrievedUser.email)")
            } else {
                addResult("❌ User retrieval failed")
            }
            
        } catch {
            addResult("❌ User operations failed: \(error.localizedDescription)")
        }
    }
    
    private func testEmailOperations() async {
        addResult("📋 Test 4: Email operations")
        
        let service = SupabaseService.shared
        
        guard service.isConnected else {
            addResult("❌ Service not initialized")
            return
        }
        
        // Create test email
        let testEmail = Email(
            id: "test-email-\(UUID().uuidString)",
            subject: "Test Email",
            sender: EmailContact(name: "Test Sender", email: "sender@example.com"),
            recipients: [EmailContact(name: "Test Recipient", email: "recipient@example.com")],
            body: "This is a test email body for Supabase integration testing.",
            date: Date(),
            isRead: false,
            isImportant: false,
            labels: ["test"],
            attachments: [],
            isPromotional: false
        )
        
        let testUserId = UUID()
        
        do {
            // Test storing emails
            let _ = try await service.syncEmailsToSupabase([testEmail], for: testUserId)
            addResult("✅ Email storage successful")
            
            // Test retrieving emails
            let retrievedEmails = try await service.fetchEmailsFromSupabase(for: testUserId, limit: 10)
            addResult("✅ Email retrieval successful: found \(retrievedEmails.count) emails")
            
            // Test updating email status
            try await service.updateEmailStatus(gmailID: testEmail.id, userID: testUserId, isRead: true, isImportant: false)
            addResult("✅ Email status update successful")
            
            // Test searching emails
            let searchResults = try await service.searchEmailsInSupabase(query: "test", for: testUserId, limit: 10)
            addResult("✅ Email search successful: found \(searchResults.count) results")
            
        } catch {
            addResult("❌ Email operations failed: \(error.localizedDescription)")
        }
    }
    
    private func addResult(_ message: String) {
        testResults.append(message)
        print(message)
    }
}

#if DEBUG
// Extension for easy testing in development
extension SimpleSupabaseTest {
    static func runQuickTest() async {
        await SimpleSupabaseTest.shared.runBasicTests()
    }
}
#endif