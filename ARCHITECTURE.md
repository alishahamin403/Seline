# Seline App - Architecture Diagram

## Tech Stack Overview

### Frontend
- **Platform**: iOS (iOS 18.0+)
- **Framework**: SwiftUI
- **Language**: Swift
- **Widgets**: WidgetKit
- **Location Services**: CoreLocation, CLVisit
- **Authentication**: Google Sign-In SDK
- **Notifications**: UserNotifications
- **Calendar**: EventKit
- **Background Tasks**: BackgroundTasks

### Backend & Services
- **Backend-as-a-Service**: Supabase (PostgreSQL, Auth, Storage, Realtime)
- **Edge Functions**: Deno (TypeScript)
  - `llm-proxy`: Routes LLM requests with rate limiting
  - `deepseek-proxy`: DeepSeek API proxy with quota management
- **APIs Used**:
  - Gmail API (email sync)
  - Google Maps API (geocoding, directions)
  - OpenWeatherMap API (weather data)
  - DeepSeek API (LLM/AI)
  - OpenAI API (deprecated, kept for compatibility)

### Database Schema (Supabase PostgreSQL)
- `auth.users` - User authentication
- `saved_places` - Saved locations with geofences
- `location_visits` - Visit tracking with timestamps
- `location_memories` - Location-specific user memories
- `notes` - Encrypted notes
- `emails` - Synced email data
- `tasks` - Calendar events and tasks
- `expenses` - Receipt tracking and expenses
- `user_profiles` - User settings and quotas
- `llm_usage_logs` - LLM request tracking
- `llm_api_keys` - API key pool management

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        iOS CLIENT (Swift)                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────┐  │
│  │   SwiftUI Views  │  │  ViewModels &    │  │   Managers   │  │
│  │                  │  │  StateObjects    │  │   (Services) │  │
│  │  • MainAppView   │  │                  │  │              │  │
│  │  • RootView      │  │  • @StateObject  │  │  • Auth      │  │
│  │  • Notes, Tasks  │  │  • @Observable   │  │  • Location  │  │
│  │  • Maps, Search  │  │  • @Environment  │  │  • Email     │  │
│  └────────┬─────────┘  └────────┬─────────┘  └──────┬───────┘  │
│           │                     │                    │          │
│           └─────────────────────┼────────────────────┘          │
│                                 │                               │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │              CORE SERVICES LAYER                           │ │
│  ├───────────────────────────────────────────────────────────┤ │
│  │                                                             │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │ │
│  │  │ Authentication│  │  Location    │  │    Email     │    │ │
│  │  │  Manager     │  │  Services    │  │   Service    │    │ │
│  │  │              │  │              │  │              │    │ │
│  │  │ • Google Sign│  │ • Geofence   │  │ • Gmail API  │    │ │
│  │  │   -In OAuth  │  │   Manager    │  │ • Sync/Filter│    │ │
│  │  │ • Supabase   │  │ • Visit Track│  │ • Notifications│   │ │
│  │  │   Auth       │  │ • Analytics  │  │              │    │ │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘    │ │
│  │         │                 │                  │            │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │ │
│  │  │    Notes     │  │    Tasks     │  │   Search     │    │ │
│  │  │   Manager    │  │   Manager    │  │   Service    │    │ │
│  │  │              │  │              │  │              │    │ │
│  │  │ • CRUD Ops   │  │ • Calendar   │  │ • Full-Text  │    │ │
│  │  │ • Encryption │  │   Sync       │  │   Search     │    │ │
│  │  │ • Supabase   │  │ • EventKit   │  │ • LLM Query  │    │ │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘    │ │
│  │         │                 │                  │            │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │ │
│  │  │    AI/LLM    │  │   Widget     │  │   Cache      │    │ │
│  │  │   Service    │  │   Manager    │  │   Manager    │    │ │
│  │  │              │  │              │  │              │    │ │
│  │  │ • DeepSeek   │  │ • WidgetKit  │  │ • In-Memory  │    │ │
│  │  │ • Query      │  │ • Data Sync  │  │ • Keychain   │    │ │
│  │  │   Processing │  │ • Updates    │  │ • Persistence│    │ │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘    │ │
│  └─────────┼──────────────────┼─────────────────┼────────────┘ │
│            │                  │                 │              │
└────────────┼──────────────────┼─────────────────┼──────────────┘
             │                  │                 │
             │                  │                 │
             ▼                  ▼                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                      SUPABASE BACKEND                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │    Auth      │  │  PostgreSQL  │  │   Storage    │          │
