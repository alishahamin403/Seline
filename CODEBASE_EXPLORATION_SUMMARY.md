# Seline Codebase Exploration Report

## Executive Summary

**Seline** is a comprehensive iOS productivity application built with SwiftUI that integrates emails, events, notes, locations, and weather. The project is currently using Gmail API for email management and Supabase as the backend database for notes, folders, and other persistent data.

---

## 1. Project Overview & Technology Stack

### Core Technology
- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI
- **Platform**: iOS 17.0+
- **Deployment Target**: iOS 17.0 or later

### Backend Services
- **Supabase**: PostgreSQL database + Storage
  - Used for: Notes, Folders, Tasks, Locations, Receipts, and metadata
  - Real-time subscriptions enabled
  - Row Level Security (RLS) for data protection
  - Encryption: End-to-end encryption for sensitive data (notes, content)
  
- **Gmail API**: Email management
  - OAuth2 authentication
  - Used to fetch inbox/sent emails
  - Email categorization (Primary, Social, Promotions, Updates, Forums)
  - AI summaries via GPT-4o-mini
  
- **OpenAI API**: AI processing
  - GPT-4o-mini: Email summaries and text enhancement
  - GPT-4o Vision: Receipt/document scanning

- **Google APIs**:
  - Google Maps API: Location search and details
  - Places API: Location information
  
- **Open-Meteo API**: Weather data

### Key Libraries
- **GoogleSignIn**: OAuth2 authentication
- **PostgREST**: Supabase database queries
- **Combine**: Reactive programming
- **URLSession**: Network requests
- **UserDefaults**: Local caching (for emails)
- **KeychainLocalStorage**: Secure token storage

---

## 2. Project Directory Structure

```
Seline/
├── Models/                          # Data structures
│   ├── EmailModels.swift           # Email, EmailAttachment, EmailFolder, EmailCategory
│   ├── AttachmentModels.swift      # Note attachments (for receipt scanning)
│   ├── NoteModels.swift            # Note, NoteFolder, DeletedNote, NotesManager
│   ├── EventModels.swift           # Event-related structures
│   ├── LocationModels.swift        # Location data models
│   ├── ReceiptStatsModels.swift    # Receipt statistics and categorization
│   ├── ConversationModels.swift    # Chat/conversation structures
│   ├── ConversationalActionModels.swift
│   ├── DataMetadataModels.swift
│   └── RecurringEventStat.swift
│
├── Services/                        # Business logic & API integrations
│   ├── GmailAPIClient.swift        # Gmail API wrapper (fetch, search, mark read/unread)
│   ├── EmailService.swift          # Email management (in-memory cache, search, filtering)
│   ├── SupabaseManager.swift       # Supabase database client
│   ├── EncryptionManager.swift     # End-to-end encryption (notes, content)
│   ├── EncryptedEmailHelper.swift  # Email encryption utilities
│   ├── EncryptedNoteHelper.swift   # Note encryption utilities
│   ├── EncryptedLocationHelper.swift
│   ├── EncryptedTaskHelper.swift
│   ├── EncryptedSavedPlaceHelper.swift
│   ├── OpenAIService.swift         # GPT-4o API integration
│   ├── LocationService.swift       # Location management
│   ├── WeatherService.swift        # Weather API integration
│   ├── NotificationService.swift   # Push notifications & badge management
│   ├── AuthenticationManager.swift # User authentication & session
│   ├── FeedbackService.swift       # Haptic feedback
│   ├── KeychainLocalStorage.swift  # Secure storage
│   ├── ConversationContextService.swift
│   ├── InteractiveEventBuilder.swift
│   ├── InteractiveNoteBuilder.swift
│   ├── ConversationActionHandler.swift
│   ├── QueryRouter.swift
│   ├── AppContextService.swift
│   ├── NotificationDelegate.swift
│   └── HapticManager.swift
│
├── Views/                           # SwiftUI Components
│   ├── EmailView.swift             # Main email interface (tabs, categories, filtering)
│   ├── EventsView.swift            # Calendar/events management
│   ├── NotesView.swift             # Notes interface with folder support
│   ├── MapsView.swift              # Google Maps integration
│   ├── RootView.swift              # App navigation root
│   ├── SelineApp.swift             # App entry point
│   └── Components/                 # Reusable UI components
│       ├── EmailListView.swift
│       ├── EmailListWithCategories.swift
│       ├── EmailDetailView.swift   # Email detail sheet
│       ├── EmailRow.swift          # Individual email row
│       ├── EmailTabView.swift      # Inbox/Sent tabs
│       ├── EmailSearchBar.swift
│       ├── EmailCategoryFilterView.swift
│       ├── EmailCategorySection.swift
│       ├── AttachmentRow.swift     # Email attachment display
│       ├── CompactSenderView.swift
│       ├── AISummaryCard.swift
│       ├── EmailActionButtons.swift
│       ├── AddEventFromEmailView.swift
│       ├── FolderPickerView.swift  # Note folder selection
│       ├── FolderSidebarView.swift # Folder sidebar (Notes)
│       ├── TrashView.swift         # Trash/deleted items
│       ├── RichTextEditor.swift    # Note editor
│       ├── SearchView.swift        # Global search
│       ├── FilePickerButton.swift
│       ├── FilePreviewSheet.swift
│       ├── CameraActionSheet.swift
│       ├── CameraPicker.swift
│       └── ... (70+ more components)
│
├── Utils/                           # Utility functions
│   ├── FontManager.swift
│   ├── GmailURLHelper.swift
│   ├── ShadcnColors.swift
│   ├── CurrencyParser.swift
│   ├── TimelineEventColorManager.swift
│   ├── ImageCacheManager.swift
│   ├── AttributedStringToMarkdown.swift
│   ├── SearchModels.swift
│   ├── HashUtils.swift
│   └── ... (extensions and helpers)
│
├── LLMArchitecture/                 # LLM integration (advanced)
│   └── ... (LLM processing logic)
│
├── Assets.xcassets/                 # Images, icons, colors
│
└── Config.swift                     # API configuration
```

