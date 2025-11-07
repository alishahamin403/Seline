# LLM Chat Functionality Architecture Overview
## Seline iOS App

### 1. Core Chat Models & Data Structures

#### ConversationMessage (ConversationModels.swift)
- **Purpose**: Represents individual messages in a conversation thread
- **Key Properties**:
  - `id`: UUID for unique identification
  - `isUser`: Boolean to distinguish user vs assistant messages
  - `text`: Message content string
  - `timestamp`: When the message was created
  - `intent`: QueryIntent enum (calendar, notes, locations, general)
  - `relatedData`: Array of RelatedDataItem objects for cross-references
- **Display**: Formats timestamp for UI display

#### SavedConversation (SearchService.swift)
- **Purpose**: Represents a complete conversation session for persistence
- **Key Properties**:
  - `id`: UUID for unique conversation identification
  - `title`: Auto-generated conversation title
  - `messages`: Complete array of ConversationMessage objects
  - `createdAt`: Timestamp when conversation started
  - `formattedDate`: Display-friendly date string

#### QueryIntent Enum
- **Purpose**: Categorizes message intent for context-aware responses
- **Values**:
  - `calendar`: Questions about events, schedules, tasks
  - `notes`: Questions about saved notes/information
  - `locations`: Questions about places, maps, directions
  - `general`: Everything else (conversation, emails, weather, news)
- Each intent has associated icon and color for UI display

#### RelatedDataItem
- **Purpose**: Links conversation messages to relevant app data
- **Types**: 
  - `event`: Calendar/task items
  - `note`: Note items
  - `location`: Saved places
- Enables cross-referencing between messages and data

---

### 2. Conversation Context Service

#### ConversationContextService (ConversationContextService.swift)
- **Pattern**: Singleton with @Published properties for reactive updates
- **Purpose**: Maintains conversation context and improves search relevance

##### Key Properties:
- `recentSearches`: Last 20 search queries with metadata
- `currentTopics`: Active discussion topics (extracted from recent queries)
- `conversationHistory`: Last 100 conversation items

##### SearchContext Structure:
```swift
struct SearchContext {
    let query: String
    let timestamp: Date
    let topics: [String]         // Extracted keywords
    let foundResults: Int        // Result count
    let selectedResult: String?  // User-selected result
}
```

##### Key Methods:
- **trackSearch()**: Logs search queries and extracts topics for context
- **getContextualSearchBoost()**: Returns relevant topics for query expansion
- **isRelatedToRecentContext()**: Checks if current search relates to recent queries
- **getRelatedSearchSuggestions()**: Returns top 5 topics from recent searches
- **extractTopicsFromQuery()**: Parses query for hashtags and category keywords
- **isPossibleFollowUp()**: Detects if query is refinement of previous search
- **getContextBoost()**: Calculates relevance boost for context-related items

##### Topic Extraction:
- Hashtags: `#[a-zA-Z0-9_]+`
- Category keywords: finance, health, work, travel, shopping, etc.
- Uses Levenshtein distance for string similarity calculations

---

### 3. Message Display & Formatting

#### ConversationSearchView (ConversationSearchView.swift)
- **Purpose**: Main UI for conversation display and message input
- **Structure**:
  - Header: Conversation title + history/close buttons
  - Scroll view with message thread
  - Action confirmation area (for event/note creation)
  - Input area with text field and send button

##### ConversationMessageView (Sub-component):
- **Message Alignment**: User messages right-aligned, assistant left-aligned
- **Styling**:
  - User: Dark bubble (white text on dark, dark text on light)
  - Assistant: Light gray bubble (dark text)
  - Max width: 75% of screen
  - Rounded corners: 12pt
  - Timestamp below each message
- **Features**:
  - Text selection enabled
  - Unlimited line wrapping
  - Scroll-to-latest on new messages
  - Keyboard dismissal on scroll

