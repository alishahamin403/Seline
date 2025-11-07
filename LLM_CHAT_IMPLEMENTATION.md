# LLM Chat Implementation Analysis - Seline

## Overview
Seline implements a multi-turn conversational chat system integrated with an iOS calendar/notes/email management app. The chat allows users to query their app data and perform actions through natural language.

---

## 1. Files That Handle OpenAI API Calls

### Primary LLM Service
**File**: `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Services/OpenAIService.swift`

**Key Functions**:
- `answerQuestion()` - Non-streaming question answering with conversation history
- `answerQuestionWithStreaming()` - Real-time streaming responses with chunks
- `makeOpenAIStreamingRequest()` - Handles SSE (Server-Sent Events) parsing for streaming

**Configuration**:
- Base URL: `https://api.openai.com/v1/chat/completions`
- Model: `gpt-4o-mini`
- API Key: Loaded from `Config.swift` (not committed to git)
- Rate limiting: 2-second minimum interval between requests
- Embedding model: `text-embedding-3-small` (for semantic similarity)

---

## 2. Message Formatting & Sending Flow

### Message Flow Architecture

```
User Input (SearchService.swift)
    ↓
Classification (QueryRouter) - Is it a question or action?
    ↓
If Action → ConversationActionHandler → Multi-turn action flow
If Question → OpenAIService.answerQuestion()
    ↓
buildContextForQuestion() - Gathers all app data
    ↓
Creates system prompt + conversation history
    ↓
POST to OpenAI API with streaming
    ↓
SSE Parser processes chunks
    ↓
ConversationMessage added to history
    ↓
UI updates via ConversationSearchView
```

### Message Sending - Main Entry Point

**File**: `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Services/SearchService.swift`
**Function**: `addConversationMessage(_ userMessage: String)`

```swift
// Process flow:
1. Trim and validate input
2. Classify query type (Question vs Action)
3. If action: startConversationalAction()
4. If question: 
   - Build context with buildContextForQuestion()
   - Call OpenAIService.answerQuestionWithStreaming() OR answerQuestion()
   - Stream chunks back to UI
   - Add assistant response to conversationHistory
   - Save to local storage
```

**Lines**: 574-684

### Streaming vs Non-Streaming
- **Streaming enabled** (default): Uses `answerQuestionWithStreaming()` with `onChunk` callback
- **Non-streaming**: Uses `answerQuestion()` for simpler responses
- Toggle available via `SearchService.enableStreamingResponses` property

---

## 3. App Context Passed to LLM

### Context Builder

**File**: `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Services/OpenAIService.swift`
**Function**: `buildContextForQuestion()` (Lines 2106-2245)

### Data Included in Context

1. **Current Date/Time**
   - Full date format (medium style)
   - Current time (short style)

2. **Weather Data** (if available)
   - Location name
   - Current temperature & description
   - Sunrise/sunset times
   - 6-day forecast

3. **Navigation Destinations** (ETAs)
   - Location 1, Location 2, Location 3 distances

4. **Saved Locations/Places**
   - Name, custom name, category
   - Address, city, country
   - Rating, phone number, user notes
   - Available filters: country, city, category, duration

5. **Tasks/Events** (Filtered by date range)
   - Title, date, time
   - Completion status (✓ or ○)
   - Description
   - Date range detection (today, tomorrow, this week, next week, etc.)
   - All tasks flattened from TaskManager.tasks dictionary

6. **All Notes** (Full content)
   - Title, content
   - Folder/category information
   - Last modified date
   - All notes sorted by modification date

7. **All Emails** (Full details)
   - Subject, sender, date
   - Full body text (not just snippet)
   - Read/unread status
   - Top 10 most recent emails from inbox

### Context Source Classes
- `TaskManager.shared.tasks` - Dictionary of events by weekday
- `NotesManager.shared.notes` - Array of all notes
- `EmailService.shared.inboxEmails` - Inbox emails
- `LocationsManager.shared.savedPlaces` - Saved locations
- `WeatherService.shared.weatherData` - Current & forecast data
- `NavigationService.shared` - ETA destinations