---

## 3. Email Management System

### 3.1 Email Data Models

```swift
// Main Email Structure
struct Email: Identifiable, Codable, Equatable {
    let id: String                           // Unique identifier
    let threadId: String                     // Gmail thread ID
    let sender: EmailAddress                 // From address
    let recipients: [EmailAddress]           // To addresses
    let ccRecipients: [EmailAddress]         // CC addresses
    let subject: String
    let snippet: String                      // Preview text
    let body: String?                        // Full email body (HTML or plain text)
    let timestamp: Date
    let isRead: Bool
    let isImportant: Bool
    let hasAttachments: Bool                 // Flag indicating attachments exist
    let attachments: [EmailAttachment]       // Array of attachments
    let labels: [String]                     // Gmail labels
    let aiSummary: String?                   // Generated AI summary
    let gmailMessageId: String?              // Gmail API ID
    let gmailThreadId: String?               // Gmail API thread ID
}

// Attachment Structure
struct EmailAttachment: Identifiable, Codable, Equatable {
    let id: String                           // Unique attachment ID
    let name: String                         // File name
    let size: Int64                          // File size in bytes
    let mimeType: String                     // Content type (e.g., "application/pdf")
    let url: String?                         // Download URL (if available)
    
    // Computed properties
    var formattedSize: String                // Human-readable size
    var fileExtension: String                // File extension
    var isImage: Bool                        // Image type check
    var isPDF: Bool                          // PDF type check
    var systemIcon: String                   // SF Symbol icon
}

// Email Categorization
enum EmailCategory: String, CaseIterable {
    case primary = "Primary"
    case social = "Social"
    case promotions = "Promotions"
    case updates = "Updates"
    case forums = "Forums"
    
    var gmailLabel: String {
        // Maps to Gmail's native labels (CATEGORY_PRIMARY, etc.)
    }
}

// Email Folders
enum EmailFolder: String, CaseIterable {
    case inbox = "INBOX"
    case sent = "SENT"
    case drafts = "DRAFT"
    case trash = "TRASH"
    case spam = "SPAM"
}

// Time-based Categorization
enum TimePeriod: String, CaseIterable {
    case morning = "Morning"       // 12:00 AM - 11:59 AM
    case afternoon = "Afternoon"   // 12:00 PM - 4:59 PM
    case night = "Night"           // 5:00 PM - 11:59 PM
}
```