│  │              │  │  Database    │  │              │          │
│  │ • OAuth JWT  │  │              │  │ • File Upload│          │
│  │ • Sessions   │  │ • RLS Policy │  │ • Attachments│          │
│  │ • User Mgmt  │  │ • Migrations │  │ • Images     │          │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘          │
│         │                 │                  │                  │
│         └─────────────────┼──────────────────┘                  │
│                           │                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              EDGE FUNCTIONS (Deno)                        │  │
│  ├──────────────────────────────────────────────────────────┤  │
│  │                                                           │  │
│  │  ┌──────────────┐              ┌──────────────┐         │  │
│  │  │  llm-proxy   │              │deepseek-proxy│         │  │
│  │  │              │              │              │         │  │
│  │  │ • Rate Limit │              │ • Quota Check│         │  │
│  │  │ • User Bucket│              │ • Key Pooling│         │  │
│  │  │ • API Pool   │              │ • Daily/Month│         │  │
│  │  └──────┬───────┘              └──────┬───────┘         │  │
│  └─────────┼──────────────────────────────┼─────────────────┘  │
│            │                              │                     │
└────────────┼──────────────────────────────┼─────────────────────┘
             │                              │
             ▼                              ▼
┌────────────────────────┐      ┌────────────────────────┐
│     DeepSeek API       │      │      Other APIs        │
│                        │      │                        │
│ • LLM Queries          │      │ • Gmail API            │
│ • Text Generation      │      │ • Google Maps          │
│ • Chat Completions     │      │ • OpenWeatherMap       │
└────────────────────────┘      └────────────────────────┘
```

---

## Core Data Flow

### 1. Location Tracking Flow

```
iOS Location Services
    ↓
[CoreLocation] → [CLVisit] → [SharedLocationManager]
    ↓
[GeofenceManager] → Check geofence entry/exit
    ↓
[LocationVisitRecord] → Calculate duration
    ↓
[BackgroundValidationService] → Validate visit (>2min)
    ↓
[Supabase] → Save to `location_visits` table
    ↓
[LocationVisitAnalytics] → Aggregate stats, cache
    ↓
[UI Update] → Display visits, stats
```

### 2. Email Sync Flow

```
Background Task (BGTaskScheduler)
    ↓
[EmailService] → Gmail API Request
    ↓
[GmailAPIClient] → Fetch emails
    ↓
[EmailNotificationIntelligence] → Filter, prioritize
    ↓
[Supabase] → Save to `emails` table
    ↓
[Local Cache] → Update UI
    ↓
[NotificationService] → Push notifications
```

### 3. AI/LLM Query Flow

```
User Query (SearchService)
    ↓
[QueryRouter] → Parse intent
    ↓
[Supabase Edge Function] → `/functions/llm-proxy`
    ↓
    ├─ Check user quota (RPC: check_user_quota)
    ├─ Rate limiting (token bucket)
    ├─ Select API key from pool
    └─ Log usage
    ↓
[DeepSeek API] → Process query
    ↓
[Response] → Parse, format
    ↓
[SearchService] → Update UI, cache result
```

### 4. Note/Task Creation Flow

```
User Input (SwiftUI View)
    ↓
[NotesManager / TaskManager] → Create model
    ↓
[EncryptionHelper] → Encrypt sensitive data
    ↓
[Supabase] → Insert with RLS policy
    ↓
[CacheManager] → Update local cache
    ↓
[WidgetManager] → Refresh widgets
    ↓
[UI Update] → Display in list
```

---

## Service Architecture Details

### Location Services

```
┌─────────────────────────────────────────┐
│       Location Service Layer            │
├─────────────────────────────────────────┤
│                                         │
│  ┌──────────────────────────────────┐  │
│  │   SharedLocationManager          │  │
│  │   • CLLocationManager wrapper    │  │
│  │   • CLVisit monitoring           │  │
│  │   • Background location updates  │  │
│  └────────────┬─────────────────────┘  │
│               │                         │
│  ┌────────────▼─────────────────────┐  │
│  │   GeofenceManager                │  │
│  │   • Geofence setup/removal       │  │
│  │   • Entry/exit detection         │  │
│  │   • Visit record management      │  │
│  └────────────┬─────────────────────┘  │
│               │                         │
│  ┌────────────▼─────────────────────┐  │
│  │   LocationVisitAnalytics         │  │
│  │   • Visit aggregation            │  │
│  │   • Statistics calculation       │  │
│  │   • Midnight splitting           │  │
│  └──────────────────────────────────┘  │
│                                         │
│  ┌──────────────────────────────────┐  │
│  │   Background Services            │  │
│  │   • LocationBackgroundTaskService│  │
│  │   • LocationBackgroundValidation │  │
│  │   • LocationErrorRecoveryService │  │
│  └──────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

### AI/LLM Services