##### ActionConfirmationView (Sub-component):
- **Purpose**: Shows action details for user confirmation
- **Display Format**:
  - Title (event/note name)
  - Details (date/time for events, content for notes)
  - Cancel/Confirm buttons
- **Multi-action Progress**: Shows "Action X of N" indicator

#### ConversationHistoryView (ConversationHistoryView.swift)
- **Purpose**: Shows all saved conversations
- **Features**:
  - List of previous conversations with:
    - Title (auto-generated from first user message)
    - Creation date
    - Message count
    - First user message preview
  - Edit mode for bulk deletion
  - Context menu for individual conversation deletion

---

### 4. Conversational Action System

#### InteractiveAction & Related Models (ConversationalActionModels.swift)
- **Purpose**: Tracks multi-turn action building (event/note creation, updates, deletions)

##### ActionType Enum:
```
- createEvent, updateEvent, deleteEvent
- createNote, updateNote, deleteNote
```

##### InteractiveAction Structure:
```swift
struct InteractiveAction {
    let id: UUID
    let type: ActionType
    var extractedInfo: ExtractedActionInfo    // What we know so far
    var extractionState: ExtractionState      // What needs clarification
    var clarifyingQuestions: [ClarifyingQuestion]
    var suggestions: [ActionSuggestion]
    var conversationTurns: Int
}
```

##### ExtractedActionInfo (For Events):
- `eventTitle`: Required
- `eventDescription`: Optional
- `eventDate`: Required for creation
- `eventStartTime`/`eventEndTime`: Optional
- `eventReminders`: Array of EventReminder objects
- `eventRecurrence`: Recurring pattern string
- `isAllDay`: Boolean flag

##### ExtractedActionInfo (For Notes):
- `noteTitle`: Required
- `noteContent`: Required, stores accumulated content
- `formattedContent`: Rich text version

##### ExtractedActionInfo (For Updates/Deletes):
- `targetItemTitle`: Item to update/delete
- `deleteAllOccurrences`: For recurring events
- `updateContent`: Additional content to add

##### ExtractionState:
```swift
struct ExtractionState {
    var isExtracting: Bool = true           // Actively gathering info
    var isAskingClarifications: Bool = false
    var isShowingSuggestions: Bool = false
    var isConfirming: Bool = false          // User confirmed action
    var isComplete: Bool = false
    var confirmedFields: Set<String>        // Verified fields
    var requiredFields: Set<String>         // Still needed
    var optionalFields: Set<String>         // Nice-to-have
    var currentFocusField: String?          // Current field being filled
}
```

##### Field Requirements by Action:
- **createEvent**: Required: [eventTitle, eventDate], Optional: [time, recurrence, reminders]
- **updateEvent**: Required: [targetItemTitle], Optional: [eventDate, startTime, endTime]
- **deleteEvent**: Required: [targetItemTitle], Optional: [deleteAllOccurrences]
- **createNote**: Required: [noteTitle, noteContent], Optional: []
- **updateNote**: Required: [targetItemTitle, noteContent], Optional: []
- **deleteNote**: Required: [targetItemTitle], Optional: []

##### Completion Logic:
- `isComplete()`: Checks if minimum required fields are populated
- `missingRequiredFields`: Returns list of unfilled required fields
- `nextFieldToConfirm`: Returns next field needing user input

#### ConversationActionContext:
- **Purpose**: Provides full conversation context to action builders
- **Contents**:
  - `conversationHistory`: All messages in current conversation
  - `recentTopics`: Topics discussed recently
  - `lastNoteCreated`: Title of most recent note (for follow-ups like "add to this note")
  - `lastEventCreated`: Title of most recent event (for follow-ups)
  - `historyText`: Formatted conversation as text

---

### 5. Conversational Action Handler

#### ConversationActionHandler (ConversationActionHandler.swift)
- **Pattern**: Singleton on main thread (@MainActor)
- **Purpose**: Orchestrates multi-turn action building workflow

