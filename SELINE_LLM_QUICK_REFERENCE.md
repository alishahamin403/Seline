# Seline LLM Architecture - Quick Reference Guide

## File Locations & Responsibilities

| File | Location | Purpose |
|------|----------|---------|
| **OpenAIService.swift** | Services/ | Core LLM API client, streaming, context building |
| **SearchService.swift** | Services/ | Entry point for messages, conversation state management |
| **ConversationSearchView.swift** | Views/ | UI for chat interface |
| **ConversationModels.swift** | Models/ | Data models for messages, intents, related data |
| **QueryRouter.swift** | Services/ | Classifies queries as questions vs actions |
| **ConversationActionHandler.swift** | Services/ | Multi-turn workflows for create/update operations |
| **TaskManager.swift** | Services/ | Manages calendar events/tasks |
| **NotesManager.swift** | Services/ | Manages notes and folders |
| **LocationsManager.swift** | Services/ | Manages saved places |
| **EmailService.swift** | Services/ | Manages email data |
| **WeatherService.swift** | Services/ | Manages weather data |

---

## Data Available to LLM

### Events/Tasks
- **Source**: `TaskManager.shared.tasks`
- **Structure**: Dictionary grouped by weekday
- **Fields**: title, date, time, description, completion status
- **Filtering**: Date range detection (today, tomorrow, this week, etc)

### Notes
- **Source**: `NotesManager.shared.notes`
- **Structure**: Array of Note objects
- **Fields**: title, content, folder, isPinned, dates, images
- **Filtering**: All notes included, keyword search supported

### Emails
- **Source**: `EmailService.shared.inboxEmails`
- **Structure**: Array of Email objects
- **Fields**: subject, sender, timestamp, FULL BODY TEXT
- **Filtering**: Top 10 most recent emails
- **Special**: Full email body included (not just snippet)

### Locations/Places
- **Source**: `LocationsManager.shared.savedPlaces`
- **Structure**: Array of SavedPlace objects
- **Fields**: name, address, category, rating, phone, coordinates, custom notes
- **Filtering**: By country, province, city, category, distance
- **Special**: Includes user ratings and personal notes

### Weather
- **Source**: `WeatherService.shared.weatherData`
- **Fields**: Temperature, conditions, sunrise/sunset, 6-day forecast
- **Filtering**: Current location only

### User Preferences
- **Source**: Various preference objects
- **Fields**: Home, work, restaurant locations with coordinates
- **Use Case**: Navigation/ETA calculations

---

## Message Flow

```
User Input
    ↓
SearchService.addConversationMessage(text)
    ↓
QueryRouter.classifyQuery()
    ├─ QUESTION → OpenAIService.answerQuestionWithStreaming()
    │                ↓
    │            buildContextForQuestion()
    │                ↓
    │            Format OpenAI request
    │                ↓
    │            POST to API (streaming enabled)
    │                ↓
    │            Parse SSE chunks
    │                ↓
    │            Update UI in real-time
    │                ↓
    │            Save to history
    │
    └─ ACTION → ConversationActionHandler
                 (Multi-turn questions & confirmation)
```

---

## LLM Request Structure

### Headers
```
Authorization: Bearer {API_KEY}
Content-Type: application/json
```

### Body
```json
{
  "model": "gpt-4o-mini",
  "messages": [
    {
      "role": "system",
      "content": "System prompt + full app context"
    },
    {
      "role": "user",
      "content": "Previous user message"
    },
    {
      "role": "assistant",
      "content": "Previous assistant response"
    },
    {
      "role": "user",
      "content": "Current user query"
    }
  ],
  "temperature": 0.7,
  "max_tokens": 500,
  "stream": true
}
```

### Context Building Process
1. Get current date/time
2. Gather weather data
3. Collect all events (filtered by date)
4. Collect all notes (full text)
5. Collect all emails (top 10, full body)
6. Collect saved places with metadata
7. Format as human-readable text
8. Prepend system prompt

---

## LLM Response Handling

### Streaming (SSE Format)
```
data: {"choices":[{"delta":{"content":"Hello"}}]}
data: {"choices":[{"delta":{"content":" world"}}]}
data: [DONE]
```

### Parsing Steps
1. Parse SSE format (lines starting with "data: ")
2. Extract JSON from each line
3. Get `choices[0].delta.content` field
4. Accumulate into buffer
5. Send chunks on word boundary/punctuation
6. Detect [DONE] marker
7. Save complete message to history

---

## Conversation Models

### ConversationMessage
```swift
struct ConversationMessage: Identifiable, Codable {
    let id: UUID
    let isUser: Bool          // true = user, false = assistant
    let text: String          // Full message text
    let timestamp: Date
    let intent: QueryIntent?  // calendar, notes, locations, general
    let relatedData: [RelatedDataItem]?  // Links to app data
    let timeStarted: Date?    // When LLM started responding
    let timeFinished: Date?   // When LLM finished responding
}
```

### QueryIntent
```swift
enum QueryIntent: String, Codable {
    case calendar = "calendar"
    case notes = "notes"
    case locations = "locations"
    case general = "general"
}
```

### RelatedDataItem
```swift
struct RelatedDataItem: Identifiable, Codable {
    let id: UUID
    let type: DataType        // event, note, location
    let title: String
    let subtitle: String?
    let date: Date?
}
```

---

## Configuration

