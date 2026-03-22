import Foundation

@MainActor
final class TrackerParserService {
    static let shared = TrackerParserService()

    private let engine = TrackerEngine.shared
    private let gemini = GeminiService.shared

    private init() {}

    func normalizedThread(_ thread: TrackerThread) -> TrackerThread {
        let normalizedSnapshot = normalizedMemorySnapshot(thread.memorySnapshot)
        guard normalizedSnapshot != thread.memorySnapshot else {
            return thread
        }

        var updatedThread = thread
        updatedThread.memorySnapshot = normalizedSnapshot
        updatedThread.cachedState = engine.deriveState(for: updatedThread)

        let existingSubtitle = updatedThread.subtitle?.trackerNonEmpty
        let priorSummary = thread.cachedState?.summaryLine ?? thread.memorySnapshot.normalizedSummaryText.trackerNonEmpty
        if existingSubtitle == nil || existingSubtitle == priorSummary {
            updatedThread.subtitle = updatedThread.cachedState?.summaryLine
        }

        return updatedThread
    }

    func handleMessage(
        _ text: String,
        in thread: TrackerThread?,
        conversationHistory: [ConversationMessage]
    ) async -> TrackerChatOutcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return TrackerChatOutcome(
                intent: .clarification,
                responseText: "Describe the tracker rules or tell me what changed.",
                shouldPersistAssistantMessage: true
            )
        }

        if let thread {
            return await handleExistingTrackerMessage(
                trimmed,
                in: thread,
                conversationHistory: conversationHistory
            )
        }

        return await handleTrackerCreation(trimmed)
    }

    func applyDraft(_ draft: TrackerOperationDraft, to thread: TrackerThread?) -> TrackerApplyResult {
        switch draft.type {
        case .createTracker:
            guard let proposedMemorySnapshot = draft.proposedMemorySnapshot else {
                return TrackerApplyResult(thread: thread, didApply: false, message: "The tracker draft is incomplete, so nothing was saved.")
            }

            let title = proposedMemorySnapshot.title.trackerNonEmpty ?? "Tracker"
            var createdThread = TrackerThread(
                title: title,
                memorySnapshot: proposedMemorySnapshot
            )
            createdThread.cachedState = engine.deriveState(for: createdThread)
            createdThread.subtitle = createdThread.cachedState?.summaryLine
            return TrackerApplyResult(thread: createdThread, didApply: true, message: "Tracker created.")

        case .updateRules, .updateState:
            guard var thread, let proposedMemorySnapshot = draft.proposedMemorySnapshot else {
                return TrackerApplyResult(thread: thread, didApply: false, message: "I could not apply that tracker change.")
            }

            thread.title = proposedMemorySnapshot.title.trackerNonEmpty ?? thread.title
            thread.memorySnapshot = proposedMemorySnapshot
            thread.updatedAt = Date()
            thread.cachedState = engine.deriveState(for: thread)
            thread.subtitle = thread.cachedState?.summaryLine
            return TrackerApplyResult(thread: thread, didApply: true, message: "Tracker updated.")

        case .whatIf, .clarification:
            return TrackerApplyResult(thread: thread, didApply: false, message: "There is nothing to save for that draft.")
        }
    }

    func draftUndoLastChange(
        in thread: TrackerThread,
        conversationHistory: [ConversationMessage]
    ) async -> TrackerChatOutcome {
        guard let latestChange = thread.memorySnapshot.changeLog.sorted(by: mostRecentChangeFirst).first else {
            return TrackerChatOutcome(
                intent: .clarification,
                responseText: "There is no saved tracker change to undo yet.",
                derivedState: engine.deriveState(for: thread),
                shouldPersistAssistantMessage: true
            )
        }

        guard let extraction = await extractUndoLastChange(
            targetChange: latestChange,
            in: thread,
            conversationHistory: conversationHistory
        ) else {
            return TrackerChatOutcome(
                intent: .clarification,
                responseText: "I could not draft an undo for the latest tracker change.",
                derivedState: engine.deriveState(for: thread),
                shouldPersistAssistantMessage: true
            )
        }

        let intent = resolvedIntent(from: extraction.intent)
        guard intent == .updateState || intent == .editRules else {
            return TrackerChatOutcome(
                intent: .clarification,
                responseText: extraction.clarificationPrompt?.trackerNonEmpty ?? "I need more context before I can undo the latest change.",
                derivedState: engine.deriveState(for: thread),
                shouldPersistAssistantMessage: true
            )
        }

        return buildDraftOutcome(
            from: extraction,
            intent: intent,
            in: thread,
            requiresConfirmation: true
        )
    }

    // MARK: - Creation

    private func handleTrackerCreation(_ text: String) async -> TrackerChatOutcome {
        guard let extraction = await extractTrackerCreation(from: text) else {
            return TrackerChatOutcome(
                intent: .clarification,
                responseText: "Describe the tracker rules you want me to remember, and I will draft the tracker for confirmation.",
                shouldPersistAssistantMessage: true
            )
        }

        let intent = resolvedIntent(from: extraction.intent)
        guard intent == .createTracker else {
            return TrackerChatOutcome(
                intent: .clarification,
                responseText: extraction.clarificationPrompt?.trackerNonEmpty ?? "Describe the tracker rules you want me to remember, and I will draft the tracker for confirmation.",
                shouldPersistAssistantMessage: true
            )
        }

        guard let rulesText = extraction.rulesText?.trackerNonEmpty else {
            return TrackerChatOutcome(
                intent: .clarification,
                responseText: extraction.clarificationPrompt?.trackerNonEmpty ?? "I need the actual rules for the tracker before I can create it.",
                shouldPersistAssistantMessage: true
            )
        }

        let title = extraction.title?.trackerNonEmpty ?? suggestedTitle(from: text)
        let memorySnapshot = TrackerMemorySnapshot(
            title: title,
            rulesText: rulesText,
            currentSummary: extraction.currentSummary?.trackerNonEmpty ?? "No tracked updates yet.",
            quickFacts: sanitizedFacts(extraction.quickFacts),
            notes: extraction.notes?.trackerNonEmpty
        )

        let projectedState = engine.projectedState(
            for: memorySnapshot,
            on: TrackerThread(title: title, memorySnapshot: memorySnapshot)
        )

        let draft = TrackerOperationDraft(
            intent: .createTracker,
            type: .createTracker,
            requiresConfirmation: true,
            summaryText: "Create \(title) with the saved rules and summary.",
            assistantResponse: "I drafted a tracker from your rules. Confirm it if it looks right.",
            confidence: extraction.confidence ?? 0.8,
            proposedMemorySnapshot: memorySnapshot,
            projectedState: projectedState
        )

        return TrackerChatOutcome(
            intent: .createTracker,
            responseText: draft.assistantResponse,
            draft: draft,
            derivedState: projectedState,
            shouldPersistAssistantMessage: true
        )
    }

    // MARK: - Existing Tracker

    private func handleExistingTrackerMessage(
        _ text: String,
        in thread: TrackerThread,
        conversationHistory: [ConversationMessage]
    ) async -> TrackerChatOutcome {
        guard let extraction = await resolveTrackerAction(
            from: text,
            in: thread,
            conversationHistory: conversationHistory
        ) else {
            return TrackerChatOutcome(
                intent: .clarification,
                responseText: "I can restate the tracker rules, summarize the current state, or draft a tracked change. Tell me what changed or what you want to recall.",
                shouldPersistAssistantMessage: true
            )
        }

        let intent = resolvedIntent(from: extraction.intent)
        switch intent {
        case .askRules:
            let state = engine.deriveState(for: thread)
            let response = await explainTrackerState(
                userMessage: text,
                thread: thread,
                state: state,
                conversationHistory: conversationHistory,
                fallback: state.ruleSummary
            )
            return TrackerChatOutcome(
                intent: .askRules,
                responseText: response,
                derivedState: state,
                commitsProjectedStateToThread: true,
                shouldPersistAssistantMessage: true
            )

        case .askState:
            let state = engine.deriveState(for: thread)
            let response = await explainTrackerState(
                userMessage: text,
                thread: thread,
                state: state,
                conversationHistory: conversationHistory,
                fallback: state.summaryLine
            )
            return TrackerChatOutcome(
                intent: .askState,
                responseText: response,
                derivedState: state,
                commitsProjectedStateToThread: true,
                shouldPersistAssistantMessage: true
            )

        case .editRules, .updateState:
            return buildDraftOutcome(
                from: extraction,
                intent: intent,
                in: thread,
                requiresConfirmation: true
            )

        case .whatIf:
            return await buildWhatIfOutcome(
                from: extraction,
                in: thread,
                conversationHistory: conversationHistory
            )

        case .createTracker:
            return TrackerChatOutcome(
                intent: .clarification,
                responseText: "This tracker already exists. Tell me what rule changed or what should be updated in the tracked summary.",
                shouldPersistAssistantMessage: true
            )

        case .clarification:
            return TrackerChatOutcome(
                intent: .clarification,
                responseText: extraction.clarificationPrompt?.trackerNonEmpty ?? "Tell me what changed, or ask me to show the current rules or summary.",
                shouldPersistAssistantMessage: true
            )
        }
    }

    private func buildDraftOutcome(
        from extraction: TrackerLLMExtraction,
        intent: TrackerChatIntent,
        in thread: TrackerThread,
        requiresConfirmation: Bool
    ) -> TrackerChatOutcome {
        guard let proposal = buildProposedSnapshot(
            from: extraction,
            on: thread,
            includeChangeInLog: true
        ) else {
            return TrackerChatOutcome(
                intent: .clarification,
                responseText: extraction.clarificationPrompt?.trackerNonEmpty ?? "I need a clearer tracker update before I can draft it.",
                shouldPersistAssistantMessage: true
            )
        }

        let proposedMemorySnapshot = proposal.snapshot
        let changeType = resolvedChangeType(from: extraction.changeType, intent: intent)
        let projectedState = engine.projectedState(for: proposedMemorySnapshot, on: thread)
        let summaryText = extraction.confirmationSummary?.trackerNonEmpty
            ?? proposal.change?.content.trackerNonEmpty
            ?? defaultConfirmationSummary(for: intent, type: changeType)

        let draft = TrackerOperationDraft(
            intent: intent,
            type: intent == .editRules ? .updateRules : .updateState,
            requiresConfirmation: requiresConfirmation,
            summaryText: summaryText,
            assistantResponse: requiresConfirmation
                ? "I drafted the tracker update. Confirm it if it looks right."
                : projectedState.summaryLine,
            confidence: extraction.confidence ?? 0.8,
            proposedMemorySnapshot: proposedMemorySnapshot,
            proposedChange: proposal.change,
            projectedState: projectedState
        )

        return TrackerChatOutcome(
            intent: intent,
            responseText: draft.assistantResponse,
            draft: draft,
            derivedState: projectedState,
            shouldPersistAssistantMessage: true
        )
    }

    private func buildWhatIfOutcome(
        from extraction: TrackerLLMExtraction,
        in thread: TrackerThread,
        conversationHistory: [ConversationMessage]
    ) async -> TrackerChatOutcome {
        guard let proposal = buildProposedSnapshot(
            from: extraction,
            on: thread,
            includeChangeInLog: true
        ) else {
            return TrackerChatOutcome(
                intent: .clarification,
                responseText: extraction.clarificationPrompt?.trackerNonEmpty ?? "Tell me the hypothetical change you want me to reason about.",
                shouldPersistAssistantMessage: true
            )
        }

        let proposedMemorySnapshot = proposal.snapshot
        let projectedState = engine.projectedState(for: proposedMemorySnapshot, on: thread)
        let response = await explainTrackerState(
            userMessage: extraction.assistantResponse?.trackerNonEmpty ?? "What if this change were applied?",
            thread: TrackerThread(
                id: thread.id,
                title: proposedMemorySnapshot.title.trackerNonEmpty ?? thread.title,
                status: thread.status,
                memorySnapshot: proposedMemorySnapshot,
                cachedState: projectedState,
                createdAt: thread.createdAt,
                updatedAt: thread.updatedAt,
                lastSyncedAt: thread.lastSyncedAt,
                subtitle: projectedState.summaryLine
            ),
            state: projectedState,
            conversationHistory: conversationHistory,
            fallback: projectedState.summaryLine
        )

        let draft = TrackerOperationDraft(
            intent: .whatIf,
            type: .whatIf,
            requiresConfirmation: false,
            summaryText: extraction.confirmationSummary?.trackerNonEmpty ?? "Hypothetical tracker update.",
            assistantResponse: response,
            confidence: extraction.confidence ?? 0.8,
            proposedMemorySnapshot: proposedMemorySnapshot,
            proposedChange: proposal.change,
            projectedState: projectedState
        )

        return TrackerChatOutcome(
            intent: .whatIf,
            responseText: response,
            draft: draft,
            derivedState: projectedState,
            shouldPersistAssistantMessage: true
        )
    }

    // MARK: - LLM

    private func extractTrackerCreation(from text: String) async -> TrackerLLMExtraction? {
        let prompt = """
        Convert this request into a generic tracker draft.

        Return JSON only.

        Intent values:
        - create_tracker
        - clarification

        Rules:
        - This is a generic tracker that may track money, counts, points, habits, schedules, or any other user-defined state.
        - Normalize the rules into concise plain text in rulesText.
        - Preserve concrete numbers, names, dates, caps, turns, and carryover rules exactly when the user provides them.
        - Summarize the starting state in currentSummary.
        - quickFacts should be 2-4 short current-state facts optimized for compact UI cards.
        - Prefer facts that capture the latest status, such as balances, amounts left, counts completed or remaining, next due item, active owner, or current totals when relevant.
        - Do not repeat the tracker title inside quickFacts.
        - If the request does not actually define tracker rules, return clarification.

        JSON shape:
        {
          "intent": "create_tracker",
          "title": "Short tracker title",
          "rulesText": "Canonical rules text",
          "currentSummary": "Starting summary",
          "quickFacts": ["fact one", "fact two"],
          "changeType": null,
          "changeTitle": null,
          "changeContent": null,
          "assistantResponse": null,
          "confirmationSummary": "Short confirmation line",
          "clarificationPrompt": null,
          "notes": "Optional notes",
          "confidence": 0.9
        }

        User request:
        \(text)
        """

        return await runExtractionPrompt(prompt, operationType: "tracker_create")
    }

    private func resolveTrackerAction(
        from text: String,
        in thread: TrackerThread,
        conversationHistory: [ConversationMessage]
    ) async -> TrackerLLMExtraction? {
        let primaryExtraction = await extractTrackerAction(
            from: text,
            in: thread,
            conversationHistory: conversationHistory
        )

        if let primaryExtraction {
            let primaryIntent = resolvedIntent(from: primaryExtraction.intent)
            if primaryIntent != .clarification || !looksLikeStateUpdateMessage(text) {
                return fallbackQueryExtraction(for: text, thread: thread, primary: primaryExtraction)
            }

            return await extractForcedStateUpdate(
                from: text,
                in: thread,
                conversationHistory: conversationHistory
            ) ?? fallbackQueryExtraction(for: text, thread: thread, primary: primaryExtraction)
        }

        guard looksLikeStateUpdateMessage(text) else {
            return fallbackQueryExtraction(for: text, thread: thread)
        }

        return await extractForcedStateUpdate(
            from: text,
            in: thread,
            conversationHistory: conversationHistory
        ) ?? fallbackQueryExtraction(for: text, thread: thread)
    }

    private func extractTrackerAction(
        from text: String,
        in thread: TrackerThread,
        conversationHistory: [ConversationMessage]
    ) async -> TrackerLLMExtraction? {
        let recentTurns = conversationHistory
            .suffix(6)
            .map { message in
                let role = message.isUser ? "User" : "Assistant"
                return "\(role): \(message.text)"
            }
            .joined(separator: "\n")

        let recentChanges = thread.memorySnapshot.changeLog
            .sorted(by: mostRecentChangeFirst)
            .prefix(6)
            .map { change in
                let date = displayDate(change.effectiveAt)
                let title = change.title?.trackerNonEmpty.map { "\($0): " } ?? ""
                return "- [\(date)] \(change.type.rawValue) • \(title)\(change.content)"
            }
            .joined(separator: "\n")

        let prompt = """
        You manage a generic tracker memory inside a dedicated tracker chat.

        Return JSON only.

        Current tracker title:
        \(thread.title)

        RULES:
        \(thread.memorySnapshot.normalizedRulesText)

        CURRENT SUMMARY:
        \(thread.memorySnapshot.normalizedSummaryText.trackerNonEmpty ?? "No tracked updates yet.")

        QUICK FACTS:
        \(thread.memorySnapshot.quickFacts.isEmpty ? "None" : thread.memorySnapshot.quickFacts.joined(separator: " | "))

        RECENT CHANGES:
        \(recentChanges.isEmpty ? "None" : recentChanges)

        RECENT TRACKER TURNS:
        \(recentTurns.isEmpty ? "None" : recentTurns)

        Intent values:
        - ask_rules: the user wants the rules restated
        - ask_state: the user wants the current tracked summary or recall
        - edit_rules: the user is changing the tracker rules
        - update_state: the user is adding, correcting, or updating tracked information
        - what_if: the user wants a hypothetical update that should not be saved
        - clarification: ambiguous or insufficient

        Rules:
        - Do not invent facts beyond the current tracker memory plus the latest user message.
        - Direct factual statements such as "Suju bought underwear for 20 dollars", "log 3 workouts", or "Ali spent 15" are update_state, not clarification.
        - For edit_rules, update_state, and what_if, return the FULL updated rulesText and currentSummary after applying the message.
        - For edit_rules, update_state, and what_if, quickFacts should reflect the updated tracker if they need to change.
        - When changeContent is present, also return changeContext with structured fields for actors, relatedEntities, subject, amount, resultingValue, unit, periodLabel, and tags when they are knowable.
        - Keep quickFacts UI-friendly: 2-4 short current-state facts, not a paragraph.
        - Prefer the latest values the user would care about now, such as what remains, what is due next, who is up, what changed most recently, or the current running total.
        - If RULES and CURRENT SUMMARY conflict, prefer RULES plus RECENT CHANGES and the latest user message, and correct the summary.
        - If the tracker rules imply calculations such as remaining budget, points left, counts completed, or turn rotation, update currentSummary and quickFacts with the recalculated state.
        - If the latest message only asks a question, do not rewrite rulesText or currentSummary.
        - changeType can be rule_change, state_update, correction, or note.
        - changeContent should be a clean canonical sentence for the tracker log.
        - confirmationSummary should be short and user-facing.

        JSON shape:
        {
          "intent": "ask_state",
          "title": "Optional updated title",
          "rulesText": null,
          "currentSummary": null,
          "quickFacts": null,
          "changeType": null,
          "changeTitle": null,
          "changeContent": null,
          "changeContext": null,
          "assistantResponse": "Optional direct answer for queries",
          "confirmationSummary": null,
          "clarificationPrompt": null,
          "notes": null,
          "confidence": 0.9
        }

        Latest user message:
        \(text)
        """

        return await runExtractionPrompt(prompt, operationType: "tracker_update")
    }

    private func extractForcedStateUpdate(
        from text: String,
        in thread: TrackerThread,
        conversationHistory: [ConversationMessage]
    ) async -> TrackerLLMExtraction? {
        let recentTurns = conversationHistory
            .suffix(4)
            .map { message in
                let role = message.isUser ? "User" : "Assistant"
                return "\(role): \(message.text)"
            }
            .joined(separator: "\n")

        let prompt = """
        The latest user message is intended as a real tracker state update.

        Return JSON only.

        TRACKER TITLE:
        \(thread.title)

        RULES:
        \(thread.memorySnapshot.normalizedRulesText)

        CURRENT SUMMARY:
        \(thread.memorySnapshot.normalizedSummaryText.trackerNonEmpty ?? "No tracked updates yet.")

        QUICK FACTS:
        \(thread.memorySnapshot.quickFacts.isEmpty ? "None" : thread.memorySnapshot.quickFacts.joined(separator: " | "))

        RECENT TRACKER TURNS:
        \(recentTurns.isEmpty ? "None" : recentTurns)

        Rules:
        - Prefer intent update_state unless the message is truly impossible to apply.
        - Update rulesText only if the user changed the rules.
        - Always return the FULL updated currentSummary after applying the latest change.
        - Update quickFacts if the tracked state changed.
        - Return changeContext with structured fields for actors, relatedEntities, subject, amount, resultingValue, unit, periodLabel, and tags whenever they can be inferred.
        - Keep quickFacts UI-friendly: 2-4 short current-state facts, not a paragraph.
        - Prefer the latest values the user would care about now, such as what remains, what is due next, who is up, what changed most recently, or the current running total.
        - If RULES and CURRENT SUMMARY conflict, follow RULES and correct the summary.
        - If the rules imply numeric calculations, compute them. Examples include remaining budget, amount left this month, points remaining, counts completed, or quotas left.
        - For expense or budget trackers, subtract the reported spend from the relevant allowance when the rules provide enough information.
        - changeContent should be a concise canonical tracker log entry.
        - confirmationSummary should briefly describe the applied update.

        JSON shape:
        {
          "intent": "update_state",
          "title": null,
          "rulesText": "Full rules text or null if unchanged",
          "currentSummary": "Full updated summary",
          "quickFacts": ["updated fact one"],
          "changeType": "state_update",
          "changeTitle": "Optional short title",
          "changeContent": "Canonical change sentence",
          "changeContext": {
            "actors": ["Person"],
            "relatedEntities": ["Other party"],
            "subject": "What changed or what was bought",
            "amount": 13.29,
            "resultingValue": 21.23,
            "unit": "dollars",
            "periodLabel": "March 2026",
            "tags": ["expense", "budget"]
          },
          "assistantResponse": null,
          "confirmationSummary": "Short confirmation line",
          "clarificationPrompt": null,
          "notes": null,
          "confidence": 0.9
        }

        Latest user message:
        \(text)
        """

        return await runExtractionPrompt(prompt, operationType: "tracker_update_recovery")
    }

    private func extractUndoLastChange(
        targetChange: TrackerChange,
        in thread: TrackerThread,
        conversationHistory: [ConversationMessage]
    ) async -> TrackerLLMExtraction? {
        let recentTurns = conversationHistory
            .suffix(4)
            .map { message in
                let role = message.isUser ? "User" : "Assistant"
                return "\(role): \(message.text)"
            }
            .joined(separator: "\n")

        let recentChanges = thread.memorySnapshot.changeLog
            .sorted(by: mostRecentChangeFirst)
            .prefix(6)
            .map { change in
                let title = change.title?.trackerNonEmpty.map { "\($0): " } ?? ""
                return "- [\(displayDate(change.effectiveAt))] \(change.type.rawValue) • \(title)\(change.content)"
            }
            .joined(separator: "\n")

        let targetTitle = targetChange.title?.trackerNonEmpty ?? targetChange.content
        let prompt = """
        You are drafting an undo for the latest change in a generic tracker chat.

        Return JSON only.

        TRACKER TITLE:
        \(thread.title)

        RULES:
        \(thread.memorySnapshot.normalizedRulesText)

        CURRENT SUMMARY:
        \(thread.memorySnapshot.normalizedSummaryText.trackerNonEmpty ?? "No tracked updates yet.")

        QUICK FACTS:
        \(thread.memorySnapshot.quickFacts.isEmpty ? "None" : thread.memorySnapshot.quickFacts.joined(separator: " | "))

        RECENT CHANGES:
        \(recentChanges.isEmpty ? "None" : recentChanges)

        RECENT TRACKER TURNS:
        \(recentTurns.isEmpty ? "None" : recentTurns)

        TARGET CHANGE TO UNDO:
        \(targetTitle)
        Type: \(targetChange.type.rawValue)
        Effective at: \(displayDate(targetChange.effectiveAt))

        Rules:
        - Undo only the target change above.
        - Preserve all other rules and tracker changes.
        - Return the FULL updated rulesText only if the target change altered the rules and you can confidently restore the previous rules.
        - Always return the FULL updated currentSummary after removing the target change's effect.
        - Update quickFacts if the tracked state changes.
        - Return changeContext with structured fields for actors, relatedEntities, subject, amount, resultingValue, unit, periodLabel, and tags whenever they can be inferred for the undo note.
        - Keep quickFacts UI-friendly: 2-4 short current-state facts, not a paragraph.
        - Prefer the latest values the user would care about now, such as what remains, what is due next, who is up, what changed most recently, or the current running total.
        - Set intent to update_state for normal state reversals, or edit_rules if undoing a rule change requires restoring prior rules.
        - Set changeType to correction.
        - changeTitle should be "Undo last change".
        - changeContent should clearly say what was undone.
        - confirmationSummary should be short and user-facing.
        - If the prior state cannot be inferred reliably, return clarification instead of guessing.

        JSON shape:
        {
          "intent": "update_state",
          "title": null,
          "rulesText": null,
          "currentSummary": "Full updated summary",
          "quickFacts": ["updated fact one"],
          "changeType": "correction",
          "changeTitle": "Undo last change",
          "changeContent": "Undid the previous tracker update.",
          "changeContext": {
            "actors": ["Person"],
            "relatedEntities": [],
            "subject": "What changed",
            "amount": 13.29,
            "resultingValue": 21.23,
            "unit": "dollars",
            "periodLabel": "March 2026",
            "tags": ["undo", "correction"]
          },
          "assistantResponse": null,
          "confirmationSummary": "Undo the last change.",
          "clarificationPrompt": null,
          "notes": null,
          "confidence": 0.9
        }
        """

        return await runExtractionPrompt(prompt, operationType: "tracker_undo")
    }

    private func explainTrackerState(
        userMessage: String,
        thread: TrackerThread,
        state: TrackerDerivedState,
        conversationHistory: [ConversationMessage],
        fallback: String
    ) async -> String {
        let recentTurns = conversationHistory
            .suffix(6)
            .map { message in
                let role = message.isUser ? "User" : "Assistant"
                return "\(role): \(message.text)"
            }
            .joined(separator: "\n")

        let quickFacts = state.quickFacts.isEmpty
            ? "None"
            : state.quickFacts.map { "- \($0)" }.joined(separator: "\n")
        let relevantChanges = relevantChanges(for: userMessage, in: thread.memorySnapshot.changeLog)
        let relevantChangesText = relevantChanges.isEmpty
            ? "None"
            : relevantChanges.map(formattedChangeLine).joined(separator: "\n")
        let recentChanges = state.recentChanges.isEmpty
            ? "None"
            : state.recentChanges.map(formattedChangeLine).joined(separator: "\n")

        let prompt = """
        You are answering inside Seline's tracker chat mode.

        Rules:
        - Use only the tracker context below.
        - This is a generic tracker and may include money, points, counts, or schedules.
        - Be concise and concrete.
        - If the user asks about rules, answer from RULES.
        - If the user asks about status or recall, answer from CURRENT SUMMARY, QUICK FACTS, RELEVANT CHANGES, and RECENT CHANGES.
        - If the user asks who bought, spent, changed, completed, or has left this month/week/day, answer directly from the relevant changes and current summary.
        - When the user asks for a list, list the matching tracked changes plainly instead of restating the generic summary.
        - If totals can be derived from the tracker context, include them.
        - If the tracker context is incomplete, say exactly what is known from the saved changes.
        - Do not mention unrelated app data.

        TRACKER TITLE:
        \(thread.title)

        RULES:
        \(state.ruleSummary)

        CURRENT SUMMARY:
        \(state.currentSummary)

        QUICK FACTS:
        \(quickFacts)

        RELEVANT CHANGES:
        \(relevantChangesText)

        RECENT CHANGES:
        \(recentChanges)

        RECENT TRACKER TURNS:
        \(recentTurns.isEmpty ? "None" : recentTurns)

        USER MESSAGE:
        \(userMessage)
        """

        do {
            let generated = try await gemini.generateText(
                systemPrompt: "Answer tracker questions using only the provided tracker memory.",
                userPrompt: prompt,
                maxTokens: 220,
                temperature: 0.15,
                operationType: "tracker_chat"
            )
            let cleaned = generated.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty ? fallback : cleaned
        } catch {
            return fallback
        }
    }

    private func runExtractionPrompt(
        _ prompt: String,
        operationType: String
    ) async -> TrackerLLMExtraction? {
        do {
            let raw = try await gemini.generateText(
                systemPrompt: "Return valid JSON only. Never add markdown fences.",
                userPrompt: prompt,
                maxTokens: 420,
                temperature: 0.1,
                operationType: operationType
            )
            return decodeExtraction(from: raw)
        } catch {
            return nil
        }
    }

    private func decodeExtraction(from raw: String) -> TrackerLLMExtraction? {
        let cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = cleaned.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(TrackerLLMExtraction.self, from: data)
    }

    // MARK: - Snapshot Helpers

    private func buildProposedSnapshot(
        from extraction: TrackerLLMExtraction,
        on thread: TrackerThread,
        includeChangeInLog: Bool
    ) -> (snapshot: TrackerMemorySnapshot, change: TrackerChange?)? {
        let base = thread.memorySnapshot
        let proposedRules = extraction.rulesText?.trackerNonEmpty ?? base.normalizedRulesText
        let proposedSummary = extraction.currentSummary?.trackerNonEmpty ?? base.normalizedSummaryText
        let proposedTitle = extraction.title?.trackerNonEmpty ?? thread.title
        let proposedFacts = sanitizedFacts(extraction.quickFacts, fallback: base.quickFacts)

        guard !proposedRules.isEmpty || !proposedSummary.isEmpty else {
            return nil
        }

        var changeLog = base.changeLog
        let change = buildChange(from: extraction)
        if includeChangeInLog, let change {
            changeLog.append(change)
            if changeLog.count > 150 {
                changeLog.removeFirst(changeLog.count - 150)
            }
        }

        let lastUpdatedAt = includeChangeInLog
            ? (change?.effectiveAt ?? Date())
            : base.lastUpdatedAt

        let snapshot = TrackerMemorySnapshot(
            title: proposedTitle,
            rulesText: proposedRules,
            currentSummary: proposedSummary.trackerNonEmpty ?? base.normalizedSummaryText.trackerNonEmpty ?? "No tracked updates yet.",
            quickFacts: proposedFacts,
            changeLog: changeLog,
            notes: extraction.notes?.trackerNonEmpty ?? base.notes,
            lastUpdatedAt: lastUpdatedAt
        )

        let nothingChanged = snapshot == base
        return nothingChanged ? nil : (snapshot, change)
    }

    private func buildChange(from extraction: TrackerLLMExtraction) -> TrackerChange? {
        guard let content = extraction.changeContent?.trackerNonEmpty else { return nil }
        let timestamp = Date()
        return TrackerChange(
            type: resolvedChangeType(from: extraction.changeType, intent: resolvedIntent(from: extraction.intent)),
            title: extraction.changeTitle?.trackerNonEmpty,
            content: content,
            effectiveAt: timestamp,
            createdAt: timestamp,
            context: mergedChangeContext(
                extraction.changeContext,
                fallback: heuristicChangeContext(
                    from: content,
                    title: extraction.changeTitle,
                    effectiveAt: timestamp
                )
            )
        )
    }

    private func normalizedMemorySnapshot(_ snapshot: TrackerMemorySnapshot) -> TrackerMemorySnapshot {
        let normalizedChanges = snapshot.changeLog.map(normalizedChange)
        guard normalizedChanges != snapshot.changeLog else {
            return snapshot
        }

        return TrackerMemorySnapshot(
            version: snapshot.version,
            title: snapshot.title,
            rulesText: snapshot.rulesText,
            currentSummary: snapshot.currentSummary,
            quickFacts: snapshot.quickFacts,
            changeLog: normalizedChanges,
            notes: snapshot.notes,
            lastUpdatedAt: snapshot.lastUpdatedAt
        )
    }

    private func normalizedChange(_ change: TrackerChange) -> TrackerChange {
        let normalizedContext = contextForChange(change)
        guard normalizedContext != change.context else {
            return change
        }

        var updatedChange = change
        updatedChange.context = normalizedContext
        return updatedChange
    }

    private func sanitizedFacts(
        _ facts: [String]?,
        fallback: [String] = []
    ) -> [String] {
        let cleaned = facts?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return cleaned?.isEmpty == false ? cleaned! : fallback
    }

    private func mergedChangeContext(
        _ extracted: TrackerChangeContext?,
        fallback: TrackerChangeContext?
    ) -> TrackerChangeContext? {
        let sanitizedExtracted = sanitizeChangeContext(extracted)
        let sanitizedFallback = sanitizeChangeContext(fallback)

        guard sanitizedExtracted != nil || sanitizedFallback != nil else {
            return nil
        }

        let merged = TrackerChangeContext(
            actors: uniqueTrackerTerms((sanitizedExtracted?.actors ?? []) + (sanitizedFallback?.actors ?? [])),
            relatedEntities: uniqueTrackerTerms((sanitizedExtracted?.relatedEntities ?? []) + (sanitizedFallback?.relatedEntities ?? [])),
            subject: sanitizedExtracted?.subject?.trackerNonEmpty ?? sanitizedFallback?.subject?.trackerNonEmpty,
            amount: sanitizedExtracted?.amount ?? sanitizedFallback?.amount,
            resultingValue: sanitizedExtracted?.resultingValue ?? sanitizedFallback?.resultingValue,
            unit: sanitizedExtracted?.unit?.trackerNonEmpty ?? sanitizedFallback?.unit?.trackerNonEmpty,
            periodLabel: sanitizedExtracted?.periodLabel?.trackerNonEmpty ?? sanitizedFallback?.periodLabel?.trackerNonEmpty,
            tags: uniqueTrackerTerms((sanitizedExtracted?.tags ?? []) + (sanitizedFallback?.tags ?? []))
        )

        return isMeaningfulChangeContext(merged) ? merged : nil
    }

    private func sanitizeChangeContext(_ context: TrackerChangeContext?) -> TrackerChangeContext? {
        guard let context else { return nil }
        let sanitized = TrackerChangeContext(
            actors: uniqueTrackerTerms(context.actors),
            relatedEntities: uniqueTrackerTerms(context.relatedEntities),
            subject: context.subject?.trackerNonEmpty,
            amount: context.amount,
            resultingValue: context.resultingValue,
            unit: context.unit?.trackerNonEmpty,
            periodLabel: context.periodLabel?.trackerNonEmpty,
            tags: uniqueTrackerTerms(context.tags)
        )
        return isMeaningfulChangeContext(sanitized) ? sanitized : nil
    }

    private func isMeaningfulChangeContext(_ context: TrackerChangeContext) -> Bool {
        !context.actors.isEmpty
            || !context.relatedEntities.isEmpty
            || context.subject?.trackerNonEmpty != nil
            || context.amount != nil
            || context.resultingValue != nil
            || context.unit?.trackerNonEmpty != nil
            || context.periodLabel?.trackerNonEmpty != nil
            || !context.tags.isEmpty
    }

    private func heuristicChangeContext(
        from content: String,
        title: String?,
        effectiveAt: Date
    ) -> TrackerChangeContext? {
        let combined = [title?.trackerNonEmpty, content.trackerNonEmpty]
            .compactMap { $0 }
            .joined(separator: " ")
        let lowercase = combined.lowercased()

        let actors = heuristicActors(from: content)
        let relatedEntities = heuristicRelatedEntities(from: content)
        let subject = heuristicSubject(from: content)
        let amount = firstCurrencyValue(in: content)
        let resultingValue = resultingValue(in: content)
        let unit = heuristicUnit(from: lowercase)
        let periodLabel = heuristicPeriodLabel(from: combined, effectiveAt: effectiveAt)
        let tags = heuristicTags(from: lowercase)

        let context = TrackerChangeContext(
            actors: actors,
            relatedEntities: relatedEntities,
            subject: subject,
            amount: amount,
            resultingValue: resultingValue,
            unit: unit,
            periodLabel: periodLabel,
            tags: tags
        )

        return isMeaningfulChangeContext(context) ? context : nil
    }

    private func heuristicActors(from content: String) -> [String] {
        let pattern = #"^([A-Z][A-Za-z']*(?:\s+[A-Z][A-Za-z']*)*)\s+(spent|paid|bought|purchased|used|completed|finished|earned|transferred|logged|missed|has|had|owes|owe)\b"#
        guard let match = content.firstRegexMatch(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        return heuristicNames(from: match)
    }

    private func heuristicRelatedEntities(from content: String) -> [String] {
        let relatedPatterns = [
            #"\bfrom\s+([A-Z][A-Za-z']*(?:\s+[A-Z][A-Za-z']*)*)"#,
            #"\bto\s+([A-Z][A-Za-z']*(?:\s+[A-Z][A-Za-z']*)*)"#,
            #"\bat\s+([A-Z][A-Za-z']*(?:\s+[A-Z][A-Za-z']*)*)"#,
            #"\bwith\s+([A-Z][A-Za-z']*(?:\s+[A-Z][A-Za-z']*)*)"#,
        ]

        return uniqueTrackerTerms(
            relatedPatterns.compactMap { content.firstRegexMatch(pattern: $0, options: [.caseInsensitive]) }
                .flatMap(heuristicNames)
        )
    }

    private func heuristicNames(from text: String) -> [String] {
        let excluded = trackerNameStopwords
        let matches = text.allRegexMatches(pattern: #"\b[A-Z][A-Za-z']+\b"#)
        return uniqueTrackerTerms(
            matches.filter { candidate in
                !excluded.contains(candidate.lowercased())
            }
        )
    }

    private func heuristicSubject(from content: String) -> String? {
        let patterns = [
            #"\bon\s+(.+?)(?:,|\.\s*| leaving| left| remaining|$)"#,
            #"\bfor\s+(.+?)(?:,|\.\s*| leaving| left| remaining|$)"#,
            #"\bbought\s+(.+?)(?:\s+for\s+\$|\s*,|\.\s*|$)"#,
            #"\bpurchased\s+(.+?)(?:\s+for\s+\$|\s*,|\.\s*|$)"#
        ]

        for pattern in patterns {
            if let match = content.firstRegexMatch(pattern: pattern, options: [.caseInsensitive])?.trackerNonEmpty {
                return cleanSubject(match)
            }
        }

        return nil
    }

    private func cleanSubject(_ value: String) -> String? {
        let cleaned = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:"))
        return cleaned.trackerNonEmpty
    }

    private func firstCurrencyValue(in text: String) -> Double? {
        let patterns = [
            #"\$([0-9]+(?:\.[0-9]{1,2})?)"#,
            #"\b([0-9]+(?:\.[0-9]{1,2})?)\s*(?:dollars?|usd|cad)\b"#
        ]

        for pattern in patterns {
            if let match = text.firstRegexMatch(pattern: pattern, options: [.caseInsensitive]) {
                let normalized = match.replacingOccurrences(of: "$", with: "")
                if let value = Double(normalized) {
                    return value
                }
            }
        }

        return nil
    }

    private func resultingValue(in text: String) -> Double? {
        let patterns = [
            #"(?:leaving\s+\w+\s+with|left\s+\w+\s+with|remaining|balance(?:\s+after)?|has)\s+\$?([0-9]+(?:\.[0-9]{1,2})?)"#,
            #"\$([0-9]+(?:\.[0-9]{1,2})?)\s+(?:left|remaining)"#
        ]

        for pattern in patterns {
            if let match = text.firstRegexMatch(pattern: pattern, options: [.caseInsensitive]) {
                let normalized = match.replacingOccurrences(of: "$", with: "")
                if let value = Double(normalized) {
                    return value
                }
            }
        }

        return nil
    }

    private func heuristicUnit(from lowercase: String) -> String? {
        if lowercase.contains("$") || lowercase.contains("dollar") || lowercase.contains("cad") || lowercase.contains("usd") {
            return "dollars"
        }
        if lowercase.contains("point") {
            return "points"
        }
        if lowercase.contains("visit") {
            return "visits"
        }
        if lowercase.contains("workout") {
            return "workouts"
        }
        return nil
    }

    private func heuristicPeriodLabel(from text: String, effectiveAt: Date) -> String? {
        if let match = text.firstRegexMatch(
            pattern: #"\b(January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{4}\b"#,
            options: [.caseInsensitive]
        ) {
            return match
        }

        let lowercase = text.lowercased()
        if lowercase.contains("this month") {
            return monthYearFormatter.string(from: effectiveAt)
        }
        if lowercase.contains("last month"),
           let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: effectiveAt) {
            return monthYearFormatter.string(from: lastMonth)
        }
        if lowercase.contains("today") {
            return dayFormatter.string(from: effectiveAt)
        }
        return nil
    }

    private func heuristicTags(from lowercase: String) -> [String] {
        var tags: [String] = []

        if containsAny(["spent", "paid", "bought", "purchase", "purchased"], in: lowercase) {
            tags.append("expense")
        }
        if containsAny(["left", "remaining", "balance"], in: lowercase) {
            tags.append("balance")
        }
        if containsAny(["transfer", "transferred", "sent", "received"], in: lowercase) {
            tags.append("transfer")
        }
        if containsAny(["undo", "reverted", "reversed"], in: lowercase) {
            tags.append("undo")
        }
        if containsAny(["complete", "completed", "finished", "logged"], in: lowercase) {
            tags.append("progress")
        }

        return uniqueTrackerTerms(tags)
    }

    private func formattedChangeLine(_ change: TrackerChange) -> String {
        let title = change.title?.trackerNonEmpty.map { "\($0): " } ?? ""
        let structured = formattedContextDetails(contextForChange(change))
        if let structured, !structured.isEmpty {
            return "- [\(displayDate(change.effectiveAt))] \(title)\(change.content) { \(structured) }"
        }
        return "- [\(displayDate(change.effectiveAt))] \(title)\(change.content)"
    }

    private func formattedContextDetails(_ context: TrackerChangeContext?) -> String? {
        guard let context = sanitizeChangeContext(context) else { return nil }

        var parts: [String] = []
        if !context.actors.isEmpty {
            parts.append("actors: \(context.actors.joined(separator: ", "))")
        }
        if !context.relatedEntities.isEmpty {
            parts.append("entities: \(context.relatedEntities.joined(separator: ", "))")
        }
        if let subject = context.subject?.trackerNonEmpty {
            parts.append("subject: \(subject)")
        }
        if let amount = context.amount {
            parts.append("amount: \(formatStructuredNumber(amount))")
        }
        if let resultingValue = context.resultingValue {
            parts.append("valueAfter: \(formatStructuredNumber(resultingValue))")
        }
        if let unit = context.unit?.trackerNonEmpty {
            parts.append("unit: \(unit)")
        }
        if let periodLabel = context.periodLabel?.trackerNonEmpty {
            parts.append("period: \(periodLabel)")
        }
        if !context.tags.isEmpty {
            parts.append("tags: \(context.tags.joined(separator: ", "))")
        }

        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    private func uniqueTrackerTerms(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { return nil }
            seen.insert(key)
            return trimmed
        }
    }

    private func formatStructuredNumber(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    private func contextForChange(_ change: TrackerChange) -> TrackerChangeContext? {
        sanitizeChangeContext(change.context)
            ?? heuristicChangeContext(
                from: change.content,
                title: change.title,
                effectiveAt: change.effectiveAt
            )
    }

    private func fallbackQueryExtraction(
        for text: String,
        thread: TrackerThread,
        primary: TrackerLLMExtraction? = nil
    ) -> TrackerLLMExtraction? {
        if let primary {
            let primaryIntent = resolvedIntent(from: primary.intent)
            if primaryIntent != .clarification {
                return primary
            }
        }

        guard looksLikeTrackerQuestion(text) else {
            return primary
        }

        let intent: TrackerChatIntent = looksLikeRuleQuestion(text) ? .askRules : .askState
        return TrackerLLMExtraction(
            intent: intent.rawValue,
            title: nil,
            rulesText: nil,
            currentSummary: nil,
            quickFacts: nil,
            changeType: nil,
            changeTitle: nil,
            changeContent: nil,
            changeContext: nil,
            assistantResponse: primary?.assistantResponse,
            confirmationSummary: nil,
            clarificationPrompt: nil,
            notes: thread.memorySnapshot.notes?.trackerNonEmpty,
            confidence: primary?.confidence ?? 0.35
        )
    }

    private func relevantChanges(
        for userMessage: String,
        in changeLog: [TrackerChange]
    ) -> [TrackerChange] {
        let sorted = changeLog.sorted(by: mostRecentChangeFirst)
        guard !sorted.isEmpty else { return [] }

        let scopedChanges = changesScopedToLikelyTimeRange(from: userMessage, in: sorted)
        let keywordMatched = filterChanges(scopedChanges, matching: queryKeywords(from: userMessage))

        if !keywordMatched.isEmpty {
            return Array(keywordMatched.prefix(18))
        }

        if !scopedChanges.isEmpty {
            return Array(scopedChanges.prefix(18))
        }

        return Array(sorted.prefix(18))
    }

    private func changesScopedToLikelyTimeRange(
        from userMessage: String,
        in changes: [TrackerChange]
    ) -> [TrackerChange] {
        guard let range = inferredDateRange(from: userMessage) else {
            return changes
        }

        let filtered = changes.filter { change in
            range.contains(change.effectiveAt)
        }

        return filtered.isEmpty ? changes : filtered
    }

    private func inferredDateRange(from userMessage: String) -> DateInterval? {
        let lowercase = userMessage.lowercased()
        let calendar = Calendar.current
        let now = Date()

        if lowercase.contains("today") {
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
            return DateInterval(start: start, end: end)
        }

        if lowercase.contains("yesterday") {
            let end = calendar.startOfDay(for: now)
            let start = calendar.date(byAdding: .day, value: -1, to: end) ?? end
            return DateInterval(start: start, end: end)
        }

        if lowercase.contains("this week") {
            let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? now
            return DateInterval(start: start, end: end)
        }

        if lowercase.contains("last week"),
           let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now) {
            let end = currentWeek.start
            let start = calendar.date(byAdding: .day, value: -7, to: end) ?? end
            return DateInterval(start: start, end: end)
        }

        if lowercase.contains("this month") {
            let start = calendar.dateInterval(of: .month, for: now)?.start ?? calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? now
            return DateInterval(start: start, end: end)
        }

        if lowercase.contains("last month"),
           let currentMonth = calendar.dateInterval(of: .month, for: now) {
            let end = currentMonth.start
            let start = calendar.date(byAdding: .month, value: -1, to: end) ?? end
            return DateInterval(start: start, end: end)
        }

        let monthNames = DateFormatter().monthSymbols.map { $0.lowercased() }
        if let monthIndex = monthNames.firstIndex(where: { lowercase.contains($0) }) {
            var components = calendar.dateComponents([.year], from: now)
            components.month = monthIndex + 1
            components.day = 1
            if let start = calendar.date(from: components) {
                let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
                return DateInterval(start: start, end: end)
            }
        }

        return nil
    }

    private func queryKeywords(from userMessage: String) -> [String] {
        let lowercase = userMessage.lowercased()
        let baseTokens = lowercase
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { token in
                token.count > 2 && !trackerQueryStopwords.contains(token)
            }

        var keywords = Set(baseTokens)

        if containsAny(["buy", "bought", "purchase", "purchased"], in: lowercase) {
            ["buy", "bought", "purchase", "purchased", "spent", "paid"].forEach { keywords.insert($0) }
        }

        if containsAny(["spend", "spent", "pay", "paid"], in: lowercase) {
            ["spend", "spent", "pay", "paid", "bought", "purchase"].forEach { keywords.insert($0) }
        }

        if lowercase.contains("left") || lowercase.contains("remaining") {
            ["left", "remaining", "remain"].forEach { keywords.insert($0) }
        }

        return Array(keywords)
    }

    private func filterChanges(
        _ changes: [TrackerChange],
        matching keywords: [String]
    ) -> [TrackerChange] {
        guard !keywords.isEmpty else { return changes }

        return changes.filter { change in
            let haystack = searchableChangeText(change)
            return keywords.contains(where: { haystack.contains($0) })
        }
    }

    private func searchableChangeText(_ change: TrackerChange) -> String {
        var parts = [change.title ?? "", change.content]
        if let context = contextForChange(change) {
            parts.append(contentsOf: context.actors)
            parts.append(contentsOf: context.relatedEntities)
            parts.append(context.subject ?? "")
            parts.append(context.unit ?? "")
            parts.append(context.periodLabel ?? "")
            parts.append(contentsOf: context.tags)
            if let amount = context.amount {
                parts.append(String(amount))
            }
            if let resultingValue = context.resultingValue {
                parts.append(String(resultingValue))
            }
        }
        return parts.joined(separator: " ").lowercased()
    }

    private var monthYearFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }

    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }

    private var trackerNameStopwords: Set<String> {
        Set(DateFormatter().monthSymbols.map { $0.lowercased() })
            .union(DateFormatter().shortMonthSymbols.map { $0.lowercased() })
            .union([
                "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday",
                "mon", "tue", "tues", "wed", "thu", "thur", "thurs", "fri", "sat", "sun",
                "undo", "last", "change", "tracker", "march"
            ])
    }

    private func looksLikeTrackerQuestion(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let lowercase = trimmed.lowercased()
        let questionPrefixes = [
            "what ",
            "what's ",
            "whats ",
            "how ",
            "how's ",
            "show ",
            "list ",
            "tell ",
            "which ",
            "who ",
            "when ",
            "where ",
            "why ",
            "can ",
            "could ",
            "did ",
            "does ",
            "is ",
            "are "
        ]

        if trimmed.hasSuffix("?") || questionPrefixes.contains(where: { lowercase.hasPrefix($0) }) {
            return true
        }

        return containsAny(
            [
                "summary",
                "recap",
                "status",
                "current state",
                "how much left",
                "what changed",
                "recent changes"
            ],
            in: lowercase
        )
    }

    private func looksLikeRuleQuestion(_ text: String) -> Bool {
        let lowercase = text.lowercased()
        return containsAny(
            [
                "rule",
                "rules",
                "budget rule",
                "how does this work",
                "what are we tracking",
                "what is the rule",
                "what are the rules"
            ],
            in: lowercase
        )
    }

    private func containsAny(_ terms: [String], in text: String) -> Bool {
        terms.contains(where: { text.contains($0) })
    }

    private var trackerQueryStopwords: Set<String> {
        [
            "the", "and", "for", "with", "from", "that", "this", "what", "whats",
            "what's", "show", "tell", "about", "have", "has", "into", "your", "their",
            "they", "them", "just", "want", "need", "please", "would", "could", "should",
            "there", "here", "than", "then", "been", "were", "when", "where", "which",
            "month", "week", "today", "yesterday", "current", "state", "summary", "recap"
        ]
    }

    private func looksLikeStateUpdateMessage(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let lowercase = trimmed.lowercased()
        let queryPrefixes = [
            "what ",
            "what's ",
            "whats ",
            "how ",
            "can ",
            "could ",
            "should ",
            "show ",
            "list ",
            "tell ",
            "do ",
            "does ",
            "is ",
            "are ",
            "when ",
            "why "
        ]

        if trimmed.hasSuffix("?") || queryPrefixes.contains(where: { lowercase.hasPrefix($0) }) {
            return false
        }

        let ruleEditKeywords = [
            "rule",
            "rules",
            "from now on",
            "instead",
            "new limit",
            "change the limit",
            "change the budget",
            "set the budget",
            "set the cap",
            "starting next",
            "going forward"
        ]

        if ruleEditKeywords.contains(where: { lowercase.contains($0) }) {
            return false
        }

        let updateKeywords = [
            "bought",
            "spent",
            "paid",
            "purchased",
            "used",
            "completed",
            "finished",
            "earned",
            "owe",
            "owes",
            "transferred",
            "logged",
            "log ",
            "add ",
            "added",
            "update ",
            "updated",
            "changed",
            "missed",
            "did "
        ]

        if updateKeywords.contains(where: { lowercase.contains($0) }) {
            return true
        }

        return lowercase.range(of: #"\d"#, options: .regularExpression) != nil
    }

    private func resolvedIntent(from rawValue: String?) -> TrackerChatIntent {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case TrackerChatIntent.createTracker.rawValue:
            return .createTracker
        case TrackerChatIntent.editRules.rawValue:
            return .editRules
        case TrackerChatIntent.updateState.rawValue, "draft_entry":
            return .updateState
        case TrackerChatIntent.askState.rawValue:
            return .askState
        case TrackerChatIntent.askRules.rawValue:
            return .askRules
        case TrackerChatIntent.whatIf.rawValue:
            return .whatIf
        default:
            return .clarification
        }
    }

    private func resolvedChangeType(from rawValue: String?, intent: TrackerChatIntent) -> TrackerChangeType {
        switch rawValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case TrackerChangeType.ruleChange.rawValue:
            return .ruleChange
        case TrackerChangeType.correction.rawValue:
            return .correction
        case TrackerChangeType.note.rawValue:
            return .note
        case TrackerChangeType.stateUpdate.rawValue:
            return .stateUpdate
        default:
            return intent == .editRules ? .ruleChange : .stateUpdate
        }
    }

    private func defaultConfirmationSummary(
        for intent: TrackerChatIntent,
        type: TrackerChangeType
    ) -> String {
        switch intent {
        case .editRules:
            return "Update the tracker rules."
        case .updateState:
            switch type {
            case .correction:
                return "Apply the correction to the tracker."
            case .note:
                return "Add the note to the tracker."
            case .ruleChange:
                return "Update the tracker rules."
            case .stateUpdate:
                return "Update the tracked summary."
            }
        case .whatIf:
            return "Preview the hypothetical tracker change."
        case .createTracker, .askState, .askRules, .clarification:
            return "Update the tracker."
        }
    }

    private func suggestedTitle(from text: String) -> String {
        let compact = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else { return "Tracker" }
        let words = compact.split(separator: " ").prefix(5).joined(separator: " ")
        return words.isEmpty ? "Tracker" : words.capitalized
    }

    private func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func mostRecentChangeFirst(_ lhs: TrackerChange, _ rhs: TrackerChange) -> Bool {
        if lhs.effectiveAt == rhs.effectiveAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.effectiveAt > rhs.effectiveAt
    }
}

