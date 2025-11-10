# Seline Architecture Quick Reference

## System Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    iOS App (SwiftUI)                        │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │  EmailView   │  │  NotesView   │  │  EventsView  │       │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘       │
│         │                 │                 │               │
│  ┌──────▼──────────────────▼─────────────────▼──────┐       │
│  │         Service Layer (@MainActor)               │       │
│  ├──────────────────────────────────────────────────┤       │
│  │ • EmailService          → Gmail + Cache          │       │
│  │ • NotesManager          → Supabase + Encryption  │       │
│  │ • EventManager          → Supabase               │       │
│  │ • LocationService       → Google Maps            │       │
│  │ • AuthenticationManager → Google OAuth           │       │
│  └──────┬─────────────────────┬──────────────┬──────┘       │
│         │                     │              │              │
└─────────┼─────────────────────┼──────────────┼──────────────┘
          │                     │              │
          ▼                     ▼              ▼
      Gmail API          Supabase DB      Google APIs
      (OAuth2)        (PostgreSQL+RLS)   (Maps, Auth)
```

## Email Data Flow

```
┌─────────────────────────────────────────────┐
│         EmailView                           │
│  ┌─────────────────────────────────────┐   │
│  │ 1. User opens Email tab             │   │
│  └──────────────────┬──────────────────┘   │
│                     │                       │
│                     ▼                       │
│  ┌─────────────────────────────────────┐   │
│  │ 2. Load from Cache (7-day TTL)      │   │
│  │    - Check validity                 │   │
│  │    - Show cached emails             │   │
│  └──────────────────┬──────────────────┘   │
│                     │                       │
│                     ▼                       │
│  ┌─────────────────────────────────────┐   │
│  │ 3. If cache invalid/expired         │   │
│  │    Call GmailAPIClient.fetch()      │   │
│  └──────────────────┬──────────────────┘   │
└─────────────────────┼─────────────────────┘
                      │
                      ▼
            ┌─────────────────────┐
            │   Gmail API         │
            │  (10 emails/req)    │
            │  Rate: 1/min check  │
            └────────┬────────────┘
                     │
                     ▼
            ┌─────────────────────┐
            │  Parse Emails       │
            │  • Extract metadata │
            │  • Build attachment │
            │  • Categorize       │
            └────────┬────────────┘
                     │
                     ▼
            ┌─────────────────────┐
            │  Cache in Memory    │
            │  Save to UserDefaults
            │  Preload AI summaries
            └────────┬────────────┘
                     │
                     ▼
            ┌─────────────────────┐
            │  Display in UI      │
            │  Grouped by:        │
            │  • Time (M/A/N)     │
            │  • Category         │
            │  • Read status      │
            └─────────────────────┘
```

## Email Models Hierarchy

```
Email (Main)
├── id: String (Gmail message ID)
├── threadId: String
├── sender: EmailAddress
│   ├── name: String?
│   ├── email: String
│   └── avatarUrl: String?
├── recipients: [EmailAddress]
├── ccRecipients: [EmailAddress]
├── subject: String
├── snippet: String (preview)
├── body: String? (full HTML)
├── timestamp: Date
├── isRead: Bool
├── isImportant: Bool
├── attachments: [EmailAttachment]
│   ├── id: String
│   ├── name: String
│   ├── size: Int64
│   ├── mimeType: String
│   └── url: String?
├── labels: [String] (Gmail labels)
├── aiSummary: String? (GPT-4o generated)
└── gmailMessageId: String

EmailCategory (enum)
├── .primary
├── .social
├── .promotions
├── .updates
└── .forums

TimePeriod (enum)
├── .morning (12AM-11:59AM)
├── .afternoon (12PM-4:59PM)
└── .night (5PM-11:59PM)

EmailSection
├── timePeriod: TimePeriod
├── emails: [Email]
└── isExpanded: Bool
```

## Notes Folder System (Template for Emails)

```
NoteFolder (Tree Structure)
├── id: UUID
├── name: String (plain text)
├── color: String (hex: "#84cae9")
├── parentFolderId: UUID? (null = root)
└── createdAt: Date