### 3.2 Email Storage & Caching

**Current Implementation**:
- **In-Memory Storage**: `EmailService` maintains `@Published` properties:
  - `inboxEmails: [Email]`
  - `sentEmails: [Email]`
  - `searchResults: [Email]`

- **Persistent Cache**: UserDefaults-based (7-day expiration)
  - Keys: `cached_inbox_emails`, `cached_sent_emails`, timestamps
  - Cache size: ~500KB-1MB typical
  - Used for offline availability

- **No Supabase Storage**: Emails are NOT stored in Supabase database
  - Reason: Gmail is the source of truth
  - Reduces storage costs and API quota usage

### 3.3 EmailService Architecture

```swift
@MainActor
class EmailService: ObservableObject {
    // Published properties for UI binding
    @Published var inboxEmails: [Email] = []
    @Published var sentEmails: [Email] = []
    @Published var searchResults: [Email] = []
    @Published var isSearching: Bool = false
    @Published var inboxLoadingState: EmailLoadingState = .idle
    @Published var sentLoadingState: EmailLoadingState = .idle
    
    // Cache management
    private var cacheTimestamps: [EmailFolder: Date] = [:]
    private let cacheExpirationTime: TimeInterval = 604800 // 7 days
    private let newEmailCheckInterval: TimeInterval = 60   // Check every minute
    
    // Key Methods:
    
    // Load emails for a folder (with cache validation)
    func loadEmailsForFolder(_ folder: EmailFolder, forceRefresh: Bool = false) async
    
    // Search emails (Gmail API or local fallback)
    func searchEmails(query: String) async
    
    // Refresh all emails
    func refreshEmails() async
    
    // Email actions
    func markAsRead(_ email: Email)
    func markAsUnread(_ email: Email)
    func deleteEmail(_ email: Email) async throws
    func replyToEmail(_ email: Email)
    func forwardEmail(_ email: Email)
    
    // Categorization
    func getCategorizedEmails(for folder: EmailFolder, category: EmailCategory?, unreadOnly: Bool) -> [EmailSection]
    func getFilteredEmails(for folder: EmailFolder, category: EmailCategory) -> [Email]
    
    // AI summaries
    func updateEmailWithAISummary(_ email: Email, summary: String) async
    private func preloadAISummaries(for emails: [Email]) async
}
```

### 3.4 Loading States

```swift
enum EmailLoadingState: Equatable {
    case idle                        // No active operation
    case loading                     // Fetching emails
    case loaded([Email])             // Successfully loaded
    case error(String)               // Error message
}
```

---

## 4. Attachment Handling (Current Implementation)

### 4.1 Email Attachment Display

**Current Status**: Attachments are DISPLAYED but NOT DOWNLOADABLE

- **Attachment Information**: Retrieved from Gmail API
  - Filename, size, MIME type, attachment ID
  - Displayed in `AttachmentRow` component
  - Show file type icon (PDF, document, image, archive)

- **Attachment Structure**:
  ```swift
  struct EmailAttachment {
      let id: String              // Gmail attachment ID
      let name: String            // Original filename
      let size: Int64             // File size
      let mimeType: String        // Content type
      let url: String?            // Download URL (currently unused)
  }
  ```

- **UI Components**:
  - `AttachmentRow.swift`: Displays attachment metadata
  - `FileChip.swift`: Compact attachment display
  - `FilePreviewSheet.swift`: File preview modal

### 4.2 Note Attachments (Different System)

