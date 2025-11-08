# Action/Event/Note Creation Methods and Properties

## Overview
The codebase has a comprehensive system for creating notes, events, and actions from chatbot responses. This document outlines all methods and properties that handle action/event creation so they can be disabled if needed.

---

## 1. Core Service Classes

### A. ConversationActionHandler.swift
**Location:** `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Services/ConversationActionHandler.swift`

**Main Methods:**
- `startAction(from:actionType:conversationContext:)` - Initiates action building from user message
- `processFollowUp(userMessage:action:conversationContext:)` - Processes follow-up messages
- `getNextPrompt(for:conversationContext:)` - Determines next prompt to show user
- `processUserResponse(_:to:currentStep:conversationContext:)` - Processes user responses
- `isReadyToSave(_:)` - Checks if action is ready for execution
- `compileEventData(from:)` - Converts interactive action to EventCreationData
- `compileNoteData(from:)` - Converts interactive action to NoteCreationData
- `compileNoteUpdateData(from:)` - Converts to NoteUpdateData
- `compileDeletionData(from:)` - Converts to DeletionData
- `getConfirmationSummary(for:)` - Gets confirmation summary to show user

**Private Methods:**
- `getEventPrompt(for:)` - Generates prompts for event creation
- `getNotePrompt(for:)` - Generates prompts for note creation
- `getDeletePrompt(for:)` - Generates prompts for deletion
- `generateEventQuestion(for:action:)` - Generates specific event questions

---

### B. InteractiveEventBuilder.swift
**Location:** `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Services/InteractiveEventBuilder.swift`

**Main Methods:**
- `getNextStep(for:)` - Determines next step in event building flow
- `generateClarifyingQuestions(for:)` - Generates clarifying questions for missing info
- `generateOptionalSuggestions(for:)` - Generates suggestions for optional fields
- `processResponse(_:to:action:)` - Processes user's answers to clarifying questions
- `getConfirmationSummary(for:)` - Gets formatted summary for confirmation

**Enums:**
```swift
enum BuilderStep {
    case askForMissingField(String, action: InteractiveAction)
    case confirmExtracted(action: InteractiveAction)
    case offerOptionalFields(action: InteractiveAction)
    case readyToSave(action: InteractiveAction)
}
```

---

### C. InteractiveNoteBuilder.swift
**Location:** `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Services/InteractiveNoteBuilder.swift`

**Main Methods:**
- `getNextStep(for:)` - Determines next step in note building (includes "Want to add more?" logic)
- `generateSuggestions(for:context:)` - Generates LLM-powered suggestions for enhancing notes
- `generateContentForSuggestion(type:currentContent:relatedText:)` - Generates content for suggestions
- `processResponse(_:to:action:)` - Processes user responses (handles "Want to add more?" case)
- `getPromptMessage(for:)` - Gets friendly message for current step
- `formatNotePreview(content:)` - Formats note content for display

**Key "Want to add more?" Logic:**
```swift
case .askAddMore:
    let shouldAddMore = response.lowercased().contains("yes") ||
                      response.lowercased().contains("want to add") ||
                      response.lowercased().contains("have more")
    
    if shouldAddMore {
        action.extractionState.isShowingSuggestions = true
    } else {
        action.extractionState.isComplete = true
    }
```

**Enums:**
```swift
enum NoteBuilderStep {
    case askForTitle
    case askForContent(suggestedTitle: String)
    case askWhichNoteToUpdate
    case askWhatToAdd
    case askAddMore(currentContent: String)  // KEY: "Want to add more?" prompt
    case offerSuggestions(action: InteractiveAction)
}

enum NoteSuggestionType: String {
    case lookup = "lookup"
    case remind = "remind"
    case details = "details"
    case format = "format"
}
```

---

### D. InformationExtractor.swift
**Location:** `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Services/InformationExtractor.swift`

**Main Methods:**
- `extractFromMessage(_:existingAction:conversationContext:)` - Extracts action info from user messages
- `extractEventInfo(_:context:action:)` - Extracts event-specific information
- `extractUpdateEventInfo(_:context:action:)` - Extracts update-event information
- `extractDeleteInfo(_:context:action:)` - Extracts deletion information
- `extractNoteInfo(_:context:action:)` - Extracts note-specific information

---

## 2. Service Class: SearchService.swift
**Location:** `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Services/SearchService.swift`

### Published Properties (Observable State):
```swift
@Published var pendingEventCreation: EventCreationData?
@Published var pendingNoteCreation: NoteCreationData?
@Published var pendingNoteUpdate: NoteUpdateData?

// Conversational action system
@Published var currentInteractiveAction: InteractiveAction?
@Published var actionPrompt: String? = nil
@Published var isWaitingForActionResponse: Bool = false
@Published var actionSuggestions: [NoteSuggestion] = []

// Multi-action support
@Published var pendingMultiActions: [(actionType: ActionType, query: String)] = []
@Published var currentMultiActionIndex: Int = 0

// Note refinement mode
@Published var isRefiningNote: Bool = false
@Published var currentNoteBeingRefined: Note? = nil
@Published var pendingRefinementContent: String? = nil
```

### Key Methods:

#### Action Confirmation Methods:
- `confirmEventCreation()` - Confirms and saves event (lines 170-260)
- `confirmNoteCreation()` - Confirms and saves note (lines 262-279)
- `confirmNoteUpdate()` - Confirms and updates note (lines 281-313)
- `cancelAction()` - Cancels pending action (lines 315-339)

