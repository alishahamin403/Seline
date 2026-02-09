import Contacts
import Foundation

/// ContactsSyncService: Imports iPhone contacts into the People page
/// READ-ONLY: This service only reads from iPhone Contacts, never writes to them.
class ContactsSyncService {
    static let shared = ContactsSyncService()

    private let contactStore = CNContactStore()
    private let userDefaults = UserDefaults.standard

    // UserDefaults key for contact identifier -> Person ID mapping
    private let contactMappingKey = "ContactsSyncMapping"

    private init() {}

    // MARK: - Contacts Authorization

    /// Request access to the user's contacts
    func requestContactsAccess() async -> Bool {
        let status = CNContactStore.authorizationStatus(for: .contacts)

        switch status {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            do {
                let granted = try await contactStore.requestAccess(for: .contacts)
                return granted
            } catch {
                print("❌ Failed to request contacts access: \(error.localizedDescription)")
                return false
            }
        @unknown default:
            return false
        }
    }

    /// Check current authorization status without requesting
    func authorizationStatus() -> CNAuthorizationStatus {
        return CNContactStore.authorizationStatus(for: .contacts)
    }

    // MARK: - Contact Fetching (READ-ONLY)

    /// Fetch all contacts from the iPhone
    func fetchAllContacts() async -> [CNContact] {
        let hasAccess = await requestContactsAccess()
        guard hasAccess else {
            print("❌ Contacts access not granted")
            return []
        }

        let keysToFetch: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactNicknameKey as CNKeyDescriptor,
            CNContactBirthdayKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactPostalAddressesKey as CNKeyDescriptor,
            CNContactThumbnailImageDataKey as CNKeyDescriptor,
            CNContactOrganizationNameKey as CNKeyDescriptor,
            CNContactIdentifierKey as CNKeyDescriptor
        ]

        let request = CNContactFetchRequest(keysToFetch: keysToFetch)
        request.sortOrder = .givenName

        var contacts: [CNContact] = []

        do {
            try contactStore.enumerateContacts(with: request) { contact, _ in
                // Filter out contacts without a name
                let fullName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
                if !fullName.isEmpty || !contact.organizationName.isEmpty {
                    contacts.append(contact)
                }
            }
            print("📇 Fetched \(contacts.count) contacts from iPhone")
        } catch {
            print("❌ Error fetching contacts: \(error.localizedDescription)")
        }

        return contacts
    }

    // MARK: - Contact Conversion

    /// Convert a CNContact to a Person object
    func convertContactToPerson(_ contact: CNContact) -> Person {
        // Build name: givenName + familyName, fallback to organizationName
        let fullName = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
        let name = fullName.isEmpty ? contact.organizationName : fullName

        // Nickname
        let nickname: String? = contact.nickname.isEmpty ? nil : contact.nickname

        // Birthday
        var birthday: Date? = nil
        if let birthdayComponents = contact.birthday {
            birthday = Calendar.current.date(from: birthdayComponents)
        }

        // Phone (first number)
        let phone: String? = contact.phoneNumbers.first?.value.stringValue

        // Email (first address)
        let email: String? = contact.emailAddresses.first.map { $0.value as String }

        // Address (first postal address)
        var address: String? = nil
        if let postalAddress = contact.postalAddresses.first?.value {
            let formatted = CNPostalAddressFormatter.string(from: postalAddress, style: .mailingAddress)
            address = formatted.isEmpty ? nil : formatted
        }

        return Person(
            name: name,
            nickname: nickname,
            relationship: .friend,
            birthday: birthday,
            phone: phone,
            email: email,
            address: address,
            isFavourite: false
        )
    }

    // MARK: - Photo Upload

    /// Upload contact thumbnail to Supabase Storage
    /// Returns the public URL string, or nil if no photo or upload fails
    func uploadContactPhoto(_ imageData: Data, personId: UUID) async -> String? {
        guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
            print("⚠️ No user ID, skipping photo upload")
            return nil
        }

        do {
            let fileName = "person-\(personId.uuidString).jpg"
            let url = try await SupabaseManager.shared.uploadImage(imageData, fileName: fileName, userId: userId)
            return url
        } catch {
            print("❌ Error uploading contact photo: \(error)")
            return nil
        }
    }

    // MARK: - Deduplication Mapping

    /// Check if a contact has already been imported
    func isContactAlreadySynced(_ identifier: String) -> Bool {
        let mapping = getContactMapping()
        return mapping[identifier] != nil
    }

    /// Get the full contact identifier -> Person ID mapping
    func getContactMapping() -> [String: String] {
        return userDefaults.dictionary(forKey: contactMappingKey) as? [String: String] ?? [:]
    }

    /// Save a single contact -> person mapping entry
    func saveContactMappingEntry(contactIdentifier: String, personId: UUID) {
        var mapping = getContactMapping()
        mapping[contactIdentifier] = personId.uuidString
        userDefaults.set(mapping, forKey: contactMappingKey)
    }

    /// Save multiple mapping entries at once
    func saveContactMappingEntries(_ entries: [(contactIdentifier: String, personId: UUID)]) {
        var mapping = getContactMapping()
        for entry in entries {
            mapping[entry.contactIdentifier] = entry.personId.uuidString
        }
        userDefaults.set(mapping, forKey: contactMappingKey)
    }

    /// Clear all sync data (called on logout)
    func clearSyncData() {
        userDefaults.removeObject(forKey: contactMappingKey)
        print("🗑️ Cleared contacts sync mapping")
    }
}