**Note Attachments** for receipt scanning (NOT used for emails):
- Separate model: `NoteAttachment`
- Stored in Supabase as `attachments` table
- Used for document extraction (invoices, bank statements, receipts)
- Files uploaded to Supabase Storage

---

## 5. Current Emails Page Implementation

### 5.1 Email UI Architecture

**Main View Hierarchy**:
```
EmailView
├── Email Tab Selection (Inbox/Sent)
├── Unread Filter Button
├── Category Filter Slider (Primary/Social/Promotions/Updates/Forums)
└── EmailListWithCategories
    ├── ScrollView with RefreshControl
    └── ForEach EmailSection
        └── ForEach Email
            └── EmailRow
                ├── Sender Avatar
                ├── Subject
                ├── Preview Text
                ├── Timestamp
                ├── Unread Indicator
                ├── Attachment Indicator
                └── Actions (Mark as read, Delete)
```

### 5.2 Email Detail View

**Currently**: Full email view in sheet/modal
- Email header with sender info
- AI summary section
- Original email content (HTML rendering)
- Attachments section (metadata display only)
- Action buttons: Reply, Forward, Delete, Mark as Unread, Add Event

### 5.3 Features

- **Categorization**: 
  - Auto-categorization based on Gmail labels + heuristics
  - Time-based grouping (Morning/Afternoon/Night)
  - Collapsible sections

- **Filtering**:
  - By folder (Inbox/Sent/Draft/Trash/Spam)
  - By category (Primary/Social/etc.)
  - Unread only toggle
  - Full-text search (via Gmail API)

- **Actions**:
  - Mark as read/unread (synced to Gmail)
  - Delete (moves to trash in Gmail)
  - Reply/Forward (opens Gmail compose)
  - Create event from email
  - AI summary generation (on-demand or preloaded)

### 5.4 Search Implementation

```swift
func searchEmails(query: String) async {
    // Uses Gmail API search if available
    let emails = try await gmailAPIClient.searchEmails(query: query, maxResults: 15)
    
    // Fallback to local search if API fails
    let filteredEmails = allEmails.filter { email in
        email.subject.contains(query) ||
        email.sender.displayName.contains(query) ||
        email.snippet.contains(query)
    }
}
```

---

## 6. Folder Management (For Notes - Template for Emails)

### 6.1 Note Folder Structure

The app already has a proven folder management system for NOTES that can serve as a template for emails:

```swift
struct NoteFolder: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var color: String                    // Hex color
    var parentFolderId: UUID?            // Supports hierarchy/subfolders
}

// Hierarchy example:
// Receipts (root)
//   ├── 2024 (year folder)
//   │   ├── January (month folder)
//   │   ├── February
//   │   └── ...
//   └── 2023
//       └── ...
```

### 6.2 Folder Operations

- **Create**: Folder added locally and synced to Supabase
- **Update**: Name and color can be changed
- **Delete**: Moved to trash (soft delete), recovered within 30 days
- **Hierarchy**: Supports parent-child relationships
- **Supabase Storage**:
  ```sql
  folders (
      id UUID PRIMARY KEY,
      user_id UUID FOREIGN KEY,
      name VARCHAR,
      color VARCHAR,
      parent_folder_id UUID REFERENCES folders(id),
      created_at TIMESTAMP
  )
  ```

### 6.3 Folder Syncing

- **Async Operations**: `addFolderAndSync()` waits for Supabase confirmation
- **Retry Logic**: Exponential backoff (2s, 4s, 8s) for failed operations
- **Hierarchy Sorting**: Parents synced before children to avoid foreign key violations

---

## 7. Supabase Database Structure

### 7.1 Current Tables

The Supabase database is used for:

