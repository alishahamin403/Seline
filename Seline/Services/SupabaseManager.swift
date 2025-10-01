import Foundation
import Auth
import PostgREST

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
            let existingProfile = try await client
                .from("user_profiles")
                .select("id")
                .eq("id", value: user.id.uuidString)
                .execute()

            print("Profile check result: \(existingProfile)")

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

            print("✅ User profile updated: \(user.id)")

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
}