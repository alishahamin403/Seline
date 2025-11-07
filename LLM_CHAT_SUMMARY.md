# Seline LLM Chat Functionality - Exploration Complete

## Overview
Successfully explored and documented the complete LLM chat implementation in the Seline iOS app. This is a sophisticated, multi-layered system that integrates conversational AI with app-specific actions.

## Key Findings

### 1. Architecture Pattern
The system uses a **Service-Oriented Architecture** with:
- **Singleton Services**: SearchService, OpenAIService, ConversationActionHandler
- **Observable State Management**: Using @Published properties for reactive updates
- **Separation of Concerns**: Each layer handles specific responsibilities

### 2. Three Main Conversation Modes

#### A. Simple Questions & Answers
User: "What events do I have tomorrow?"
→ Full app context (tasks, notes, emails, weather, locations, news)
→ LLM generates contextual response with all relevant data
→ Displayed in conversation thread

#### B. Conversational Actions (Multi-Turn)
User: "Create event tomorrow at 2pm"
→ Extracts information from natural language
→ Builds InteractiveAction with extracted fields
→ Asks clarifying questions for missing required fields
→ Shows confirmation preview
→ Saves to app on user confirmation
→ Supports multi-action queries ("create event AND add note")

#### C. Content Search
User: "Find my notes about budgeting"
→ Keyword + semantic similarity search
→ Ranks by relevance score
→ Context-aware boosting based on recent conversation

### 3. Core Components

#### Message Models
- **ConversationMessage**: Individual messages with intent classification
- **SavedConversation**: Complete conversation sessions with auto-generated titles
- **QueryIntent**: Categorizes messages (calendar, notes, locations, general)

#### State Management
- **SearchService**: Central orchestrator for all query types
- **ConversationContextService**: Tracks conversation context, topics, suggestions
- **OpenAIService**: LLM integration with context building

#### Action Building
- **ConversationActionHandler**: Orchestrates multi-turn action workflows
- **InteractiveAction**: State container for building events/notes
- **InformationExtractor**: Parses natural language to structured data

#### UI Components
- **ConversationSearchView**: Main conversation interface
- **ConversationMessageView**: Individual message display (user/assistant)
- **ActionConfirmationView**: Confirmation panel for pending actions
- **ConversationHistoryView**: List of saved conversations

### 4. Data Flow

```
User Input
    ↓
Query Classification (SearchService)
    ├─ Is Question? → Answer with full context
    ├─ Is Action? → Build action through multi-turn dialog
    └─ Is Search? → Semantic + keyword search

For Actions:
    → Extract information from message
    → Check which fields are complete
    → Ask for missing required fields
    → On completion: Show confirmation
    → On user confirmation: Save to app
    → Process next action if multi-action
```

### 5. LLM Integration Points

#### Models Used:
- **gpt-4o**: For high-quality, precise outputs (email summaries, responses)
- **gpt-4o-mini**: For fast/cheap tasks (intent detection, extractions)
- **text-embedding-3-small**: For semantic similarity (search ranking)

#### Context Building:
1. **Date/Time Context**: For relative queries ("tomorrow", "next week")
2. **App Data**: Full access to tasks, notes, emails, locations, weather
3. **Conversation History**: Full previous messages for context
4. **Selective Filtering**: News articles only if query mentions news

#### Rate Limiting:
- 2-second minimum between requests
- Embedding caching to avoid repeated API calls
- Batch processing for semantic similarity scores

### 6. State Management Approach

**SearchService** maintains @Published properties:
- `conversationHistory`: Array of ConversationMessage
- `currentInteractiveAction`: The action being built
- `pendingMultiActions`: Queue of multiple actions
- `pendingEventCreation`: Event confirmation pending
- `pendingNoteCreation`: Note confirmation pending

State flows through UI reactively:
- Changes to @Published properties trigger UI updates
- User interactions modify state
- Services handle side effects (API calls, persistence)

### 7. Persistence Strategy