### Intelligent Filtering
- **Date range detection**: Analyzes query for temporal keywords ("today", "tomorrow", "next week", "this month", etc.)
- **Keyword extraction**: Finds relevant items by searching title/content
- The `AppContextService` provides an alternative context builder with keyword-based matching

---

## 4. System Prompt & LLM Instructions

### System Prompt Template

**Location**: `OpenAIService.swift` - `answerQuestion()` function (Lines 1897-1916)

```swift
let systemPrompt = """
You are a helpful personal assistant that helps users understand their schedule, notes, emails, weather, locations, and saved places.
Based on the provided context about the user's data, answer their question in a clear, concise way.
If the user asks about "tomorrow", "today", "next week", etc., use the current date context provided.
For location-based queries: You can filter by country, city, category (folder), distance, or duration.
For weather queries: Use the provided weather data and forecast.
Always be helpful and provide specific details when available.

FORMATTING INSTRUCTIONS:
- Use **bold** for important information, dates, times, amounts, and key facts
- Use bullet points (- ) for lists of items
- Use numbered lists (1. 2. 3.) for steps or prioritized items
- Use `code formatting` for technical details or specific values
- Use heading style (## or ###) for different sections
- Break information into short paragraphs with clear spacing
- Never use walls of text - prioritize readability with proper formatting

Context about user's data:
\(context)
"""
```

### Message Structure Sent to API

```swift
var messages: [[String: String]] = [
    ["role": "system", "content": systemPrompt]
]

// Add previous conversation messages
for message in conversationHistory {
    messages.append([
        "role": message.isUser ? "user" : "assistant",
        "content": message.text
    ])
}

// Add current query
messages.append([
    "role": "user",
    "content": query
])

// Request parameters
let requestBody: [String: Any] = [
    "model": "gpt-4o-mini",
    "messages": messages,
    "temperature": 0.7,
    "max_tokens": 500,
    "stream": true  // For streaming responses
]
```

### Conversation History
- Full conversation history is included in every request
- Previous messages are added in chronological order
- Helps LLM understand context of multi-turn conversations

---

## 5. Response Parsing & Display

### Streaming Response Handler

**File**: `OpenAIService.swift`
**Function**: `makeOpenAIStreamingRequest()` (Lines 2036-2100)

**Process**:
1. Creates URLSession streaming request with SSE format
2. Parses incoming bytes line-by-line
3. Extracts JSON from `data: {json}` format
4. Parses `choices[0].delta.content` for text chunks
5. Accumulates chunks into buffer
6. Sends chunks via callback when word boundary or punctuation found
7. Detects `[DONE]` marker for stream completion

### Response Display

**File**: `ConversationSearchView.swift` (Lines 272-329)

**Component**: `ConversationMessageView`

**Display Logic**:
```swift
// Checks for complex formatting (markdown, lists, code)
private var hasComplexFormatting: Bool {
    message.text.contains("**") || message.text.contains("*") ||
        message.text.contains("`") || message.text.contains("- ") ||
        message.text.contains("• ") || message.text.contains("\n")
}

// Rendering:
if hasComplexFormatting && !message.isUser {
    MarkdownText(markdown: message.text, colorScheme: colorScheme)
} else {
    Text(message.text)
        .font(.system(size: 13, weight: .regular))
        .foregroundColor(...)
        .textSelection(.enabled)
}
```

### Message Styling
- **User messages**: White background (dark mode) / Black background (light mode)
- **AI responses**: Gray transparent background (15% opacity)
- **Font**: 13pt regular weight
- **Text selection**: Enabled for copying
- **Rounded corners**: 12pt radius
- **Padding**: 12pt horizontal, 10pt vertical

### Markdown Rendering
- Uses `MarkdownText` component for rich formatting
- Strips markdown symbols during rendering (per recent commit)
- Supports bold, italic, code blocks, headers, lists

### Streaming UI Updates
**File**: `SearchService.swift` (Lines 618-653)

```swift
// Create placeholder message
var assistantMsg = ConversationMessage(
    id: streamingMessageID, 
    isUser: false, 
    text: "", 
    timestamp: Date(), 
    intent: .general
)
conversationHistory.append(assistantMsg)

