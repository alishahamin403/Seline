import Foundation
import Auth
import PostgREST
import Storage

class SupabaseManager: ObservableObject {
    static let shared = SupabaseManager()

    let authClient: AuthClient
    private let supabaseURL: URL
    private let supabaseKey: String

    private init() {
        // Your Supabase project details
        self.supabaseURL = URL(string: "https://rtiacmeeqkihzhgosvjn.supabase.co")!
        self.supabaseKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ0aWFjbWVlcWtpaHpoZ29zdmpuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTc5ODk3MTMsImV4cCI6MjA3MzU2NTcxM30.dwv0Og-lxjP8W3YSTxk6mdj9Oy7AYhqwwLZ61FjIcfI"

        // Initialize Auth client with default localStorage
        self.authClient = AuthClient(
            url: supabaseURL.appendingPathComponent("/auth/v1"),
            headers: ["apikey": supabaseKey, "Authorization": "Bearer \(supabaseKey)"],
            localStorage: KeychainLocalStorage(),
            logger: nil
        )

        // PostgREST client is now created dynamically with current auth token
    }

    func getPostgrestClient() async -> PostgrestClient {
        let token: String
        if authClient.currentUser != nil {
            do {
                let session = try await authClient.session
                token = session.accessToken
            } catch {
                print("Failed to get session, using anon key: \(error)")
                token = supabaseKey
            }
        } else {
            token = supabaseKey
        }

        return PostgrestClient(
            url: supabaseURL.appendingPathComponent("/rest/v1"),
            headers: ["apikey": supabaseKey, "Authorization": "Bearer \(token)"],
            logger: nil
        )
    }

    func signInWithGoogleIdToken(_ idToken: String, accessToken: String, nonce: String?) async throws -> User {
        let credentials = OpenIDConnectCredentials(
            provider: .google,
            idToken: idToken,
            accessToken: accessToken,
            nonce: nonce
        )

        let session = try await authClient.signInWithIdToken(credentials: credentials)
        return session.user
    }

    func createOrUpdateUserProfile(user: User, email: String?, name: String?) async throws {
        do {
            let client = await getPostgrestClient()

            // First, check if profile exists
            let _ = try await client
                .from("user_profiles")
                .select("id")
                .eq("id", value: user.id.uuidString)
                .execute()

            // If no profile exists, the trigger should have created it
            // Let's try updating with the latest info
            let userProfile: [String: AnyJSON] = [
                "email": AnyJSON.string(email ?? ""),
                "full_name": AnyJSON.string(name ?? ""),
                "updated_at": AnyJSON.string(ISO8601DateFormatter().string(from: Date()))
            ]

            try await client
                .from("user_profiles")
                .update(userProfile)
                .eq("id", value: user.id.uuidString)
                .execute()

        } catch {
            print("❌ Profile operation failed: \(error)")
            // Profile might not exist, trigger might not have fired
            // This is okay - the user is still authenticated
        }
    }

    func getCurrentUser() -> User? {
        return authClient.currentUser
    }

    func signOut() async throws {
        try await authClient.signOut()
    }

    func getStorageClient() async -> SupabaseStorageClient {
        let token: String
        if authClient.currentUser != nil {
            do {
                let session = try await authClient.session
                token = session.accessToken
            } catch {
                print("❌ Failed to get session: \(error)")
                token = supabaseKey
            }
        } else {
            token = supabaseKey
        }

        let configuration = StorageClientConfiguration(
            url: supabaseURL.appendingPathComponent("/storage/v1"),
            headers: ["apikey": supabaseKey, "Authorization": "Bearer \(token)"],
            logger: nil
        )

        return SupabaseStorageClient(configuration: configuration)
    }

    // Upload image to Supabase Storage
    func uploadImage(_ imageData: Data, fileName: String, userId: UUID) async throws -> String {
        // Verify user is authenticated
        guard let currentUser = authClient.currentUser else {
            throw NSError(domain: "SupabaseManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }

        // Verify the userId matches the current user
        guard currentUser.id == userId else {
            throw NSError(domain: "SupabaseManager", code: 403, userInfo: [NSLocalizedDescriptionKey: "User ID mismatch"])
        }

        let storage = await getStorageClient()
        let path = "\(userId.uuidString)/\(fileName)"

        // Upload with optimized cache headers for CDN caching
        // Cache-Control: max-age=31536000 (1 year), immutable
        // This dramatically reduces cached egress by enabling browser + CDN caching
        try await storage
            .from("note-images")
            .upload(
                path,
                data: imageData,
                options: FileOptions(
                    cacheControl: "public, max-age=31536000, immutable",
                    contentType: "image/jpeg",
                    upsert: true
                )
            )

        // Return the public URL
        let publicURL = try await storage
            .from("note-images")
            .getPublicURL(path: path)

        return publicURL.absoluteString
    }

    // MARK: - User Location Preferences

    func saveLocationPreferences(_ preferences: UserLocationPreferences) async throws {
        guard let userId = getCurrentUser()?.id else {
            throw NSError(domain: "SupabaseManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }

        let client = await getPostgrestClient()
        let preferencesData: [String: PostgREST.AnyJSON] = [
            "location1_address": preferences.location1Address != nil ? .string(preferences.location1Address!) : .null,
            "location1_latitude": preferences.location1Latitude != nil ? .double(preferences.location1Latitude!) : .null,
            "location1_longitude": preferences.location1Longitude != nil ? .double(preferences.location1Longitude!) : .null,
            "location1_icon": preferences.location1Icon != nil ? .string(preferences.location1Icon!) : .null,
            "location2_address": preferences.location2Address != nil ? .string(preferences.location2Address!) : .null,
            "location2_latitude": preferences.location2Latitude != nil ? .double(preferences.location2Latitude!) : .null,
            "location2_longitude": preferences.location2Longitude != nil ? .double(preferences.location2Longitude!) : .null,
            "location2_icon": preferences.location2Icon != nil ? .string(preferences.location2Icon!) : .null,
            "location3_address": preferences.location3Address != nil ? .string(preferences.location3Address!) : .null,
            "location3_latitude": preferences.location3Latitude != nil ? .double(preferences.location3Latitude!) : .null,
            "location3_longitude": preferences.location3Longitude != nil ? .double(preferences.location3Longitude!) : .null,
            "location3_icon": preferences.location3Icon != nil ? .string(preferences.location3Icon!) : .null,
            "is_first_time_setup": .bool(preferences.isFirstTimeSetup),
            "updated_at": .string(ISO8601DateFormatter().string(from: Date()))
        ]

        try await client
            .from("user_profiles")
            .update(preferencesData)
            .eq("id", value: userId.uuidString)
            .execute()
    }

    func loadLocationPreferences() async throws -> UserLocationPreferences {
        guard let userId = getCurrentUser()?.id else {
            throw NSError(domain: "SupabaseManager", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }

        let client = await getPostgrestClient()
        let response: [UserProfileSupabaseData] = try await client
            .from("user_profiles")
            .select()
            .eq("id", value: userId.uuidString)
            .execute()
            .value

        guard let profileData = response.first else {
            throw NSError(domain: "SupabaseManager", code: 404, userInfo: [NSLocalizedDescriptionKey: "User profile not found"])
        }

        return profileData.toLocationPreferences()
    }
}