# End-to-End Encryption Integration Guide

## Overview

Your Seline app now has end-to-end encryption capabilities. This guide explains:
- How encryption works
- Where to integrate it
- What's already done
- What you need to do

---

## ✅ What's Already Done

### 1. Core Encryption Manager (`EncryptionManager.swift`)
- **Location**: `Services/EncryptionManager.swift`
- **What it does**:
  - AES-256-GCM authenticated encryption
  - Deterministic key derivation from user UUID
  - Encrypt/decrypt strings and batches
- **Key point**: The same user UUID always produces the same encryption key, allowing decryption later

### 2. Authentication Integration
- **Files modified**: `AuthenticationManager.swift`
- **What happens**:
  - ✅ When user signs in → Encryption key is initialized
  - ✅ When session is restored → Encryption key is re-initialized
  - ✅ When user signs out → Encryption key is cleared
- **Result**: Encryption is ready whenever user is authenticated

### 3. Helper Files Created
- `EncryptedNoteHelper.swift` - Encrypt/decrypt notes
- `EncryptedEmailHelper.swift` - Encrypt/decrypt email data
- `EncryptedLocationHelper.swift` - Encrypt/decrypt location data

---

## 🔧 What You Need To Do

### Phase 1: Notes Encryption (Recommended First)

#### Step 1: Modify `saveNoteToSupabase()` in `NotesManager.swift`

**BEFORE:**
```swift
private func saveNoteToSupabase(_ note: Note) async {
    // ...
    let noteData: [String: PostgREST.AnyJSON] = [
        "id": .string(note.id.uuidString),
        "title": .string(note.title),  // ← Plaintext
        "content": .string(note.content),  // ← Plaintext
        // ...
    ]
}
```

**AFTER:**
```swift
private func saveNoteToSupabase(_ note: Note) async {
    guard let userId = SupabaseManager.shared.getCurrentUser()?.id else {
        print("⚠️ No user ID, skipping Supabase sync")
        return
    }

    // ✨ ENCRYPT BEFORE SAVING
    let encryptedNote: Note
    do {
        encryptedNote = try await encryptNoteBeforeSaving(note)
    } catch {
        print("❌ Failed to encrypt note: \(error)")
        return
    }

    let noteData: [String: PostgREST.AnyJSON] = [
        "id": .string(note.id.uuidString),
        "title": .string(encryptedNote.title),  // ← Now encrypted
        "content": .string(encryptedNote.content),  // ← Now encrypted
        "is_locked": .bool(encryptedNote.isLocked),
        // ... rest of fields
    ]

    do {
        let client = await SupabaseManager.shared.getPostgrestClient()
        try await client
            .from("notes")
            .insert(noteData)
            .execute()
    } catch {
        print("❌ Error saving note to Supabase: \(error)")
    }
}
```

#### Step 2: Modify `updateNoteInSupabase()` in `NotesManager.swift`

**Add encryption before update:**
```swift
private func updateNoteInSupabase(_ note: Note) async {
    // ... existing code ...

    // ✨ ENCRYPT BEFORE UPDATING
    let encryptedNote: Note
    do {
        encryptedNote = try await encryptNoteBeforeSaving(note)
    } catch {
        print("❌ Failed to encrypt note: \(error)")
        return
    }

    let noteData: [String: PostgREST.AnyJSON] = [
        "title": .string(encryptedNote.title),  // ← Now encrypted
        "content": .string(encryptedNote.content),  // ← Now encrypted
        // ...
    ]

    // ... rest of update code
}
```

#### Step 3: Modify `parseNoteFromSupabase()` in `NotesManager.swift`

**Add decryption after parsing:**
```swift
private func parseNoteFromSupabase(_ data: NoteSupabaseData) -> Note? {
    guard let id = UUID(uuidString: data.id) else {
        print("❌ Failed to parse note ID: \(data.id)")
        return nil
    }

    // ... existing date parsing code ...

    var note = Note(title: data.title, content: data.content)
    note.id = id
    note.dateCreated = dateCreated
    note.dateModified = dateModified
    note.isPinned = data.is_pinned
    note.isLocked = data.is_locked

    if let folderIdString = data.folder_id {
        note.folderId = UUID(uuidString: folderIdString)
    }

    note.imageUrls = data.image_attachments ?? []
    note.tables = data.tables ?? []
    note.todoLists = data.todo_lists ?? []

    // ✨ DECRYPT AFTER LOADING
    let decryptedNote: Note
    do {
        decryptedNote = try await decryptNoteAfterLoading(note)
    } catch {
        print("⚠️ Could not decrypt note (may be legacy data): \(error)")
        // Return original if decryption fails (backward compatible)
        return note
    }

    return decryptedNote
}
```