```
┌─────────────────────────────────────────┐
│         AI Query Processing             │
├─────────────────────────────────────────┤
│                                         │
│  ┌──────────────────────────────────┐  │
│  │   SearchService                  │  │
│  │   • Query parsing                │  │
│  │   • Context building             │  │
│  └────────────┬─────────────────────┘  │
│               │                         │
│  ┌────────────▼─────────────────────┐  │
│  │   QueryRouter                    │  │
│  │   • Route to appropriate handler │  │
│  │   • Intent classification        │  │
│  └────────────┬─────────────────────┘  │
│               │                         │
│  ┌────────────▼─────────────────────┐  │
│  │   Specialized Services           │  │
│  │   • QueryAnalysisService         │  │
│  │   • ConversationContextService   │  │
│  │   • NaturalLanguageExtraction    │  │
│  └────────────┬─────────────────────┘  │
│               │                         │
│  ┌────────────▼─────────────────────┐  │
│  │   Supabase Edge Function         │  │
│  │   (Rate Limiting, Quota Check)   │  │
│  └────────────┬─────────────────────┘  │
│               │                         │
│  ┌────────────▼─────────────────────┐  │
│  │   DeepSeek API                   │  │
│  └──────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

---

## Background Processing

### Background Tasks

1. **Email Refresh** (`com.seline.emailRefresh`)
   - Type: BGAppRefreshTask
   - Frequency: Every 15+ minutes
   - Purpose: Lightweight email sync

2. **Email Processing** (`com.seline.emailProcessing`)
   - Type: BGProcessingTask
   - Frequency: Every 5+ minutes
   - Purpose: Full email sync when device charging

3. **Location Refresh** (Custom)
   - Type: BGAppRefreshTask
   - Purpose: Validate geofence state when app backgrounded

4. **Location Processing** (Custom)
   - Type: BGProcessingTask
   - Purpose: Deep location validation

---

## Security Architecture

### Encryption

```
┌─────────────────────────────────────────┐
│         Encryption Layer                │
├─────────────────────────────────────────┤
│                                         │
│  ┌──────────────────────────────────┐  │
│  │   EncryptionManager              │  │
│  │   • AES-256-GCM encryption       │  │
│  │   • Key derivation (PBKDF2)      │  │
│  └────────────┬─────────────────────┘  │
│               │                         │
│  ┌────────────▼─────────────────────┐  │
│  │   Helper Services                │  │
│  │   • EncryptedNoteHelper          │  │
│  │   • EncryptedLocationHelper      │  │
│  │   • EncryptedEmailHelper         │  │
│  │   • EncryptedTaskHelper          │  │
│  └──────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

### Authentication & Authorization

```
User → Google Sign-In → OAuth Token
    ↓
Supabase Auth → JWT Token
    ↓
PostgreSQL RLS Policies → Row-level security
    ↓
Data Access (filtered by user_id)
```

---

## Widget Extension

```
┌─────────────────────────────────────────┐
│      SelineWidget Extension             │
├─────────────────────────────────────────┤
│                                         │
│  • WidgetKit framework                 │
│  • Shared App Groups for data sync     │
│  • Timeline provider                   │
│  • Background refresh                  │
│                                         │
│  Displays:                             │
│    - Today's tasks                     │
│    - Spending summary                  │
│    - Visit stats                       │
└─────────────────────────────────────────┘
```

---

## Key Design Patterns

1. **Singleton Services**: Shared managers (AuthManager, GeofenceManager, etc.)
2. **Observable Objects**: SwiftUI state management with @StateObject
3. **Repository Pattern**: SupabaseManager abstracts data access
4. **Service Layer**: Business logic separated from UI
5. **Background Processing**: BGTaskScheduler for reliable background work
6. **Caching Strategy**: Multi-layer caching (in-memory, Keychain, Supabase)
7. **Encryption at Rest**: Sensitive data encrypted before storage
8. **RLS Policies**: Database-level security in Supabase

---

## Database Schema Highlights

- **Row-Level Security (RLS)**: All tables have policies ensuring users only access their own data
- **Foreign Key Constraints**: Referential integrity maintained
- **Indexes**: Optimized for common query patterns (user_id, saved_place_id, etc.)
- **Triggers**: Automatic timestamp updates (created_at, updated_at)
- **Functions**: Helper RPC functions for quota checking, visit merging, etc.

---

## Performance Optimizations

1. **Caching**: In-memory cache for frequently accessed data
2. **Lazy Loading**: Views load data on-demand
3. **Background Processing**: Heavy operations moved to background tasks
4. **Batch Operations**: Multiple database operations batched when possible
5. **Connection Pooling**: Supabase handles connection pooling
6. **Indexing**: Database indexes on commonly queried columns
7. **Pagination**: Large result sets paginated

---

## Error Handling & Recovery

1. **LocationErrorRecoveryService**: Recovers from location service failures
2. **Retry Logic**: Automatic retries for network failures
3. **Graceful Degradation**: App continues working if some services fail
4. **Logging**: Comprehensive logging for debugging
5. **User Feedback**: Error messages displayed to users when needed