### OpenAI Settings
- **Model**: gpt-4o-mini
- **Temperature**: 0.7
- **Max Tokens**: 500
- **Base URL**: https://api.openai.com/v1/chat/completions
- **Embeddings Model**: text-embedding-3-small
- **Streaming**: Enabled
- **Rate Limit**: 2 seconds minimum between requests
- **API Key**: Loaded from Config.swift (not in git)

### Streaming Settings
- **Format**: Server-Sent Events (SSE)
- **Chunk Buffering**: Accumulates until word boundary
- **Real-time Update**: Via SwiftUI @Published property
- **Fallback**: Non-streaming mode available

---

## Data Persistence

### Local (Device)
- **Storage**: UserDefaults
- **Method**: `saveConversationLocally()`
- **Timing**: Auto-save during streaming
- **Limit**: ~89MB (was causing issues with notes)

### Cloud (Supabase)
- **Timing**: On conversation close
- **Method**: `saveConversationToSupabase()`
- **Data**: Full message history
- **Model**: SavedConversation with timestamp

---

## Query Types Supported

### Calendar Questions
- "What's on my calendar today?"
- "Do I have any events next week?"
- "When is my next meeting?"

### Notes Questions
- "What notes do I have about..."
- "Show me my pinned notes"
- "Search notes in folder..."

### Location Questions
- "What restaurants have I saved in Toronto?"
- "Show me all my places in Canada"
- "What's near me with good ratings?"
- Geographic filtering: country, province, city, category

### Email Questions
- "What was in that email from..."
- "Show me emails about..."
- Full email body search supported

### Weather Questions
- "What's the weather like?"
- "Should I bring an umbrella?"
- "6-day forecast"

### Multi-Domain Questions
- "I have a meeting tomorrow - what should I do?"
- "Restaurants near my office with good ratings"

---

## Intent Classification

### How Queries are Routed

```
User Input
    ↓
QueryRouter.classifyQuery()
    ├─ Keyword matching (fast path)
    │   ├─ "create", "add", "schedule" → ACTION
    │   ├─ "what", "show", "list" → QUESTION
    │   └─ "tell", "help", "find" → QUESTION
    │
    └─ Semantic LLM matching (fallback)
        └─ Use embeddings if unclear
```

### Intent Detection
- **System Prompt**: Instructs LLM about intent
- **Related Data**: Links to relevant items
- **Follow-ups**: Tracks conversation topics

---

## Key Methods

### SearchService
```swift
// Main entry point
addConversationMessage(_ userMessage: String)

// Streaming response callback
onChunk: { chunk in updateUI() }

// Save conversations
saveConversationLocally()
saveConversationToSupabase()
```

### OpenAIService
```swift
// Main question answering
answerQuestion(query: String, conversationHistory: [...]) async

// Streaming version (default)
answerQuestionWithStreaming(query: String, onChunk: (String) -> Void)

// Context building
buildContextForQuestion() -> String

// Rate limiting
enforceRateLimit()
```

### QueryRouter
```swift
// Classify user query
classifyQuery(_ text: String) -> QueryType
```

### ConversationActionHandler
```swift
// Multi-turn action workflow
startConversationalAction(_ text: String)
```

---

## Markdown Support

### Supported Formatting
- **Bold**: `**text**`
- **Italic**: `*text*`
- **Code**: `` `code` ``
- **Code Blocks**: ````code```
- **Headers**: `## Header`
- **Lists**: `- item` or `1. item`

### Rendering
- Checked via `hasComplexFormatting` property
- Rendered with `MarkdownText` component
- User messages always plain text
- Assistant messages auto-detect formatting

---

## Performance Considerations

### API Efficiency
- Rate limited (2s minimum between requests)
- Max tokens: 500 (keeps responses focused)
- Streaming enabled (feels responsive)
- Embedding cache (reduces redundant calls)

### Context Size
- **Events**: Date range filtered (not all)
- **Notes**: All included (full content)
- **Emails**: Top 10 most recent
- **Places**: All included with metadata
- **Weather**: Current location only

### Memory Management
- Streaming with chunks (not full load)
- SwiftUI reactive binding (automatic updates)
- Conversation history persisted (loaded on demand)
- Embeddings cached (reuse across sessions)

---

## Common Patterns

### Getting Context
```swift
let context = OpenAIService.shared.buildContextForQuestion()
```

### Sending a Message
```swift
SearchService.shared.addConversationMessage("What's on my calendar?")
```

### Streaming with UI Update
```swift
try await OpenAIService.shared.answerQuestionWithStreaming(
    query: "...",
    onChunk: { chunk in
        // Update UI with chunk
    }
)
```

### Saving Conversation
```swift
SearchService.shared.saveConversationLocally()
SearchService.shared.saveConversationToSupabase()
```

---

## Debugging Tips

### Check LLM Response
- Look at `conversationHistory` array
- Check for `timeStarted` and `timeFinished`
- Calculate `timeTakenFormatted` property

### Monitor Streaming
- Check SSE parsing in `makeOpenAIStreamingRequest()`
- Verify [DONE] marker detected
- Check chunk accumulation in buffer

### Verify Context
- Call `buildContextForQuestion()` manually
- Print context string to console
- Check data sources are not empty

### Test Query Classification
- Use QueryRouter.classifyQuery()
- Check intent is correct
- Verify routing to correct handler

---

## Related Documentation
- See `/LLM_CHAT_IMPLEMENTATION.md` for detailed analysis
- See `/SELINE_LLM_ARCHITECTURE.md` for full architecture
- Check individual service files for implementation details