```sql
-- Notes
notes (
    id UUID PRIMARY KEY,
    user_id UUID,
    title TEXT ENCRYPTED,
    content TEXT ENCRYPTED,
    folder_id UUID REFERENCES folders(id),
    is_pinned BOOLEAN,
    is_locked BOOLEAN,
    image_attachments JSONB,      -- Array of image URLs
    created_at TIMESTAMP,
    updated_at TIMESTAMP
)

-- Note Folders
folders (
    id UUID PRIMARY KEY,
    user_id UUID,
    name VARCHAR,                  -- NOT encrypted (not sensitive)
    color VARCHAR,
    parent_folder_id UUID,
    created_at TIMESTAMP
)

-- Deleted Notes (Trash)
deleted_notes (
    id UUID,
    user_id UUID,
    title TEXT,
    content TEXT,
    folder_id UUID,
    deleted_at TIMESTAMP,
    ...
)

-- Attachments (for receipt scanning, NOT emails)
attachments (
    id UUID PRIMARY KEY,
    user_id UUID,
    note_id UUID,
    file_name VARCHAR,
    file_size INT,
    file_type VARCHAR,
    storage_path VARCHAR,
    document_type VARCHAR,         -- 'bank_statement', 'invoice', 'receipt'
    created_at TIMESTAMP
)

-- Extracted Data (receipt/invoice OCR results)
extracted_data (
    id UUID PRIMARY KEY,
    attachment_id UUID,
    document_type VARCHAR,
    extracted_fields JSONB,        -- Dynamic JSON based on type
    confidence DOUBLE,
    is_edited BOOLEAN,
    created_at TIMESTAMP
)

-- Other tables: events, tasks, locations, saved_places, etc.
```

### 7.2 Row Level Security (RLS)

All tables have RLS policies:
- Users can only read/write their own data (`user_id` filter)
- Prevents cross-user access
- Data isolation enforced at database level

### 7.3 Encryption

- **Encrypted Fields**: Note titles, note content
- **Plain Text Fields**: Folder names, email data
- **Encryption Method**: AES-256 via EncryptionManager
- **Key Storage**: Derived from user ID + device keychain

---

## 8. Recommendations for Email Folder Management

### 8.1 Implementation Approach

To add folder support to emails (similar to notes), follow this pattern:

#### Step 1: Extend Email Models
```swift
// Add folder_id to Email
struct Email: Identifiable, Codable {
    // ... existing fields ...
    let folderId: UUID?              // Custom email folder reference
}

// Create EmailFolder model
struct EmailFolder: Identifiable, Codable {
    let id: UUID
    var name: String
    var color: String
    var parentFolderId: UUID?
    var createdAt: Date
    var updatedAt: Date
}
```

#### Step 2: Create Email Folders Table in Supabase
```sql
CREATE TABLE email_folders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    name VARCHAR NOT NULL,
    color VARCHAR DEFAULT '#84cae9',
    parent_folder_id UUID REFERENCES email_folders(id),
    created_at TIMESTAMP DEFAULT now(),
    updated_at TIMESTAMP DEFAULT now(),
    
    CONSTRAINT folder_hierarchy CHECK (
        parent_folder_id IS NULL OR parent_folder_id != id
    )
);

-- Email folder associations
CREATE TABLE email_folder_associations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id),
    email_id VARCHAR NOT NULL,         -- Gmail message ID
    folder_id UUID REFERENCES email_folders(id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT now(),
    
    UNIQUE(user_id, email_id, folder_id)
);

-- RLS Policies
ALTER TABLE email_folders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users can manage their own email folders"
    ON email_folders
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());
```

#### Step 3: Extend EmailService
```swift
class EmailService: ObservableObject {
    @Published var emailFolders: [EmailFolder] = []
    
    // Folder operations
    func createEmailFolder(_ folder: EmailFolder) async throws
    func updateEmailFolder(_ folder: EmailFolder) async throws
    func deleteEmailFolder(_ folderId: UUID) async throws
    func moveEmailToFolder(_ email: Email, folder: EmailFolder) async throws
    func getEmailsInFolder(_ folderId: UUID) -> [Email]
    
    // Sync with Supabase
    private func loadEmailFoldersFromSupabase() async
    private func saveEmailFolderToSupabase(_ folder: EmailFolder) async
}
```

