import Foundation
import SwiftUI
import PostgREST

// MARK: - People Manager

class PeopleManager: ObservableObject {
    static let shared = PeopleManager()
    
    @Published var people: [Person] = []
    @Published var isLoading = false
    @Published var relationshipTypes: Set<RelationshipType> = []
    
    // Cache for visit-people connections
    private var visitPeopleCache: [UUID: [UUID]] = [:] // visitId -> [personId]
    private var receiptPeopleCache: [UUID: [UUID]] = [:] // noteId -> [personId]
    
    private let peopleKey = "SavedPeople"
    private let authManager = AuthenticationManager.shared
    
    private init() {
        loadPeopleFromStorage()
    }
    
    // MARK: - Data Persistence (Local Storage)
    
    private func savePeopleToStorage() {
        if let encoded = try? JSONEncoder().encode(people) {
            UserDefaults.standard.set(encoded, forKey: peopleKey)
        }
        
        // Update relationship types set
        relationshipTypes = Set(people.map { $0.relationship })
    }
    
    private func loadPeopleFromStorage() {
        if let data = UserDefaults.standard.data(forKey: peopleKey),
           let decodedPeople = try? JSONDecoder().decode([Person].self, from: data) {
            self.people = decodedPeople
            self.relationshipTypes = Set(decodedPeople.map { $0.relationship })
        }
    }
    
    // MARK: - CRUD Operations
    
    func addPerson(_ person: Person) {
        // Update on main thread for immediate UI refresh
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.people.append(person)
            self.savePeopleToStorage()
        }
        