// Update message as chunks arrive
try await OpenAIService.shared.answerQuestionWithStreaming(
    // ... parameters ...
    onChunk: { chunk in
        fullResponse += chunk
        // Update message in history with accumulated text
        if let lastIndex = self.conversationHistory.lastIndex(where: { $0.id == streamingMessageID }) {
            let updatedMsg = ConversationMessage(
                id: streamingMessageID,
                isUser: false,
                text: fullResponse,
                timestamp: self.conversationHistory[lastIndex].timestamp,
                intent: self.conversationHistory[lastIndex].intent
            )
            self.conversationHistory[lastIndex] = updatedMsg
            self.saveConversationLocally()
        }
    }
)
```

### Conversation UI Container

**File**: `ConversationSearchView.swift` (Lines 24-101)

- Scrollable message list
- Auto-scrolls to latest message via `ScrollViewReader`
- Loading indicator ("Thinking...") while response streams
- Header with conversation title and controls
- Keyboard dismissal on scroll gesture

---

## Data Models

### ConversationMessage

**File**: `ConversationModels.swift`

```swift
struct ConversationMessage: Identifiable, Codable {
    let id: UUID
    let isUser: Bool
    let text: String
    let timestamp: Date
    let intent: QueryIntent?
    let relatedData: [RelatedDataItem]?
}

enum QueryIntent: String, Codable {
    case calendar = "calendar"
    case notes = "notes"
    case locations = "locations"
    case general = "general"
}
```

### SearchService Published Properties

- `conversationHistory: [ConversationMessage]` - Current conversation
- `isInConversationMode: Bool` - Active conversation state
- `conversationTitle: String` - Auto-generated title
- `isLoadingQuestionResponse: Bool` - Loading state
- `enableStreamingResponses: Bool` - Streaming toggle
- `savedConversations: [SavedConversation]` - Persistent history

---

## Conversation Persistence

**Local Storage**: `SearchService.swift`
- Conversations saved to device storage before clearing
- Auto-saves during streaming via `saveConversationLocally()`

**Cloud Storage**: `Supabase`
- `saveConversationToSupabase()` - Uploads conversation on close
- Conversations saved with full message history

**History Model**: `SavedConversation`
- ID, title, messages, createdAt timestamp

---

## Additional Features

### Query Classification
**File**: `QueryRouter.swift`
- Detects whether input is a question, search, or action
- Semantic LLM fallback for ambiguous cases
- Routes to appropriate handler (conversation vs action)

### Conversational Actions
**File**: `ConversationActionHandler.swift`
- Multi-turn flow for creating/updating events and notes
- Extracts information incrementally
- Asks clarifying questions
- Confirms before saving

### Embeddings & Semantic Search
**File**: `OpenAIService.swift` (Lines 2397-2537)
- Uses `text-embedding-3-small` model
- Caches embeddings to reduce API calls
- Computes cosine similarity for semantic matching

---

## Summary

The LLM chat implementation is a comprehensive system that:

1. **Captures user messages** through `SearchService.addConversationMessage()`
2. **Builds rich context** from all app data via `buildContextForQuestion()`
3. **Sends formatted requests** to OpenAI's gpt-4o-mini via streaming API
4. **Parses SSE responses** with chunk-by-chunk updates
5. **Displays conversations** with markdown support and real-time updates
6. **Manages state** with conversation history and persistence
7. **Handles multi-turn interactions** including context-aware action building
8. **Persists conversations** both locally and to Supabase

The architecture separates concerns across multiple services while maintaining a unified conversational experience in the UI.