#### Step 4: Update EmailView UI
```swift
// Add sidebar or folder selection
EmailView
├── FolderSidebar (similar to notes)
│   ├── Default folders (Inbox, Sent, Draft, Trash)
│   ├── Custom folders
│   └── Folder actions (create, rename, delete)
├── Main content with selected folder's emails
└── Move to folder action in email detail
```

#### Step 5: Gmail Sync Strategy

```swift
// Two approaches:

// Approach A: Local-only folders (recommended)
// - Custom folders only exist in Supabase
// - Don't try to sync with Gmail's label system
// - Simpler, more flexible

// Approach B: Hybrid with Gmail labels
// - Allow marking emails with Gmail labels
// - Sync labels as custom folders
// - More complex but integrates with Gmail labels
```

### 8.2 Design Considerations

| Aspect | Recommendation | Rationale |
|--------|---|---|
| **Storage Location** | Supabase only | Don't store emails in Supabase (Gmail is source of truth) |
| **Folder Hierarchy** | Support parent/child | Allows organizing by sender, project, date, etc. |
| **Email Persistence** | Only associations stored | Reference by Gmail message ID + folder ID |
| **Default Folders** | Gmail native folders | INBOX, SENT, DRAFT, TRASH, SPAM (read-only from Gmail) |
| **Custom Folder Limit** | 50-100 folders | Reasonable for mobile, prevent over-organization |
| **Folder Colors** | Hex string (like notes) | Visual organization |
| **Trash Handling** | Keep Gmail trash sync | Respect Gmail's trash folder behavior |

### 8.3 Key Implementation Details

1. **Email Associations**: Store mapping of (email_id, folder_id) in Supabase, not duplicating emails
2. **Cache Strategy**: Cache email->folder mappings in memory, sync to Supabase asynchronously
3. **Offline Support**: Keep mappings in UserDefaults for offline access
4. **Search**: Extend search to filter by folder
5. **Sync Conflicts**: Last-write-wins if same email is in multiple folders
6. **Performance**: Use indexed queries on (user_id, folder_id)

---

## 9. Key Implementation Patterns in Codebase

### 9.1 Async/Await Pattern

```swift
// All major operations use async/await
func loadEmailsForFolder(_ folder: EmailFolder) async {
    // Network requests with error handling
    // Main thread updates via @MainActor
    // Proper task cancellation
}
```

### 9.2 @MainActor for UI Updates

```swift
@MainActor
class EmailService: ObservableObject {
    // All UI updates guaranteed on main thread
    @Published var inboxEmails: [Email] = []
}
```

### 9.3 Caching Strategy

```swift
// 1. Check cache validity
if !forceRefresh && isCacheValid(for: folder) && !getEmails(for: folder).isEmpty {
    setLoadingState(for: folder, state: .loaded(cachedEmails))
    return
}

// 2. Fetch from API
let emails = try await gmailAPIClient.fetchInboxEmails()

// 3. Merge with existing data (preserve AI summaries)
let mergedEmails = mergeWithExistingAISummaries(newEmails, existingEmails)

// 4. Save to cache
saveCachedData(for: folder)
```

### 9.4 Error Handling & Retry Logic

```swift
private func withRetry<T>(maxAttempts: Int = 2, operation: @escaping () async throws -> T) async throws -> T {
    for attempt in 1...maxAttempts {
        do {
            return try await operation()
        } catch let error as GmailAPIError {
            if statusCode == 401 && attempt < maxAttempts {
                try? await refreshAccessToken()
                continue
            }
            throw error
        }
    }
}
```

### 9.5 Encryption Integration

```swift
// All sensitive data encrypted before Supabase storage
let encryptedNote = try await encryptNoteBeforeSaving(note)

// Decrypted after loading from Supabase
let decryptedNote = try await decryptNoteAfterLoading(note)
```

---

## 10. Performance Considerations

### 10.1 Current Optimizations

1. **Lazy Loading**: Only load current folder's emails, not all folders
2. **Caching**: 7-day cache with validity checking
3. **AI Summary Preloading**: Background task preloads summaries
4. **Profile Picture Caching**: Avoids repeated API calls for avatars
5. **Pagination**: Gmail API requests limited to 10 emails per call (API quota friendly)
6. **Rate Limiting**: 1-minute interval for new email checks