        // Sync with Supabase
        Task {
            await savePersonToSupabase(person)
        }
    }
    
    func updatePerson(_ person: Person) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let index = self.people.firstIndex(where: { $0.id == person.id }) {
                var updatedPerson = person
                updatedPerson.dateModified = Date()
                self.people[index] = updatedPerson
                self.savePeopleToStorage()
            }
        }
        
        // Sync with Supabase
        Task {
            await updatePersonInSupabase(person)
        }
    }
    
    func deletePerson(_ person: Person) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.people.removeAll { $0.id == person.id }
            self.savePeopleToStorage()
            
            // Clear from caches
            self.visitPeopleCache = self.visitPeopleCache.mapValues { $0.filter { $0 != person.id } }
            self.receiptPeopleCache = self.receiptPeopleCache.mapValues { $0.filter { $0 != person.id } }
        }
        
        // Sync with Supabase
        Task {
            await deletePersonFromSupabase(person.id)
        }
    }
    
    // MARK: - Query Methods
    
    func getPerson(by id: UUID) -> Person? {
        return people.first { $0.id == id }
    }
    
    func getPeople(by relationship: RelationshipType) -> [Person] {
        return people.filter { $0.relationship == relationship }
            .sorted { $0.name < $1.name }
    }
    
    func getPeopleGroupedByRelationship() -> [(relationship: RelationshipType, people: [Person])] {
        let grouped = Dictionary(grouping: people) { $0.relationship }
        return RelationshipType.allCases
            .filter { grouped[$0] != nil && !grouped[$0]!.isEmpty }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { (relationship: $0, people: grouped[$0]!.sorted { $0.name < $1.name }) }
    }
    
    func searchPeople(query: String) -> [Person] {
        if query.isEmpty {
            return people.sorted { $0.name < $1.name }
        }
        
        let lowercasedQuery = query.lowercased()
        return people.filter { person in
            person.name.lowercased().contains(lowercasedQuery) ||
            (person.nickname?.lowercased().contains(lowercasedQuery) ?? false) ||
            person.relationshipDisplayText.lowercased().contains(lowercasedQuery) ||
            (person.notes?.lowercased().contains(lowercasedQuery) ?? false)
        }.sorted { $0.name < $1.name }
    }
    
    func getFavourites() -> [Person] {
        return people.filter { $0.isFavourite }
            .sorted { $0.name < $1.name }
    }
    
    func toggleFavourite(for personId: UUID) {
        if let index = people.firstIndex(where: { $0.id == personId }) {
            people[index].isFavourite.toggle()
            people[index].dateModified = Date()
            savePeopleToStorage()
            
            // Sync with Supabase
            Task {
                await updatePersonInSupabase(people[index])
            }
        }
    }
    
    // MARK: - Visit-People Connections
    
    func linkPeopleToVisit(visitId: UUID, personIds: [UUID]) async {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("⚠️ No user ID, skipping visit-people sync")
            return
        }
        
        // Ensure all persons exist in Supabase before linking (fixes FK violation when only stored locally)
        await ensurePeopleExistInSupabase(personIds: personIds, userId: userId)
        
        // Update local cache
        await MainActor.run {
            visitPeopleCache[visitId] = personIds
        }
        
        // First, delete existing connections for this visit
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("location_visit_people")
                .delete()
                .eq("visit_id", value: visitId.uuidString)
                .execute()
        } catch {
            print("❌ Error clearing visit-people connections: \(error)")
        }
        
        // Then insert new connections
        for personId in personIds {
            let connection = VisitPersonConnection(visitId: visitId, personId: personId)
            
            let data: [String: PostgREST.AnyJSON] = [
                "id": .string(connection.id.uuidString),
                "visit_id": .string(visitId.uuidString),
                "person_id": .string(personId.uuidString),
                "created_at": .string(ISO8601DateFormatter().string(from: connection.createdAt))
            ]
            
            do {
                let client = await SupabaseManager.shared.getPostgrestClient()
                try await client
                    .from("location_visit_people")
                    .insert(data)
                    .execute()
                print("✅ Linked person \(personId) to visit \(visitId)")
            } catch {
                print("❌ Error linking person to visit: \(error)")
            }
        }
    }
    
    /// Ensures each person exists in Supabase (upsert). Call before linking to visits to avoid FK violations.
    private func ensurePeopleExistInSupabase(personIds: [UUID], userId: UUID) async {
        for personId in personIds {
            guard let person = await MainActor.run(body: { self.getPerson(by: personId) }) else {
                print("⚠️ Skipping link: person \(personId) not found locally")
                continue
            }
            let data = person.toSupabaseData(userId: userId)
            do {
                let client = await SupabaseManager.shared.getPostgrestClient()
                try await client
                    .from("people")
                    .upsert(data, onConflict: "id")
                    .execute()
            } catch {
                print("❌ Failed to ensure person in Supabase \(person.name): \(error)")
            }
        }
    }
    
    func getPeopleForVisit(visitId: UUID) async -> [Person] {
        // Check cache first
        if let cachedIds = visitPeopleCache[visitId] {
            return cachedIds.compactMap { getPerson(by: $0) }
        }
        
        // Load from Supabase
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response: [VisitPersonSupabaseData] = try await client
                .from("location_visit_people")
                .select()
                .eq("visit_id", value: visitId.uuidString)
                .execute()
                .value
            
            let personIds = response.compactMap { UUID(uuidString: $0.person_id) }
            
            // Update cache
            await MainActor.run {
                visitPeopleCache[visitId] = personIds
            }
            
            return personIds.compactMap { getPerson(by: $0) }
        } catch {
            print("❌ Error loading people for visit: \(error)")
            return []
        }
    }
    
    func getVisitIdsForPerson(personId: UUID) async -> [UUID] {
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response: [VisitPersonSupabaseData] = try await client
                .from("location_visit_people")
                .select()
                .eq("person_id", value: personId.uuidString)
                .execute()
                .value
            
            return response.compactMap { UUID(uuidString: $0.visit_id) }
        } catch {
            print("❌ Error loading visits for person: \(error)")
            return []
        }
    }
    
    // MARK: - Receipt-People Connections
    
    func linkPeopleToReceipt(noteId: UUID, personIds: [UUID]) async {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("⚠️ No user ID, skipping receipt-people sync")
            return
        }
        
        // Ensure all persons exist in Supabase before linking (fixes FK violation when only stored locally)
        await ensurePeopleExistInSupabase(personIds: personIds, userId: userId)
        
        // Update local cache
        await MainActor.run {
            receiptPeopleCache[noteId] = personIds
        }
        
        // First, delete existing connections for this receipt
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("receipt_people")
                .delete()
                .eq("note_id", value: noteId.uuidString)
                .execute()
        } catch {
            print("❌ Error clearing receipt-people connections: \(error)")
        }
        
        // Then insert new connections
        for personId in personIds {
            let connection = ReceiptPersonConnection(noteId: noteId, personId: personId)
            
            let data: [String: PostgREST.AnyJSON] = [
                "id": .string(connection.id.uuidString),
                "note_id": .string(noteId.uuidString),
                "person_id": .string(personId.uuidString),
                "created_at": .string(ISO8601DateFormatter().string(from: connection.createdAt))
            ]
            
            do {
                let client = await SupabaseManager.shared.getPostgrestClient()
                try await client
                    .from("receipt_people")
                    .insert(data)
                    .execute()
                print("✅ Linked person \(personId) to receipt \(noteId)")
            } catch {
                print("❌ Error linking person to receipt: \(error)")
            }
        }
    }
    
    func getPeopleForReceipt(noteId: UUID) async -> [Person] {
        // Check cache first
        if let cachedIds = receiptPeopleCache[noteId] {
            return cachedIds.compactMap { getPerson(by: $0) }
        }
        
        // Load from Supabase
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response: [ReceiptPersonSupabaseData] = try await client
                .from("receipt_people")
                .select()
                .eq("note_id", value: noteId.uuidString)
                .execute()
                .value
            
            let personIds = response.compactMap { UUID(uuidString: $0.person_id) }
            
            // Update cache
            await MainActor.run {
                receiptPeopleCache[noteId] = personIds
            }
            
            return personIds.compactMap { getPerson(by: $0) }
        } catch {
            print("❌ Error loading people for receipt: \(error)")
            return []
        }
    }
    
    func getReceiptIdsForPerson(personId: UUID) async -> [UUID] {
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response: [ReceiptPersonSupabaseData] = try await client
                .from("receipt_people")
                .select()
                .eq("person_id", value: personId.uuidString)
                .execute()
                .value
            
            return response.compactMap { UUID(uuidString: $0.note_id) }
        } catch {
            print("❌ Error loading receipts for person: \(error)")
            return []
        }
    }
    
    // MARK: - Favourite Places Management
    
    func addFavouritePlace(personId: UUID, placeId: UUID) async {
        let connection = PersonFavouritePlace(personId: personId, placeId: placeId)
        
        let data: [String: PostgREST.AnyJSON] = [
            "id": .string(connection.id.uuidString),
            "person_id": .string(personId.uuidString),
            "place_id": .string(placeId.uuidString),
            "created_at": .string(ISO8601DateFormatter().string(from: connection.createdAt))
        ]
        
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("person_favourite_places")
                .insert(data)
                .execute()
            print("✅ Added favourite place \(placeId) for person \(personId)")
            
            // Update local person object
            await MainActor.run {
                if let index = people.firstIndex(where: { $0.id == personId }) {
                    if people[index].favouritePlaceIds == nil {
                        people[index].favouritePlaceIds = []
                    }
                    people[index].favouritePlaceIds?.append(placeId)
                    savePeopleToStorage()
                }
            }
        } catch {
            print("❌ Error adding favourite place: \(error)")
        }
    }
    
    func removeFavouritePlace(personId: UUID, placeId: UUID) async {
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("person_favourite_places")
                .delete()
                .eq("person_id", value: personId.uuidString)
                .eq("place_id", value: placeId.uuidString)
                .execute()
            print("✅ Removed favourite place \(placeId) for person \(personId)")
            
            // Update local person object
            await MainActor.run {
                if let index = people.firstIndex(where: { $0.id == personId }) {
                    people[index].favouritePlaceIds?.removeAll { $0 == placeId }
                    savePeopleToStorage()
                }
            }
        } catch {
            print("❌ Error removing favourite place: \(error)")
        }
    }
    
    func getFavouritePlacesForPerson(personId: UUID) async -> [UUID] {
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response: [PersonFavouritePlaceSupabaseData] = try await client
                .from("person_favourite_places")
                .select()
                .eq("person_id", value: personId.uuidString)
                .execute()
                .value
            
            return response.compactMap { UUID(uuidString: $0.place_id) }
        } catch {
            print("❌ Error loading favourite places for person: \(error)")
            return []
        }
    }
    
    // MARK: - Person Relationships (Person-to-Person Links)
    
    func linkPeople(personId: UUID, relatedPersonId: UUID, relationshipLabel: String) async {
        let link = PersonLink(personId: personId, relatedPersonId: relatedPersonId, relationshipLabel: relationshipLabel)
        
        let data: [String: PostgREST.AnyJSON] = [
            "id": .string(link.id.uuidString),
            "person_id": .string(personId.uuidString),
            "related_person_id": .string(relatedPersonId.uuidString),
            "relationship_label": .string(relationshipLabel),
            "created_at": .string(ISO8601DateFormatter().string(from: link.createdAt))
        ]
        
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("person_relationships")
                .insert(data)
                .execute()
            print("✅ Linked person \(personId) to \(relatedPersonId) as '\(relationshipLabel)'")
            
            // Update local person object
            await MainActor.run {
                if let index = people.firstIndex(where: { $0.id == personId }) {
                    if people[index].linkedPeople == nil {
                        people[index].linkedPeople = []
                    }
                    people[index].linkedPeople?.append(link)
                    savePeopleToStorage()
                }
            }
        } catch {
            print("❌ Error linking people: \(error)")
        }
    }
    
    func unlinkPeople(personId: UUID, relatedPersonId: UUID) async {
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("person_relationships")
                .delete()
                .eq("person_id", value: personId.uuidString)
                .eq("related_person_id", value: relatedPersonId.uuidString)
                .execute()
            print("✅ Unlinked person \(personId) from \(relatedPersonId)")
            
            // Update local person object
            await MainActor.run {
                if let index = people.firstIndex(where: { $0.id == personId }) {
                    people[index].linkedPeople?.removeAll { $0.relatedPersonId == relatedPersonId }
                    savePeopleToStorage()
                }
            }
        } catch {
            print("❌ Error unlinking people: \(error)")
        }
    }
    
    func getRelatedPeople(for personId: UUID) async -> [PersonLink] {
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response: [PersonLinkSupabaseData] = try await client
                .from("person_relationships")
                .select()
                .eq("person_id", value: personId.uuidString)
                .execute()
                .value
            
            return response.compactMap { PersonLink(from: $0) }
        } catch {
            print("❌ Error loading related people: \(error)")
            return []
        }
    }
    
    // MARK: - Supabase Sync
    
    private func savePersonToSupabase(_ person: Person) async {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("⚠️ No user ID, skipping Supabase sync")
            return
        }
        
        print("💾 Saving person to Supabase - User ID: \(userId.uuidString), Person ID: \(person.id.uuidString)")
        
        let data = person.toSupabaseData(userId: userId)
        
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("people")
                .insert(data)
                .execute()
            print("✅ Person saved to Supabase: \(person.name)")
        } catch {
            print("❌ Error saving person to Supabase: \(error)")
        }
    }
    
    private func updatePersonInSupabase(_ person: Person) async {
        guard SupabaseManager.shared.getCurrentUser() != nil else {
            print("⚠️ No user ID, skipping Supabase sync")
            return
        }
        
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else { return }
        
        var data = person.toSupabaseData(userId: userId)
        // Remove id and user_id from update data
        data.removeValue(forKey: "id")
        data.removeValue(forKey: "user_id")
        data.removeValue(forKey: "date_created")
        
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("people")
                .update(data)
                .eq("id", value: person.id.uuidString)
                .execute()
            print("✅ Person updated in Supabase: \(person.name)")
        } catch {
            print("❌ Error updating person in Supabase: \(error)")
        }
    }
    
    private func deletePersonFromSupabase(_ personId: UUID) async {
        guard SupabaseManager.shared.getCurrentUser() != nil else {
            print("⚠️ No user ID, skipping Supabase sync")
            return
        }
        
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            try await client
                .from("people")
                .delete()
                .eq("id", value: personId.uuidString)
                .execute()
            print("✅ Person deleted from Supabase: \(personId)")
        } catch {
            print("❌ Error deleting person from Supabase: \(error)")
        }
    }
    
    func loadPeopleFromSupabase() async {
        let isAuthenticated = await MainActor.run { authManager.isAuthenticated }
        let userId = await MainActor.run { authManager.supabaseUser?.id }
        
        guard isAuthenticated, let userId = userId else {
            print("User not authenticated, loading local people only")
            return
        }
        
        print("📥 Loading people from Supabase for user: \(userId.uuidString)")
        
        await MainActor.run {
            isLoading = true
        }
        
        do {
            let client = await SupabaseManager.shared.getPostgrestClient()
            let response: [PersonSupabaseData] = try await client
                .from("people")
                .select()
                .eq("user_id", value: userId.uuidString)
                .execute()
                .value
            
            print("📥 Received \(response.count) people from Supabase")
            
            var parsedPeople: [Person] = []
            for supabasePerson in response {
                if let person = Person(from: supabasePerson) {
                    parsedPeople.append(person)
                }
            }
            
            // Load relationships for each person
            for i in 0..<parsedPeople.count {
                let links = await getRelatedPeople(for: parsedPeople[i].id)
                parsedPeople[i].linkedPeople = links
                
                let favPlaces = await getFavouritePlacesForPerson(personId: parsedPeople[i].id)
                parsedPeople[i].favouritePlaceIds = favPlaces
            }
            
            await MainActor.run {
                if !parsedPeople.isEmpty {
                    self.people = parsedPeople
                    self.relationshipTypes = Set(parsedPeople.map { $0.relationship })
                    savePeopleToStorage()
                } else if response.isEmpty {
                    print("ℹ️ No people in Supabase, keeping \(self.people.count) local people")
                } else {
                    print("⚠️ Failed to parse any people from Supabase, keeping \(self.people.count) local people")
                }
                isLoading = false
            }
        } catch {
            print("❌ Error loading people from Supabase: \(error)")
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    func syncPeopleOnLogin() async {
        await loadPeopleFromSupabase()
    }
    
    // MARK: - Clear Data on Logout
    
    func clearPeopleOnLogout() {
        people = []
        relationshipTypes = []
        visitPeopleCache = [:]
        receiptPeopleCache = [:]
        
        // Clear UserDefaults
        UserDefaults.standard.removeObject(forKey: peopleKey)
        
        print("🗑️ Cleared all people data on logout")
    }
    
    // MARK: - Statistics
    
    func getRecentVisitsWithPerson(personId: UUID, limit: Int = 5) async -> [UUID] {
        let visitIds = await getVisitIdsForPerson(personId: personId)
        return Array(visitIds.prefix(limit))
    }
    
    func getTotalVisitCount(personId: UUID) async -> Int {
        let visitIds = await getVisitIdsForPerson(personId: personId)
        return visitIds.count
    }
    
    func getTotalReceiptCount(personId: UUID) async -> Int {
        let receiptIds = await getReceiptIdsForPerson(personId: personId)
        return receiptIds.count
    }
}