Example Hierarchy:
├── Receipts (root)
│   ├── 2024
│   │   ├── January
│   │   ├── February
│   │   └── ...
│   └── 2023
│       ├── January
│       └── ...
├── Work (root)
├── Personal (root)
└── ...
```

## Supabase Schema (Current)

```sql
-- Core Tables
┌─────────────────────────────────┐
│ auth.users (Supabase built-in)  │
│ ├─ id (UUID)                    │
│ └─ email (VARCHAR)              │
└─────────────────┬───────────────┘
                  │
                  ├──► notes
                  ├──► folders
                  ├──► events
                  ├──► deleted_notes
                  ├──► deleted_folders
                  ├──► attachments
                  ├──► extracted_data
                  └──► locations

-- Notes Table
notes (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id),
  title TEXT (ENCRYPTED),          ◄── AES-256
  content TEXT (ENCRYPTED),        ◄── AES-256
  folder_id UUID → folders(id),
  is_pinned BOOLEAN,
  is_locked BOOLEAN,
  image_attachments JSONB (URLs),
  date_created TIMESTAMP,
  date_modified TIMESTAMP
)

-- Folders Table
folders (
  id UUID PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id),
  name VARCHAR (plain text),        ◄── NOT encrypted
  color VARCHAR,
  parent_folder_id UUID → folders(id),
  created_at TIMESTAMP
)
```

## Authentication & Security Flow

```
┌─────────────────────────────────┐
│  User Launch App                │
└────────────┬────────────────────┘
             │
             ▼
┌─────────────────────────────────┐
│ Check Auth Status               │
│ • Supabase session exists?      │
│ • Gmail token valid?            │
└────────────┬────────────────────┘
             │
      ┌──────┴──────┐
      │             │
      ▼             ▼
  Authenticated  Not Authenticated
      │             │
      │             ▼
      │     ┌───────────────────┐
      │     │ Google Sign-In    │
      │     │ (OAuth2)          │
      │     └─────────┬─────────┘
      │               │
      │     ┌─────────▼──────────┐
      │     │ Get Tokens:        │
      │     │ • Gmail access     │
      │     │ • ID token         │
      │     └─────────┬──────────┘
      │               │
      └───────┬───────┘
              │
              ▼
    ┌─────────────────────────┐
    │ Setup Encryption        │
    │ Key = f(userId, device) │
    │ Stored in Keychain      │
    └────────┬────────────────┘
             │
             ▼
    ┌─────────────────────────┐
    │ Load Data from          │
    │ • Supabase (notes)      │
    │ • Cache (emails)        │
    │ • Decrypt if needed     │
    └─────────────────────────┘
```

## Cache Strategy (Emails)

```
┌────────────────────────────────────┐
│  EmailService Cache                │
├────────────────────────────────────┤
│ In-Memory (@Published)             │
│ ├─ inboxEmails: [Email]           │
│ ├─ sentEmails: [Email]            │
│ └─ searchResults: [Email]         │
│                                    │
│ Persistence (UserDefaults)         │
│ ├─ cached_inbox_emails (JSON)     │
│ ├─ cached_sent_emails (JSON)      │
│ ├─ cached_inbox_timestamp         │
│ └─ cached_sent_timestamp          │
│                                    │
│ Cache Metadata                     │
│ ├─ expirationTime: 7 days         │
│ ├─ lastRefreshTime: [EmailFolder] │
│ └─ cacheValid(folder): Bool       │
└────────────────────────────────────┘

Cache Invalidation:
  7 days OR forced refresh OR app restart
```

## Email Categorization Logic

```
Email Classification:
  1. Check Gmail Labels (highest priority)
     ├─ CATEGORY_PRIMARY     → Primary
     ├─ CATEGORY_SOCIAL      → Social
     ├─ CATEGORY_PROMOTIONS  → Promotions
     ├─ CATEGORY_UPDATES     → Updates
     └─ CATEGORY_FORUMS      → Forums

  2. If no Gmail label, use heuristics:
     ├─ Domain check
     │  (facebook.com, instagram.com, etc.) → Social
     │
     ├─ Keyword check (subject + snippet)
     │  ("unsubscribe", "promotion", "sale") → Promotions
     │  ("update", "notification", "receipt") → Updates
     │  ("mailing list", "forum") → Forums
     │
     └─ Default: Primary