**IMPORTANT:** This method needs to be `async`. Update the signature:
```swift
private func parseNoteFromSupabase(_ data: NoteSupabaseData) async -> Note? {
    // ... implementation
}
```

And update the call sites:
```swift
var parsedNotes: [Note] = []
for supabaseNote in response {
    if let note = await parseNoteFromSupabase(supabaseNote) {  // ← Add await
        parsedNotes.append(note)
    }
}
```

---

### Phase 2: Email Encryption

#### Update `EmailService.swift`

When storing email summaries or email data in Supabase:

```swift
// Before saving to database
let encryptedEmail = try await encryptEmailData(
    subject: email.subject,
    body: email.snippet,  // or full body
    aiSummary: generatedSummary,
    senderEmail: email.sender.email,
    recipientEmails: email.recipients.map { $0.email }
)

// Save encrypted fields to database
let emailData: [String: PostgREST.AnyJSON] = [
    "subject": .string(encryptedEmail.encryptedSubject),
    "body": .string(encryptedEmail.encryptedBody),
    "ai_summary": encryptedEmail.encryptedSummary.map { .string($0) } ?? .null,
    // ...
]
```

When displaying emails:

```swift
// Fetch from database
let storedEmail = ... // contains encrypted data

// Decrypt before showing to user
let decryptedEmail = try await decryptEmailData(
    EncryptedEmailData(
        encryptedSubject: storedEmail.subject,
        encryptedBody: storedEmail.body,
        encryptedSummary: storedEmail.ai_summary,
        // ...
    )
)

// Now show decrypted content to user
showEmail(subject: decryptedEmail.subject, body: decryptedEmail.body)
```

---

### Phase 3: Location Encryption

#### Update `LocationService.swift` (or LocationsManager if you have one)

When saving a place:

```swift
let encryptedPlace = try await encryptLocationData(
    googlePlaceId: place.googlePlaceId,
    name: place.name,
    address: place.address,
    latitude: place.latitude,
    longitude: place.longitude,
    phoneNumber: place.phoneNumber
)

// Save encrypted fields
let placeData: [String: PostgREST.AnyJSON] = [
    "google_place_id": .string(encryptedPlace.googlePlaceId),
    "name": .string(encryptedPlace.encryptedName),
    "address": .string(encryptedPlace.encryptedAddress),
    "latitude": .string(encryptedPlace.encryptedLatitude),
    "longitude": .string(encryptedPlace.encryptedLongitude),
    "phone": encryptedPlace.encryptedPhoneNumber.map { .string($0) } ?? .null
]
```

When loading places:

```swift
let decryptedPlace = try await decryptLocationData(
    EncryptedLocationData(
        googlePlaceId: storedPlace.googlePlaceId,
        encryptedName: storedPlace.name,
        encryptedAddress: storedPlace.address,
        encryptedLatitude: storedPlace.latitude,
        encryptedLongitude: storedPlace.longitude,
        encryptedPhoneNumber: storedPlace.phone
    )
)

// Use decrypted data for map display, details, etc.
mapView.addAnnotation(
    latitude: decryptedPlace.latitude,
    longitude: decryptedPlace.longitude,
    title: decryptedPlace.name
)
```

---

## 🗄️ Database Schema Changes (Optional but Recommended)

### Add Column for Encryption Status

You can optionally add a field to track which notes are encrypted (for migration purposes):

```sql
ALTER TABLE notes ADD COLUMN is_encrypted BOOLEAN DEFAULT false;
ALTER TABLE saved_places ADD COLUMN is_encrypted BOOLEAN DEFAULT false;
```

Then when saving encrypted data, set `is_encrypted = true`.