##### Key Dependencies:
- `InformationExtractor.shared`: Extracts structured data from messages
- `InteractiveEventBuilder.shared`: Handles event-specific flow
- `InteractiveNoteBuilder.shared`: Handles note-specific flow

##### Main Methods:

**startAction()**
- Initializes new InteractiveAction from user's initial message
- Calls InformationExtractor to parse initial user message
- Returns action with any auto-detected fields

**processFollowUp()**
- Updates action with new information from user response
- Extracts additional fields from message content

**getNextPrompt()**
- Determines what question to ask user next
- Returns different prompts based on action type and completion state
- Handles transitions between extraction → clarification → confirmation → save

**getConfirmationSummary()**
- Generates user-friendly summary of action details
- Shows "does this look correct?" preview before saving

**processUserResponse()**
- Analyzes user response to an action prompt
- Extracts relevant information if user provides it
- Detects yes/no confirmations for action readiness

**isReadyToSave()**
- Checks if action has all required information
- Returns true when ready to execute/save

**compileEventData()** / **compileNoteData()** / **compileUpdateData()** / **compileDeletionData()**
- Converts InteractiveAction to concrete data structures for saving
- Returns nil if required fields are missing

---

### 6. LLM Integration

#### OpenAIService (OpenAIService.swift)
- **Model**: Uses `gpt-4o` (for precision) and `gpt-4o-mini` (for speed/cost)
- **Base URL**: `https://api.openai.com/v1/chat/completions`
- **Rate Limiting**: Enforces 2-second minimum between requests

##### Key Methods for Chat:

**answerQuestion()**
- **Purpose**: Answers user queries with full app context
- **Input**: Query + TaskManager, NotesManager, EmailService, WeatherService, etc.
- **Context Building**: Includes:
  - Current date/time
  - Weather data and forecast
  - All tasks/events with completion status
  - All notes with folder structure
  - All emails (recent first)
  - Saved locations with filters
  - Navigation ETAs
  - News articles (if query mentions news)