#### Local Storage (UserDefaults):
- SavedConversation objects stored as JSON
- Fast access for recent conversations
- Auto-loaded on app start

#### Cloud Storage (Supabase):
- Synced when user dismisses conversation
- For cross-device access
- Called in onDisappear of ConversationSearchView

#### Auto-Save:
- Every new message triggers local save
- Conversation title auto-generated on close

### 8. Conversation Title Generation

**Dynamic Title**: First user message (first 4 words)
**Final Title**: LLM-summarized on conversation close
```swift
"What events do I have..." → "What events do I have"
[After conversation closes] → "Upcoming Calendar Events"
```

### 9. Multi-Action Support

Enables natural language like:
"Create meeting tomorrow and add notes for both"

Implementation:
1. QueryRouter detects multiple actions
2. Store in `pendingMultiActions` queue
3. Process first action
4. After confirmation, increment `currentMultiActionIndex`
5. Process next action
6. Show progress: "Action 1 of 2"

### 10. Context Awareness Features

#### ConversationContextService:
- Tracks last 20 searches
- Extracts topics (hashtags, category keywords)
- Detects follow-ups using Levenshtein distance
- Boosts search results for related topics
- Suggests related searches

#### Example:
User searches "budget", then "expenses" later
→ System detects both are finance-related
→ Boosts finance-related items in results
→ Suggests "finance" as related topic

## File Locations

| Component | File |
|-----------|------|
| Models | `ConversationModels.swift` |
| UI Views | `ConversationSearchView.swift`, `ConversationHistoryView.swift` |
| State | `SearchService.swift` |
| Actions | `ConversationActionHandler.swift`, `ConversationalActionModels.swift` |
| Context | `ConversationContextService.swift` |
| Extraction | `InformationExtractor.swift` (referenced) |
| LLM API | `OpenAIService.swift` |
| Routing | `QueryRouter.swift` (referenced) |

## Key Insights

### Strengths:
1. **Unified Conversation Interface**: Questions, actions, and search in one flow
2. **Rich Context**: Every response includes full app state
3. **Multi-Turn Intelligence**: Remembers conversation history for follow-ups
4. **Graceful Multi-Action**: Handles "do X and Y" in one go
5. **Semantic Search**: Uses embeddings for meaningful results
6. **Persistent History**: Conversations saved locally and to cloud
7. **Natural Language Processing**: Parses dates, times, pronouns naturally

### Patterns Used:
1. **Singleton Pattern**: Services as singletons
2. **Observable Pattern**: @Published for reactive updates
3. **Builder Pattern**: InteractiveAction builds through multi-turn dialog
4. **Strategy Pattern**: Different handlers for different action types
5. **Context Passing**: ConversationActionContext provides full context

### Design Decisions:
1. **@MainActor for ConversationActionHandler**: Ensures UI consistency
2. **Rate Limiting**: Prevents API quota exhaustion
3. **Embedding Caching**: Reduces API calls for repeated phrases
4. **Batch Processing**: More efficient semantic similarity for multiple items
5. **Two-Step Confirmation**: Build action → Show preview → Confirm

## Summary Statistics

- **13 main Swift files explored**
- **8 core service classes**
- **5 key view components**
- **6 action types supported**
- **3 query classification types**
- **2 LLM integration patterns** (full context vs. information extraction)
- **2 storage backends** (local + cloud)

## Next Steps for Enhancement

1. **Streaming Responses**: For long LLM responses
2. **Rich Media**: Images, files in chat
3. **Action Suggestions**: AI-powered suggestions for next actions
4. **Context Persistence**: Remember user preferences across conversations
5. **Offline Mode**: Cache responses for offline access
6. **Custom Prompts**: Let users define custom action templates

---

**Documentation Generated**: November 6, 2025
**Comprehensive Overview**: LLM_CHAT_ARCHITECTURE.md
**Visual Diagram**: ARCHITECTURE_DIAGRAM.txt