### 10.2 Potential Bottlenecks

1. **Large Email Lists**: No pagination UI (all emails loaded at once)
   - Fix: Implement infinite scroll with pagination

2. **Full Text Search**: Falls back to local search if API fails
   - Fix: Implement proper search indexing in Supabase

3. **Attachment Processing**: No batching of attachment fetches
   - Fix: Queue attachment downloads with rate limiting

4. **Image Caching**: Uses in-memory cache for profile pictures
   - Fix: Persist to disk cache for persistent availability

---

## 11. Security Features

### 11.1 Current Security Measures

1. **Row Level Security (RLS)**: All Supabase tables protected
2. **OAuth2**: Secure Google authentication
3. **Secure Token Storage**: Access tokens in Keychain
4. **End-to-End Encryption**: Notes and sensitive data encrypted before transmission
5. **API Key Management**: Stored in Config.swift (not committed to git)

### 11.2 Missing Security Considerations for Emails

1. **Email Folder Access Control**: Need RLS policy verification
2. **Audit Logging**: No logging of email actions in Supabase
3. **Data Minimization**: Consider what email metadata is necessary to store
4. **Attachment Scanning**: No virus/malware scanning for attachments

---

## 12. File Organization Summary

### Critical Files

| File | Purpose | Lines |
|------|---------|-------|
| `EmailModels.swift` | Email data structures | ~600 |
| `EmailService.swift` | Email business logic | ~900 |
| `GmailAPIClient.swift` | Gmail API wrapper | ~800 |
| `EmailView.swift` | Main email UI | ~200+ |
| `EmailDetailView.swift` | Email detail modal | ~200+ |
| `NoteModels.swift` | Note folder system (template) | ~2100 |
| `SupabaseManager.swift` | Database client | Varies |
| `EncryptionManager.swift` | E2E encryption | Varies |

### Component Count
- **Total Swift Files**: 100+
- **Email-related Components**: ~15 views/components
- **Models**: 8 main model files
- **Services**: 20+ service classes

---

## 13. Conclusion & Next Steps

### Current State
- **Email Management**: Basic inbox/sent view with categorization and search
- **Attachments**: Displayed but not interactive (no download/preview)
- **Folder System**: NOT implemented for emails (only exists for notes)
- **Database**: Emails NOT persisted to Supabase (Gmail is source of truth)

### Recommended Implementation Priority

1. **Phase 1**: Folder UI & Local Storage
   - Add folder creation/editing UI
   - Store folder metadata in Supabase
   - Add folder selection in email detail

2. **Phase 2**: Email-Folder Associations
   - Create email_folder_associations table
   - Implement move-to-folder functionality
   - Add folder filtering in EmailView

3. **Phase 3**: Advanced Features
   - Folder hierarchy (subfolders)
   - Folder-based search
   - Folder color customization
   - Bulk operations (move multiple emails)

4. **Phase 4**: Attachment Management
   - Download support
   - Preview capability
   - Save to device
   - Share functionality

---

## Appendix: Key Constants & Limits

```swift
// Cache Configuration
cacheExpirationTime: 604800 seconds (7 days)
newEmailCheckInterval: 60 seconds (1 minute)
maxEmailsPerFetch: 10 (Gmail API call)
maxSearchResults: 15 (Gmail API search)

// UI Limits
maxFoldersPerView: ~50 (reasonable for mobile)
attachmentDisplayLimit: All (no truncation)
emailPreviewLength: 100 characters

// Performance
profilePictureCacheSize: ~100 entries (in-memory)
emailLoadingTimeout: 30 seconds per folder
tokenRefreshThreshold: 5 minutes before expiry
```

---

**Report Generated**: November 10, 2025
**Codebase Version**: Current main branch
**App Version**: iOS 17.0+
**Framework**: SwiftUI + Supabase + Gmail API