- **Conversation History**: Passes entire history to maintain context
- **Temperature**: 0.7 (balanced creativity/consistency)
- **Max Tokens**: 500
- **Post-processing**: Removes markdown formatting (**, #, *, _, etc.)

**generateText()**
- Generic method for custom prompts
- Accepts system prompt, user prompt, temperature, max_tokens
- Used for specialized tasks

**getEmbedding()**
- **Purpose**: Gets vector embeddings for semantic similarity
- **Model**: `text-embedding-3-small` (fast, cheap)
- **Caching**: Stores embeddings to avoid repeated API calls
- **Returns**: Float vector for similarity calculations

**getSemanticSimilarityScore()** / **getSemanticSimilarityScores()**
- Calculates semantic similarity between query and content
- Uses cosine similarity on embedding vectors
- Returns score 0-10 for search ranking

##### Context-Aware Response Building:
1. **Date Context**: Formats current date for relative queries ("tomorrow", "next week")
2. **Entity Filtering**: Includes location filters (country, city, category, duration)
3. **Task/Event Details**: Full status, date, time, description
4. **Note Organization**: Shows folder structure and content
5. **Email Summary**: Shows sender, subject, date, full body
6. **News Filtering**: Only includes news articles if query mentions news

##### Error Handling:
- `SummaryError` enum with detailed error types:
  - `invalidURL`
  - `noData`
  - `decodingError`
  - `apiError(String)`
  - `rateLimitExceeded(TimeInterval)`
  - `networkError(Error)`

---

### 7. Search Service - Conversation Integration

#### SearchService (SearchService.swift)
- **Pattern**: Singleton with @Published properties
- **Main Purpose**: Routes queries to appropriate handlers (search vs. conversation vs. action)

##### Conversation State Properties:
- `conversationHistory`: Array of ConversationMessage
- `isInConversationMode`: Boolean toggle
- `conversationTitle`: User-facing title
- `savedConversations`: Persistent history

##### Action State Properties:
- `currentInteractiveAction`: Current action being built
- `actionPrompt`: Next question for user
- `isWaitingForActionResponse`: Boolean flag
- `actionSuggestions`: AI suggestions for action fields
- `pendingMultiActions`: Queue of multiple actions from one query

##### Key Methods:

**performSearch()**
- Routes query to appropriate handler
- Checks if query is question → startConversation()
- Checks if query is action → startConversationalAction()
- Otherwise → searchContent() for normal search

**isQuestion()**
- Checks for question mark
- Checks for question keywords: why, how, what, when, where, who, etc.
- Detects question prefixes

**startConversation()**
- Initializes new conversation
- Calls addConversationMessage() with first question
- LLM response added to history

**addConversationMessage()**
- Adds user message to history
- Classifies query with QueryRouter
- If action detected → startConversationalAction()
- Otherwise → calls OpenAIService.answerQuestion()
- Adds AI response to history
- Saves conversation locally

**startConversationalAction()**
- Creates new InteractiveAction
- Adds user message to history
- Gets initial prompt from ConversationActionHandler
- Sets isWaitingForActionResponse = true
- Displays prompt to user

**continueConversationalAction()**
- Updates current action with user response
- Checks if action is ready to save with isReadyToSave()
- If ready → executeConversationalAction()
- Otherwise → getNextPrompt() and ask user for more info

**executeConversationalAction()**
- Compiles action data based on type
- Sets pending creation/update object
- Confirmation flows to action confirmation view
- On confirmation in UI → confirmEventCreation()/confirmNoteCreation()

**generateFinalConversationTitle()**
- Called on conversation close
- Uses LLM to create meaningful title from conversation summary
- Updates savedConversation title

**saveConversationToSupabase()**
- Persists conversation to Supabase database
- Called when user dismisses conversation view

##### Local Persistence:
- `saveConversationLocally()`: Saves to UserDefaults
- `loadConversationHistoryLocally()`: Loads saved conversations on app start
- `saveConversationToHistory()`: Archives completed conversation

---

### 8. Query Classification & Routing

#### QueryRouter (QueryRouter.swift)
- **Purpose**: Classifies incoming queries into action vs. search vs. question

##### QueryType Enum:
- `action(ActionType)`: Detected intent to create/update/delete
- `search`: Content search query
- `question`: Question requiring conversational response

##### Classification Logic:
- **Keyword Matching**: Fast path checking for action indicators
  - "create event" → `action(.createEvent)`
  - "add note" → `action(.createNote)`
  - "remind me" → `action(.createEvent)` (implicit event)
- **Semantic Fallback**: Uses LLM for ambiguous cases
  - Method: `classifyIntentWithLLM()`
  - Used when keyword matching is inconclusive

---

### 9. Information Extraction

#### InformationExtractor (InformationExtractor.swift)
- **Purpose**: Parses natural language to extract structured action data
- **Method**: Uses LLM with detailed extraction prompts
- **Inputs**: User message + existing action + conversation context
- **Outputs**: Updated InteractiveAction with extracted fields

##### Extraction Handles:
- **Event Details**: Title, date (natural language like "tomorrow", "next Friday"), time, description, recurrence patterns
- **Note Details**: Title, content (from multi-turn accumulation)
- **Target Item**: Which event/note to update/delete
- **Optional Fields**: Reminders, all-day flag, end time

##### Context-Aware Extraction:
- Uses conversation history for implicit references
- Handles pronouns: "add to that event" → references lastEventCreated
- Temporal understanding: "move it to today" → understands relative dates

---

### 10. State Management & Data Flow

#### Conversation Lifecycle:
```
User enters question/action query
    ↓
SearchService.performSearch()
    ├→ isQuestion() → startConversation()
    └→ isAction() → startConversationalAction()
    
For Normal Conversation:
    User: "What events do I have tomorrow?"
    ↓
    SearchService.addConversationMessage()
    ↓
    OpenAIService.answerQuestion() [with full app context]
    ↓
    Assistant message added to conversationHistory
    ↓
    Saved to local UserDefaults

For Action Conversation:
    User: "Create an event called meeting tomorrow at 2pm"
    ↓
    startConversationalAction()
    ↓
    InformationExtractor parses message
    ↓
    ConversationActionHandler determines missing fields
    ↓
    Ask user: "What should I call this event?" (if title not clear)
    ↓
    User responds, extract more info
    ↓
    isReadyToSave() = true
    ↓
    executeConversationalAction()
    ↓
    Show ActionConfirmationView
    ↓
    User confirms
    ↓
    confirmEventCreation() → TaskManager.addTask()
    ↓
    Add success message to conversationHistory
    ↓
    Check for multi-actions, repeat if needed
```

#### Multi-Action Support:
```
User: "Create meeting tomorrow and add notes for both"
    ↓
QueryRouter detects multiple actions
    ↓
pendingMultiActions = [
    (.createEvent, "Create meeting tomorrow"),
    (.createNote, "Add notes for both")
]
    ↓
currentMultiActionIndex = 0
    ↓
Process first action (meeting)
    ↓
On completion: currentMultiActionIndex += 1
    ↓
Process second action (note)
    ↓
All completed
```

---

### 11. Key Integration Points

#### With TaskManager:
- `confirmEventCreation()` → `TaskManager.shared.addTask()`
- Passes: title, description, date, time, recurrence, reminders
- Used for calendar/event creation via chat

#### With NotesManager:
- `confirmNoteCreation()` → `NotesManager.shared.addNote()`
- `confirmNoteUpdate()` → `NotesManager.shared.updateNoteAndWaitForSync()`
- Passes: title, content for new notes; target title + content for updates

#### With OpenAIService:
- Conversational Q&A with full context
- Information extraction from natural language
- Intent detection
- Semantic similarity for search ranking
- Embedding generation for semantic search

#### With ConversationContextService:
- Tracks recent searches
- Extracts topics for context
- Boosts search results based on conversation context
- Detects follow-up questions

---

### 12. Current Limitations & Patterns

#### Message Display:
- User messages: Right-aligned bubbles
- Assistant messages: Left-aligned bubbles
- Full text visibility with unlimited line wrapping
- Text selection enabled for copying

#### Conversation Storage:
- Local: UserDefaults (in-app conversation history)
- Cloud: Supabase (for cross-device sync)
- Auto-save: On every new message

#### Action Confirmation:
- Two-step process: Build action → Show confirmation
- Users can cancel before confirming
- Multi-actions show progress indicator

#### Error Handling:
- Failed API calls → User sees error message in chat
- Rate limits → Automatic retry with exponential backoff
- Network errors → Fallback to local context

---

### 13. Supporting Services

#### Related Data Items:
- Automatically extracted during conversation
- Links messages to events/notes/locations
- Enables cross-app context awareness

#### QueryIntent Integration:
- Assigned to each message for categorization
- Used for filtering and context
- Associated with icons/colors for UI

#### ConversationTitle Generation:
- Dynamic: First user message (first few words)
- Final: LLM-generated summary on conversation close
- Persisted with conversation

---

## Summary

The LLM chat system is a **multi-layered, stateful architecture** that:

1. **Classifies** incoming queries into categories (action vs. search vs. question)
2. **Maintains** rich conversation context across multiple data sources
3. **Handles** multi-turn action building for complex operations (events, notes)
4. **Integrates** OpenAI APIs for understanding and generation
5. **Manages** state through reactive @Published properties
6. **Persists** conversations locally and to cloud
7. **Displays** messages in a thread format with appropriate styling
8. **Extracts** structured data from natural language for app operations
9. **Provides** context-aware responses using full app data (weather, locations, tasks, notes, emails, news)

The system elegantly bridges **conversational AI** with **app-specific actions**, enabling users to interact naturally while building structured data through dialog.
