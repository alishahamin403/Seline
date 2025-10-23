# Re-encrypt Existing Data Guide

## The Problem

Your Supabase database has **existing unencrypted notes** that need to be secured with encryption.

- ❌ Old notes: Plaintext in Supabase (vulnerable)
- ✅ New notes: Automatically encrypted

This guide shows how to encrypt all existing data.

---

## Solution: Bulk Re-encryption Function

A new function has been added to `NotesManager.swift`:

```swift
func reencryptAllExistingNotes() async
```

This function:
1. ✅ Fetches all your unencrypted notes from Supabase
2. ✅ Encrypts each one using AES-256-GCM
3. ✅ Updates Supabase with encrypted versions
4. ✅ Skips notes that are already encrypted
5. ✅ Provides detailed progress and summary

---

## How to Use

### Option 1: Run During Testing
Add this to your app temporarily (e.g., in a debug view or on first launch):

```swift
// In your view or app delegate
Task {
    await NotesManager.shared.reencryptAllExistingNotes()
}
```

Watch the console output as it encrypts notes one by one.

### Option 2: Run During Development
Call it from Xcode's console:

```swift
Task {
    await NotesManager.shared.reencryptAllExistingNotes()
}
```

### Option 3: Add Debug Menu Button
Create a temporary button in your settings for testing:

```swift
Button("🔐 Re-encrypt Existing Data") {
    Task {
        await NotesManager.shared.reencryptAllExistingNotes()
    }
}
```

---

## What Happens

### Console Output

```
🔐 Starting bulk re-encryption of existing notes...
📥 Fetched 5 notes for re-encryption
🔐 Note 1/5: Re-encrypted - 'My First Note'
🔐 Note 2/5: Re-encrypted - 'Meeting Notes'
✅ Note 3/5: Already encrypted - 'Shopping List'
🔐 Note 4/5: Re-encrypted - 'To-Do Items'
🔐 Note 5/5: Re-encrypted - 'Budget Planning'

============================================================
🔐 BULK RE-ENCRYPTION COMPLETE
============================================================
✅ Re-encrypted: 4 notes
✅ Already encrypted: 1 note
❌ Errors: 0 notes
📊 Total: 5 notes processed
============================================================

✨ All 4 plaintext notes have been encrypted!
   Your data is now protected with end-to-end encryption.
```

---

## What Gets Encrypted

- ✅ Note title
- ✅ Note content
- ❌ Images (already encrypted by Supabase Storage)
- ❌ Timestamps (not sensitive)
- ❌ Note metadata (pinned, locked status)

---

## Safety Features

### 1. Detection
- Automatically detects if a note is already encrypted
- Skips encrypted notes (won't double-encrypt)

### 2. Error Handling
- Individual note failures don't stop the process
- Error count tracked in summary
- Detailed error messages in console

### 3. Idempotent
- Can be run multiple times safely
- Already encrypted notes are skipped
- No data loss possible

---

## Before & After

### Before Encryption
```sql
SELECT title, content FROM notes WHERE user_id = '...' LIMIT 1;

title: "My Secret Note"
content: "This is private information"
```

### After Encryption
```sql
SELECT title, content FROM notes WHERE user_id = '...' LIMIT 1;

title: "aG9Y+3k2lmN9qPxR8sTu5vWxYz+aB1cDeFgHiJkLmN"
content: "xK8mP9qR2sT3uV4wX5yZ6aA7bB8cC9dD0eE1fF2gG"
```

(Only decryptable by user's device with their encryption key)

---

## When to Run

### Recommended: First Login After Update
```swift
// In AuthenticationManager.swift after successful sign-in
await NotesManager.shared.reencryptAllExistingNotes()
```

### Or: Manual Triggering
Users manually trigger re-encryption from settings menu.

### Or: Gradual (No Action Needed)
- As users edit notes → notes get encrypted automatically
- Takes time but transparent to users

---

## Monitoring Progress

Check the console to see:
- Current note being processed
- Total progress (X/Y)
- Which notes were skipped (already encrypted)
- Which notes failed (with error messages)
- Final summary with counts

---

## Troubleshooting

### "User not authenticated"
- Make sure user is logged in
- Function requires active Supabase session

### "Error updating note in Supabase"
- Check network connection
- Check Supabase is running
- Check that user has write permissions

### "Failed to encrypt" errors
- Check EncryptionManager is initialized
- Check encryption key was setup on login
- See console for specific error message

---

## After Re-encryption

Once all existing data is encrypted:

1. ✅ Old notes are protected
2. ✅ New notes are protected
3. ✅ All users' data is encrypted
4. ✅ You can enable this in production

---

## Optional: Add Tracking Column

To track which notes have been encrypted, add to Supabase:

```sql
ALTER TABLE notes ADD COLUMN is_encrypted BOOLEAN DEFAULT false;
```

Then update the re-encryption function to set this flag when saving.

---

## Complete Example

Add this to your app's initialization:

```swift
// In SelineApp.swift or your app delegate
.onAppear {
    Task {
        // Re-encrypt any existing unencrypted notes
        await NotesManager.shared.reencryptAllExistingNotes()
    }
}
```

Or add a button for manual triggering:

```swift
// In Settings view
Button(action: {
    Task {
        await NotesManager.shared.reencryptAllExistingNotes()
    }
}) {
    Label("Secure Existing Data", systemImage: "lock.shield")
}
```

---

## Summary

- ✅ Function created: `reencryptAllExistingNotes()`
- ✅ Automatically detects encrypted vs plaintext
- ✅ Encrypts all plaintext notes one by one
- ✅ Provides detailed progress in console
- ✅ Safe to run multiple times
- ✅ Ready to deploy to production

**Just call it once to secure all your existing data!** 🔐