struct TrackerChatOutcome {
    var intent: TrackerChatIntent
    var responseText: String
    var draft: TrackerOperationDraft? = nil
    var derivedState: TrackerDerivedState? = nil
    var commitsProjectedStateToThread: Bool = false
    var shouldPersistAssistantMessage: Bool
}

struct TrackerApplyResult {
    var thread: TrackerThread?
    var didApply: Bool
    var message: String
}

private struct TrackerLLMExtraction: Codable {
    var intent: String?
    var title: String?
    var rulesText: String?
    var currentSummary: String?
    var quickFacts: [String]?
    var changeType: String?
    var changeTitle: String?
    var changeContent: String?
    var changeContext: TrackerChangeContext?
    var assistantResponse: String?
    var confirmationSummary: String?
    var clarificationPrompt: String?
    var notes: String?
    var confidence: Double?
}

private extension String {
    func firstRegexMatch(
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }

        let searchRange = NSRange(startIndex..., in: self)
        guard let match = regex.firstMatch(in: self, options: [], range: searchRange) else {
            return nil
        }

        let targetRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
        guard let swiftRange = Range(targetRange, in: self) else {
            return nil
        }
        return String(self[swiftRange])
    }

    func allRegexMatches(
        pattern: String,
        options: NSRegularExpression.Options = []
    ) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }

        let searchRange = NSRange(startIndex..., in: self)
        return regex.matches(in: self, options: [], range: searchRange).compactMap { match in
            let targetRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
            guard let swiftRange = Range(targetRange, in: self) else {
                return nil
            }
            return String(self[swiftRange])
        }
    }
}