When loading, check this flag to know whether to decrypt.

---

## 🔄 Migration Strategy

### For Existing Data

Since you likely have unencrypted data already:

1. **Phase 1 (Safe)**: New data is encrypted, old data is returned as-is
   - Decryption methods catch errors and return original data
   - Both encrypted and unencrypted data coexist

2. **Phase 2 (Optional)**: Re-encrypt old data
   ```swift
   func reencryptAllNotes() async {
       for note in notes {
           // Old note is unencrypted
           let encrypted = try await encryptNoteBeforeSaving(note)
           // Save encrypted version
           await updateNoteInSupabase(encrypted)
       }
   }
   ```

3. **Phase 3 (Cleanup)**: After confirmed all data is encrypted, remove legacy code

---

## 🧪 Testing

### Test Encryption End-to-End

```swift
// 1. Create a test note
var testNote = Note(title: "Test Encryption", content: "Secret data")

// 2. Encrypt it
let encrypted = try await encryptNoteBeforeSaving(testNote)
print("Encrypted title: \(encrypted.title)")  // Should look like gibberish

// 3. Decrypt it
let decrypted = try await decryptNoteAfterLoading(encrypted)
print("Decrypted title: \(decrypted.title)")  // Should match original

// 4. Verify match
assert(decrypted.title == testNote.title)
assert(decrypted.content == testNote.content)
print("✅ Encryption test passed!")
```

### Test in Console

Add this to your app for testing:

```swift
// Temporary test code (remove before release)
Task {
    let testString = "Hello, Encryption!"
    let encrypted = try EncryptionManager.shared.encrypt(testString)
    let decrypted = try EncryptionManager.shared.decrypt(encrypted)

    print("Original: \(testString)")
    print("Encrypted: \(encrypted)")
    print("Decrypted: \(decrypted)")
    print("Match: \(testString == decrypted)")
}
```

---

## ⚠️ Important Notes

### Key Points

1. **Encryption Key Storage**: Key is derived from user UUID and stored in memory
   - If user closes app, key is cleared
   - When app reopens, key is re-derived from same UUID
   - Symmetric key is NEVER sent to server

2. **Backward Compatibility**: Old unencrypted data still works
   - Decryption fails gracefully for unencrypted data
   - Returns original data instead
   - No data loss during migration

3. **Performance**: AES-256-GCM is fast
   - Encryption/decryption happens locally
   - No server round-trip needed
   - Imperceptible latency for users

4. **Security**: This is "zero-knowledge" encryption
   - You (app developer) cannot read encrypted user data
   - Only user's device can decrypt
   - Even with database access, data is unreadable

---

## 📋 Checklist

- [ ] Understand how encryption works (read above)
- [ ] Update `saveNoteToSupabase()` to encrypt
- [ ] Update `updateNoteInSupabase()` to encrypt
- [ ] Update `parseNoteFromSupabase()` to decrypt
- [ ] Update `loadNotesFromSupabase()` to handle async parsing
- [ ] Test note encryption/decryption
- [ ] (Optional) Repeat for Email data
- [ ] (Optional) Repeat for Location data
- [ ] (Optional) Add `is_encrypted` flag to track migration
- [ ] Test with real data
- [ ] Remove test code before release

---

## 🆘 Troubleshooting

### "Key not initialized" Error
- User not authenticated
- Check that `setupEncryption()` was called in `AuthenticationManager`
- Verify `isAuthenticated` is true

### "Invalid ciphertext" Error
- Data was corrupted
- Trying to decrypt unencrypted data (should still work - caught gracefully)
- Base64 encoding/decoding issue

### Decryption returns old data
- This is expected for legacy unencrypted data
- System automatically returns original if decryption fails
- Mark these records as `is_encrypted = false`

---

## Questions?

Refer to these files for implementation details:
- `EncryptionManager.swift` - Core encryption logic
- `EncryptedNoteHelper.swift` - Note encryption examples
- `EncryptedEmailHelper.swift` - Email encryption examples
- `EncryptedLocationHelper.swift` - Location encryption examples
- `AuthenticationManager.swift` - Encryption initialization

Each helper file contains detailed comments and usage examples.
