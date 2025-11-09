# Seline LLM Chat Architecture - Comprehensive Summary

## Overview
Seline is an iOS personal assistant app that integrates conversational AI (OpenAI's GPT-4o-mini) with calendar events, notes, emails, locations, and weather data. Users can query their app data and perform actions through natural language conversations.

---

## 1. Current LLM Chat Implementation Location

### Primary Files:
- **OpenAIService.swift** - Core LLM service handling API calls, streaming, and context building
- **SearchService.swift** - Main entry point for conversation messages and query routing
- **ConversationSearchView.swift** - UI for displaying chat conversations
- **ConversationModels.swift** - Data models for messages and conversation state
- **QueryRouter.swift** - Query classification (question vs action)
- **ConversationActionHandler.swift** - Multi-turn action workflows

### LLM Configuration:
- **Model**: `gpt-4o-mini` (optimized for cost and speed)
- **Base URL**: `https://api.openai.com/v1/chat/completions`
- **API Key**: Loaded from `Config.swift` (environment variable, not committed)
- **Rate Limiting**: 2-second minimum interval between requests
- **Temperature**: 0.7 (balanced creativity/consistency)
- **Max Tokens**: 500 per response
- **Streaming**: Enabled by default via Server-Sent Events (SSE)

---

## 2. Data Models & Schema

### Conversation Messages
```swift
struct ConversationMessage: Identifiable, Codable {
    let id: UUID
    let isUser: Bool
    let text: String
    let timestamp: Date
    let intent: QueryIntent?  // calendar, notes, locations, general
    let relatedData: [RelatedDataItem]?
    let timeStarted: Date?     // LLM thinking time
    let timeFinished: Date?
}

enum QueryIntent: String {
    case calendar = "calendar"
    case notes = "notes"
    case locations = "locations"
    case general = "general"
}
```

### Key Data Models Available to LLM:

#### Events/Tasks
```swift
// Stored in TaskManager.shared.tasks (Dictionary<String, [CalendarEvent]>)
// Grouped by weekday (monday, tuesday, etc)
// Includes: title, date, time, description, completion status
```

#### Notes
```swift
struct Note: Identifiable, Codable {
    var id: UUID
    var title: String
    var content: String
    var dateCreated: Date
    var dateModified: Date
    var isPinned: Bool
    var folderId: UUID?
    var isLocked: Bool
    var imageUrls: [String]
}
// Stored in NotesManager.shared.notes
// All notes are included in LLM context
```

#### Saved Locations/Places
```swift
struct SavedPlace: Identifiable, Codable {
    var id: UUID
    var googlePlaceId: String
    var name: String
    var customName: String?
    var address: String
    var phone: String?
    var latitude: Double
    var longitude: Double
    var category: String         // AI-generated folder
    var photos: [String]
    var rating: Double?
    var openingHours: [String]?
    var isOpenNow: Bool?
    var country: String?         // Extracted from address
    var province: String?
    var city: String?
    var userRating: Int?         // 1-10 personal rating
    var userNotes: String?
    var userCuisine: String?
}
// Stored in LocationsManager.shared.savedPlaces
// Supports geographic filtering (country, province, city, category)
```

#### Emails
```swift
struct Email: Identifiable, Codable {
    let id: String
    let subject: String
    let sender: String
    let timestamp: Date
    let body: String              // FULL TEXT (not just snippet)
    let isRead: Bool
    // And more fields...
}
// Stored in EmailService.shared.inboxEmails
// Top 10 most recent emails included in context
```

#### Weather Data
```swift
// Stored in WeatherService.shared.weatherData
// Includes:
// - Current temperature & description
// - Location name
// - Sunrise/sunset times
// - 6-day forecast
```

#### User Preferences
```swift
struct UserLocationPreferences {
    var location1Address: String?    // Home
    var location2Address: String?    // Work
    var location3Address: String?    // Restaurant
    var location4Address: String?    // Custom
    // With latitude/longitude for each
}
// Used for navigation/ETA queries
```

---

## 3. How Chat Data is Structured & Sent to LLM

### Message Flow Architecture:

```
User Input → SearchService.addConversationMessage()
    ↓
QueryRouter.classifyQuery()
    ↓
    ├─ If Action → ConversationActionHandler (multi-turn flow)
    └─ If Question → OpenAIService
            ↓
            buildContextForQuestion()
            ↓
            Creates system prompt + conversation history
            ↓
            Builds request body with OpenAI format
            ↓
            POST to OpenAI API with streaming
```

### Context Building (`buildContextForQuestion()`)

The LLM receives richly formatted context:

```
SYSTEM PROMPT:
"You are a helpful personal assistant that helps users understand their schedule, 
notes, emails, weather, locations, and saved places. Based on the provided context 
about the user's data, answer their question in a clear, concise way..."

APP CONTEXT (organized sections):
1. Current Date/Time
   - Full date (medium style)
   - Current time (short style)

2. Weather Data (if available)
   - Location, temperature, description
   - Sunrise/sunset times
   - 6-day forecast

3. Navigation Destinations (ETAs)
   - Location 1, 2, 3 with distances

4. Saved Locations/Places
   - Name, custom name, category
   - Address, city, country
   - Rating, phone, user notes
   - Available filters: country, city, category, duration

5. Tasks/Events (filtered by date range)
   - Title, date, time
   - Completion status (✓ or ○)
   - Description
   - Date range detection (today, tomorrow, this week, etc)
   - All tasks flattened from TaskManager

6. All Notes (full content)
   - Title, content
   - Folder/category information
   - Last modified date

7. All Emails (full details)
   - Subject, sender, date
   - Full body text (NOT just snippet)
   - Read/unread status
   - Top 10 most recent from inbox
```

### Message Format Sent to API:

```json
{
  "model": "gpt-4o-mini",
  "messages": [
    {
      "role": "system",
      "content": "[System prompt with full context about user's data]"
    },
    {
      "role": "user",
      "content": "[Previous user message 1]"
    },
    {
      "role": "assistant",
      "content": "[Previous assistant response 1]"
    },
    {
      "role": "user",
      "content": "[Current user query]"
    }
  ],
  "temperature": 0.7,
  "max_tokens": 500,
  "stream": true
}
```

### Conversation History Management:
- Full conversation history included in every request
- Previous messages added in chronological order
- Enables multi-turn context-aware conversations
- History persisted locally to UserDefaults
- History synced to Supabase after conversation ends

---

## 4. Query Types & Handling

### Question Types Handled:

1. **Calendar Queries**
   - "What's on my calendar today?"
   - "Do I have any events next week?"
   - "When is my next meeting?"
   - Date filtering: today, tomorrow, this week, next week, etc.

2. **Notes Queries**
   - "What notes do I have about [topic]?"
   - "Show me my pinned notes"
   - "Search notes by folder"

3. **Location Queries**
   - "What restaurants have I saved in Toronto?"
   - "Show me all my places in Canada"
   - "What's near me that I've rated highly?"
   - Geographic filtering by country, province, city, category

4. **Email Queries**
   - "What was in that recent email from [sender]?"
   - "Show me emails about [topic]"
   - LLM can search through full email bodies

5. **Weather Queries**
   - "What's the weather like?"
   - "Should I bring an umbrella?"
   - "6-day forecast"

6. **Multi-domain Queries**
   - "I have a meeting tomorrow - what should I do before it?"
   - "Show me restaurants near my office with good ratings"
   - Combines multiple data sources

### Intent Classification:
- **QueryRouter.swift** classifies input as question vs action
- Semantic LLM fallback for ambiguous cases
- Routes to appropriate handler

---

## 5. LLM API Call Format & Structure

### Request Lifecycle:

```swift
// 1. Create request with headers
var request = URLRequest(url: url)
request.httpMethod = "POST"
request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
request.setValue("application/json", forHTTPHeaderField: "Content-Type")

// 2. Encode message payload
let requestBody = [
    "model": "gpt-4o-mini",
    "messages": messages,     // System + history + current query
    "temperature": 0.7,
    "max_tokens": 500,
    "stream": true            // Enable streaming SSE
]

// 3. Create URLSession with streaming delegate
let session = URLSession(configuration: .default)

// 4. Handle streaming response with SSE parsing
// Lines start with "data: " prefix
// JSON format: {"choices":[{"delta":{"content":"chunk"}}]}
// End marker: [DONE]

// 5. Accumulate chunks into buffer
// Send chunks when word boundary or punctuation found
// Update UI in real-time

// 6. Save complete response to conversation history
// Add to conversationHistory array
// Persist to local storage
// Sync to Supabase
```

### Streaming Response Handling:

```swift
func makeOpenAIStreamingRequest() {
    // 1. Parse SSE format (data: {json})
    // 2. Extract JSON from each line
    // 3. Decode "choices[0].delta.content" field
    // 4. Accumulate chunks into buffer
    // 5. Send chunks via callback when word boundary found
    // 6. Detect [DONE] marker for stream completion
}
```

---

## 6. Response Parsing & Display

### Streaming Updates to UI:
1. Create placeholder message with streaming ID
2. Append to conversationHistory
3. As chunks arrive:
   - Accumulate text
   - Update message in history
   - UI reactively updates (SwiftUI binding)
   - Auto-scrolls to latest message
4. Show "Thinking..." loading indicator while streaming
5. On completion, save to local storage and Supabase

### Response Rendering:
```swift
// Check for complex formatting (markdown)
if message.text.contains("**") || message.text.contains("`") {
    // Render with MarkdownText component
} else {
    // Render plain text
}