#### Conversational Action Methods:
- `startConversationalAction(userMessage:actionType:)` - Initiates action building (lines 765-804)
- `continueConversationalAction(userMessage:)` - Continues action conversation (lines 807-849)
- `executeConversationalAction(_:)` - Executes the built action (lines 852-929)
- `processNextMultiAction()` - Processes next action in queue (lines 133-166)

#### Internal Context Tracking:
```swift
private var lastCreatedEventTitle: String? = nil
private var lastCreatedEventDate: String? = nil
private var lastCreatedNoteTitle: String? = nil
```

---

## 3. Data Models: ConversationalActionModels.swift
**Location:** `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Models/ConversationalActionModels.swift`

### Enum: ActionType
```swift
enum ActionType: String, Codable {
    case createEvent
    case updateEvent
    case deleteEvent
    case createNote
    case updateNote
    case deleteNote
}
```

### Struct: InteractiveAction
```swift
struct InteractiveAction: Equatable {
    let id: UUID
    let type: ActionType
    var extractedInfo: ExtractedActionInfo
    var extractionState: ExtractionState
    var clarifyingQuestions: [ClarifyingQuestion] = []
    var suggestions: [ActionSuggestion] = []
    var conversationTurns: Int = 0
}
```

### Struct: ExtractionState
Key properties for tracking action completion:
```swift
struct ExtractionState: Equatable {
    var isExtracting: Bool = true
    var isAskingClarifications: Bool = false
    var isShowingSuggestions: Bool = false
    var isConfirming: Bool = false
    var isComplete: Bool = false
    var confirmedFields: Set<String> = []
    var requiredFields: Set<String> = []
    var optionalFields: Set<String> = []
    var currentFocusField: String?
    
    mutating func confirmField(_ field: String)
    var missingRequiredFields: [String]
    var nextFieldToConfirm: String?
}
```

### Data Structures for Saving:
```swift
struct EventCreationData: Codable, Equatable
struct NoteCreationData: Codable, Equatable
struct NoteUpdateData: Codable, Equatable
struct DeletionData: Codable, Equatable
struct ClarifyingQuestion: Identifiable, Equatable
struct ActionSuggestion: Identifiable, Equatable
struct EventReminder: Equatable, Codable
struct ConversationActionContext
```

---

## 4. UI Integration
**Location:** `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Views/Components/ConversationSearchView.swift`

### Properties Used:
- `searchService.pendingEventCreation` - Pending event creation data
- `searchService.pendingNoteCreation` - Pending note creation data
- `searchService.currentInteractiveAction` - Current action being built
- `searchService.actionPrompt` - Next prompt to show user
- `searchService.isWaitingForActionResponse` - Waiting for user response

### UI Methods Called:
- `searchService.confirmEventCreation()` - Confirms event creation button
- `searchService.confirmNoteCreation()` - Confirms note creation button
- `searchService.cancelAction()` - Cancels action button
- `searchService.continueConversationalAction(userMessage:)` - Sends user response

---

## 5. Query Classification
**Location:** Related to QueryRouter (referenced in SearchService)

The system classifies queries to determine if they trigger action creation:
- `.action(.createEvent)` - Create event action type
- `.action(.updateEvent)` - Update event action type
- `.action(.deleteEvent)` - Delete event action type
- `.action(.createNote)` - Create note action type
- `.action(.updateNote)` - Update note action type
- `.action(.deleteNote)` - Delete note action type
- `.search` - Regular search (no action)
- `.question` - Conversation question (no action)

---

## 6. Multi-Action Support
The system supports executing multiple actions from a single query:

```swift
@Published var pendingMultiActions: [(actionType: ActionType, query: String)] = []
@Published var currentMultiActionIndex: Int = 0

func processNextMultiAction() async {
    // Processes actions sequentially
    // After each action confirms, moves to next in queue
}
```

---

## 7. Key Confirmation Prompts That Appear

### "Want to add more?" for Notes
- **Location:** `InteractiveNoteBuilder.swift`, line 246
- **Triggered:** After initial note content is added
- **Method:** `getPromptMessage(for: .askAddMore)` returns "Want to add anything else to this note?"
- **User Response Processing:** Lines 206-215

### Event Confirmation
- **Message:** "Does this look correct? I have: [summary]"
- **Location:** `ConversationActionHandler.swift`, line 102

### Optional Field Suggestions for Events
- **Message:** "Would you like to add any of these?"
- **Location:** `ConversationActionHandler.swift`, line 110

---

## Summary of What to Disable

To completely disable action/event creation from chatbot:

### 1. Disable Query Classification
- Modify `QueryRouter` to return `.search` instead of `.action()` types

### 2. Disable ConversationActionHandler
- Comment out or stub:
  - `startAction()`
  - `processFollowUp()`
  - `getNextPrompt()`
  - `processUserResponse()`
  - `isReadyToSave()`
  - All `compile*Data()` methods

### 3. Disable SearchService Action Methods
- Comment out or stub:
  - `startConversationalAction()`
  - `continueConversationalAction()`
  - `executeConversationalAction()`
  - `confirmEventCreation()`
  - `confirmNoteCreation()`
  - `confirmNoteUpdate()`
  - `processNextMultiAction()`

### 4. Disable UI Integration
- Remove pending action UI from `ConversationSearchView`
- Remove confirmation buttons for events/notes
- Remove action prompts display

### 5. Disable Builders (Optional)
- `InteractiveEventBuilder` - Won't be called if actions aren't started
- `InteractiveNoteBuilder` - Won't be called if actions aren't started
- `InformationExtractor` - Won't be called for action types

---

## Related Files
- `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Views/MainAppView.swift` - Uses `.onChange` for pending events/notes
- `/Users/alishahamin/Desktop/Vibecode/Seline/Seline/Services/QueryRouter.swift` - Classifies queries
