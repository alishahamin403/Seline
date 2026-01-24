import Foundation

/**
 * ActionState - Focused state for pending actions and interactive modes
 *
 * Split from SearchService to reduce over-subscription.
 * Views that only care about pending actions can subscribe to just this.
 */
@MainActor
class ActionState: ObservableObject {
    // MARK: - Published Properties

    // Pending creations
    @Published var pendingEventCreation: EventCreationData?
    @Published var pendingNoteCreation: NoteCreationData?
    @Published var pendingNoteUpdate: NoteUpdateData?

    // Interactive actions
    @Published var currentInteractiveAction: InteractiveAction?
    @Published var actionPrompt: String?
    @Published var isWaitingForActionResponse: Bool = false
    @Published var actionSuggestions: [NoteSuggestion] = []

    // Note refinement mode
    @Published var isRefiningNote: Bool = false
    @Published var currentNoteBeingRefined: Note?
    @Published var pendingRefinementContent: String?

    // Multi-action support
    @Published var pendingMultiActions: [(actionType: ActionType, query: String)] = []
    @Published var currentMultiActionIndex: Int = 0

    // MARK: - Private State

    private var originalMultiActionQuery: String = ""

    // MARK: - Public Methods

    func setPendingEventCreation(_ data: EventCreationData?) {
        pendingEventCreation = data
    }

    func setPendingNoteCreation(_ data: NoteCreationData?) {
        pendingNoteCreation = data
    }

    func setPendingNoteUpdate(_ data: NoteUpdateData?) {
        pendingNoteUpdate = data
    }

    func startInteractiveAction(_ action: InteractiveAction, prompt: String? = nil) {
        currentInteractiveAction = action
        actionPrompt = prompt
        isWaitingForActionResponse = true
    }

    func completeInteractiveAction() {
        currentInteractiveAction = nil
        actionPrompt = nil
        isWaitingForActionResponse = false
        actionSuggestions = []
    }

    func startNoteRefinement(note: Note, content: String) {
        isRefiningNote = true
        currentNoteBeingRefined = note
        pendingRefinementContent = content
    }

    func completeNoteRefinement() {
        isRefiningNote = false
        currentNoteBeingRefined = nil
        pendingRefinementContent = nil
    }

    func setMultiActions(_ actions: [(ActionType, String)], originalQuery: String) {
        pendingMultiActions = actions
        currentMultiActionIndex = 0
        originalMultiActionQuery = originalQuery
    }

    func advanceToNextAction() {
        currentMultiActionIndex += 1
    }

    func clearMultiActions() {
        pendingMultiActions = []
        currentMultiActionIndex = 0
        originalMultiActionQuery = ""
    }

    var hasMoreActions: Bool {
        currentMultiActionIndex < pendingMultiActions.count
    }
}

// MARK: - Supporting Types (placeholders - actual types defined elsewhere)

struct EventCreationData {
    let title: String
    let date: Date?
    let time: Date?
}

struct NoteCreationData {
    let title: String
    let content: String
}

struct NoteUpdateData {
    let noteId: UUID
    let updates: [String: Any]
}

struct InteractiveAction {
    let type: ActionType
    let data: [String: Any]
}

enum ActionType {
    case createEvent
    case createNote
    case updateNote
    case deleteNote
    case other(String)
}

struct NoteSuggestion {
    let title: String
    let content: String
}

// Placeholder for Note (actual Note is in NoteModels.swift)
struct Note {
    let id: UUID
}

// Placeholder for ConversationMessage (actual type defined elsewhere)
struct ConversationMessage {
    let id: UUID
    var content: String
    let role: String
    let timestamp: Date
}

// Placeholder for SavedConversation (actual type defined elsewhere)
struct SavedConversation {
    let id: UUID
    let title: String
    let messages: [ConversationMessage]
    let createdAt: Date
}