// Style:
// - User messages: solid background
// - AI responses: semi-transparent gray
// - Font: 13pt regular
// - Text selection enabled for copying
// - Rounded corners, padding
```

### Markdown Support:
- Bold (**text**)
- Italic (*text*)
- Code blocks (```code```)
- Headers (## text)
- Lists (- or 1.)
- Stripped on recent update per commits

---

## 7. Data Persistence & Sync

### Local Storage:
- Conversations saved to UserDefaults (device-only)
- Auto-save during streaming via `saveConversationLocally()`
- Up to ~89MB limit (notes were previously hitting this)

### Cloud Sync (Supabase):
- Conversations saved to Supabase on close
- Full message history persisted
- Model: `SavedConversation` with ID, title, messages, createdAt
- Encryption available for sensitive data

### What Gets Included in Context:
- **All app data** (events, notes, emails, locations)
- **Full content** (not summaries or snippets)
- **Metadata** (dates, categories, ratings, notes)
- **User preferences** (navigation locations, time zones)
- **Derived data** (geographic location info, weather)

---

## 8. Additional Features

### Intelligent Filtering:
- **Date range detection**: Analyzes query for temporal keywords
- **Keyword extraction**: Finds relevant items by title/content search
- **Geographic filtering**: By country, province, city
- **Category filtering**: By folder, type, rating

### Embeddings & Semantic Search:
- Uses `text-embedding-3-small` model
- Cached embeddings to reduce API calls
- Cosine similarity for semantic matching
- Optional enhancement for context relevance

### Multi-Turn Actions:
- `ConversationActionHandler.swift` manages complex flows
- Asks clarifying questions
- Extracts information incrementally
- Confirms before saving changes
- Examples: create event, save note, add location

### Conversation State Tracking:
- Tracks topics discussed
- Identifies follow-ups vs new questions
- Avoids redundancy
- Provides suggested approach for LLM

---

## 9. Architecture Strengths

1. **Rich Context** - LLM has full access to all user data
2. **Real-time Streaming** - Immediate feedback to user
3. **Multi-turn Conversations** - Full history in every request
4. **Smart Routing** - Classifies queries to appropriate handlers
5. **Persistence** - Local + cloud backup
6. **Rate Limited** - 2s minimum between requests (cost control)
7. **Flexible** - Supports questions, actions, and multi-domain queries
8. **Semantic** - Embeddings for similarity matching
9. **User-centric** - Formatted output with markdown support

---

## 10. Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                     USER INTERFACE                          │
│              ConversationSearchView (SwiftUI)               │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ↓ User types message
┌─────────────────────────────────────────────────────────────┐
│                   SearchService                             │
│           addConversationMessage(_ text)                    │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ↓ Classify query type
┌─────────────────────────────────────────────────────────────┐
│                    QueryRouter                              │
│            Is it a question or action?                      │
└────────────┬───────────────────────────┬────────────────────┘
             │                           │
        ACTION                        QUESTION
             │                           │
             ↓                           ↓
    ConversationActionHandler    OpenAIService
             │                           │
             │                           ↓ buildContextForQuestion()
             │                           │
             │                      ┌────────────────────────────┐
             │                      │   App Context Builder      │
             │                      ├────────────────────────────┤
             │                      │ • Current date/time        │
             │                      │ • Weather data             │
             │                      │ • Tasks & events           │
             │                      │ • All notes                │
             │                      │ • All emails               │
             │                      │ • Saved locations          │
             │                      │ • Navigation prefs         │
             │                      └──────────┬─────────────────┘
             │                                 │
             │                                 ↓
             │                    ┌─────────────────────────────┐
             │                    │   Format Request           │
             │                    ├─────────────────────────────┤
             │                    │ System prompt + context     │
             │                    │ Conversation history        │
             │                    │ Current query               │
             │                    └──────────┬──────────────────┘
             │                               │
             │                               ↓
             │                    ┌─────────────────────────────┐
             │                    │  OpenAI API                 │
             │                    │ gpt-4o-mini (streaming)     │
             │                    └──────────┬──────────────────┘
             │                               │
             │                               ↓
             │                    ┌─────────────────────────────┐
             │                    │  SSE Streaming Response     │
             │                    │ Parse chunks line-by-line   │
             │                    └──────────┬──────────────────┘
             │                               │
             └───────────────┬───────────────┘
                             │
                             ↓
         ┌───────────────────────────────────┐
         │  Save to Conversation History     │
         ├───────────────────────────────────┤
         │ • Local (UserDefaults)            │
         │ • Cloud (Supabase)                │
         │ • Save message with timestamp     │
         └───────────────────────────────────┘
                             │
                             ↓
         ┌───────────────────────────────────┐
         │  Update UI (SwiftUI reactive)     │
         │  • Display message                │
         │  • Markdown rendering             │
         │  • Auto-scroll to latest          │
         │  • Update loading state           │
         └───────────────────────────────────┘
```

---

## Summary

The Seline LLM chat is a sophisticated system that:

1. **Captures** user messages through SearchService
2. **Classifies** queries as questions or actions via QueryRouter
3. **Builds** rich context from all app data (events, notes, emails, locations, weather)
4. **Sends** formatted requests to OpenAI's gpt-4o-mini with full conversation history
5. **Streams** SSE responses with real-time chunk updates
6. **Parses** markdown for formatted display
7. **Manages** conversation state and multi-turn context
8. **Persists** conversations locally and to cloud
9. **Handles** complex multi-turn workflows for actions
10. **Supports** semantic search and embeddings

The architecture separates concerns across multiple services while maintaining a unified conversational experience through reactive UI binding and real-time streaming updates.