```

## Component Dependencies

```
EmailView
├─ EmailService (shared instance)
├─ EmailTabView (Inbox/Sent tabs)
├─ EmailCategoryFilterView (category slider)
├─ EmailListWithCategories
│  └─ EmailRow (individual email)
│     ├─ Sender avatar
│     ├─ Subject + preview
│     └─ Metadata (time, unread, attachments)
│
└─ EmailDetailView (sheet)
   ├─ CompactSenderView
   ├─ AISummaryCard (GPT-4o)
   ├─ Original email content
   ├─ AttachmentRow[] (display only)
   └─ EmailActionButtons
      ├─ Reply (opens Gmail)
      ├─ Forward (opens Gmail)
      ├─ Delete
      ├─ Mark as unread
      └─ Add event from email
```

## Data Sync Architecture

```
Local ◄──────────────► Remote (Supabase)

EMAILS:
  Local Cache (7 days)  ◄── Gmail API source
  └─ NO Supabase sync
  └─ Reason: Gmail is single source of truth

NOTES:
  Memory (@Published)  ◄──► Supabase (encrypted)
  └─ UserDefaults (deprecated)
  └─ Encryption: AES-256 before upload
  └─ Decryption: After download

FOLDERS:
  Memory (@Published)  ◄──► Supabase (plain text)
  └─ Async sync with retry
  └─ Hierarchy-aware ordering
  └─ Soft delete (trash for 30 days)

SETTINGS:
  Keychain ◄──► Device only
  └─ Encryption keys
  └─ Auth tokens
  └─ User preferences
```

## Error Handling Strategy

```
Network Error
  ├─ Show cached data (if available)
  ├─ Display error message
  ├─ Provide retry button
  └─ Log error

API Error (4xx/5xx)
  ├─ 401 Unauthorized
  │  └─ Refresh token
  │  └─ Retry with new token
  │
  ├─ 429 Rate Limited
  │  └─ Exponential backoff
  │  └─ Max 2 retries
  │
  └─ Other errors
     └─ Show user-friendly message

UI State
  ├─ .idle (initial)
  ├─ .loading (fetching)
  ├─ .loaded([Email]) (success)
  └─ .error(String) (user message)
```

## Performance Optimizations

```
Current Optimizations:
1. Lazy Loading
   └─ Only load visible folder
   └─ Don't fetch all folders on startup

2. Caching
   └─ 7-day persistent cache
   └─ In-memory fast access
   └─ Avoid redundant API calls

3. Background Tasks
   └─ AI summary preloading (background)
   └─ Profile picture caching
   └─ New email polling (1/min)

4. Rate Limiting
   └─ Max 10 emails per API call
   └─ 1-minute interval for polling
   └─ Profile picture cache (100 entries)

5. Memory Management
   └─ @MainActor for thread safety
   └─ Proper task cancellation
   └─ No memory leaks from closures
```

## File Size & Complexity

```
Models:
  EmailModels.swift       ~600 lines
  NoteModels.swift        ~2100 lines
  AttachmentModels.swift  ~240 lines
  EventModels.swift       ~500 lines

Services:
  EmailService.swift      ~900 lines
  GmailAPIClient.swift    ~800 lines
  SupabaseManager.swift   Varies
  EncryptionManager.swift Varies
  NotesManager.swift      Integrated

Views:
  EmailView.swift         ~200 lines
  EmailDetailView.swift   ~200 lines
  NotesView.swift         ~300 lines
  Components:             70+ views

Total Project:           100+ Swift files
Complexity:              High (multiple services)
```

## Recommended Email Folder Implementation

```
Phase 1: Local Folder Management
  ├─ Create EmailFolder model
  ├─ Add folder CRUD UI
  └─ Cache in memory

Phase 2: Supabase Persistence
  ├─ Create email_folders table
  ├─ Create email_folder_associations table
  ├─ Implement sync with retry
  └─ Add RLS policies

Phase 3: Email Integration
  ├─ Add folderId to Email model
  ├─ Implement move-to-folder
  ├─ Add folder sidebar
  └─ Update email detail view

Phase 4: Advanced Features
  ├─ Folder hierarchy (subfolders)
  ├─ Folder-based search
  ├─ Bulk operations
  └─ Folder statistics
```

---

**Quick Stats:**
- Lines of Code: ~50,000+
- Swift Files: 100+
- API Integrations: 4 (Gmail, Supabase, OpenAI, Google Maps)
- Database Tables: 10+
- UI Components: 70+
- Supported iOS: 17.0+

