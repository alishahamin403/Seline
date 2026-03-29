import SwiftUI
import CoreLocation

struct ChatView: View {
    var isVisible: Bool = true
    var onOpenEmail: ((Email) -> Void)? = nil
    var onOpenTask: ((TaskItem) -> Void)? = nil
    var onOpenNote: ((Note) -> Void)? = nil
    var onOpenPlace: ((SavedPlace) -> Void)? = nil
    var onOpenPerson: ((Person) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var locationService: LocationService
    @FocusState private var isComposerFocused: Bool
    @StateObject private var store = SelineChatStore.shared
    @State private var draft = ""
    @State private var isSidebarPresented = false
    @State private var sidebarSearchText = ""

    private let quickPrompts: [SelineChatPromptSuggestion] = [
        .init(title: "How's my day today"),
        .init(title: "Any new emails?"),
        .init(title: "What's nearby?"),
        .init(title: "Spending this week")
    ]
    private let scrollAnchorID = "seline-chat-bottom-anchor"

    private var selectedThread: SelineChatThread? {
        store.selectedThread
    }

    private var selectedThreadTurnCount: Int {
        selectedThread?.turns.count ?? 0
    }

    private var shouldShowThinkingRow: Bool {
        guard let state = store.thinkingState, let selectedThreadID = store.selectedThreadID else { return false }
        return state.threadID == selectedThreadID
    }

    private var allSidebarSections: [SelineChatSidebarSection] {
        let grouped = Dictionary(grouping: store.threads.sorted { $0.updatedAt > $1.updatedAt }) { thread in
            sidebarSectionTitle(for: thread.updatedAt)
        }

        return ["Today", "Yesterday", "This Week", "Older"].compactMap { title in
            guard let items = grouped[title], !items.isEmpty else { return nil }
            return SelineChatSidebarSection(title: title, threads: items)
        }
    }

    private var filteredSidebarSections: [SelineChatSidebarSection] {
        let query = sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return allSidebarSections }

        return allSidebarSections.compactMap { section in
            let matches = section.threads.filter { thread in
                thread.title.lowercased().contains(query)
                    || thread.previewText.lowercased().contains(query)
            }
            guard !matches.isEmpty else { return nil }
            return SelineChatSidebarSection(title: section.title, threads: matches)
        }
    }

    private var isSidebarSearching: Bool {
        !sidebarSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var sidebarBackgroundColor: Color {
        colorScheme == .dark ? Color.black : .white
    }

    private var searchFieldFillColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)
    }

    private var sectionLabelColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.42) : Color.black.opacity(0.40)
    }

    private func sidebarRowFill(isSelected: Bool) -> Color {
        guard isSelected else { return .clear }
        return colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.055)
    }

    var body: some View {
        GeometryReader { geometry in
            InteractiveSidebarOverlay(
                isPresented: $isSidebarPresented,
                canOpen: isVisible,
                sidebarWidth: min(336, geometry.size.width * 0.86),
                colorScheme: colorScheme
            ) {
                ZStack {
                    AppAmbientBackgroundLayer(
                        colorScheme: colorScheme,
                        variant: .topLeading
                    )

                    chatShell(topInset: geometry.safeAreaInsets.top)
                }
            } sidebarContent: {
                sidebarContent
            }
        }
        .onChange(of: isVisible) { newValue in
            if !newValue {
                isSidebarPresented = false
            }
        }
    }

    private func chatShell(topInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            topBar(topInset: topInset)
            contentArea
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .bottom) {
            composerInset
        }
    }

    private func topBar(topInset: CGFloat) -> some View {
        HStack(spacing: 12) {
            Button {
                HapticManager.shared.selection()
                withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.88)) {
                    isSidebarPresented = true
                }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary(colorScheme))
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color.appInnerSurface(colorScheme) : Color.white)
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.appBorder(colorScheme), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Text("Chat")
                .font(FontManager.geist(size: 16, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))

            Spacer(minLength: 0)

            Button {
                beginNewChat()
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary(colorScheme))
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(colorScheme == .dark ? Color.appInnerSurface(colorScheme) : Color.white)
                    )
                    .overlay(
                        Circle()
                            .stroke(Color.appBorder(colorScheme), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, topInset > 0 ? 8 : 12)
        .padding(.bottom, 8)
        .background(Color.appBackground(colorScheme))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.appBorder(colorScheme))
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var contentArea: some View {
        if let selectedThread {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        messageStack(for: selectedThread)

                        if shouldShowThinkingRow, let state = store.thinkingState {
                            SelineChatThinkingRow(
                                title: state.title,
                                sourceChips: state.sourceChips,
                                colorScheme: colorScheme
                            )
                        }

                        Color.clear
                            .frame(height: 8)
                            .id(scrollAnchorID)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .selinePrimaryPageScroll()
                .onAppear {
                    scrollToBottom(using: proxy, animated: false)
                }
                .onChange(of: store.selectedThreadID) { _ in
                    scrollToBottom(using: proxy, animated: false)
                }
                .onChange(of: selectedThreadTurnCount) { _ in
                    scrollToBottom(using: proxy)
                }
                .onChange(of: shouldShowThinkingRow) { _ in
                    scrollToBottom(using: proxy)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            VStack {
                Spacer(minLength: 0)
                emptyState
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    @ViewBuilder
    private func messageStack(for thread: SelineChatThread) -> some View {
        LazyVStack(alignment: .leading, spacing: 18) {
            ForEach(thread.turns) { turn in
                if turn.role == .assistant {
                    if turn.assistantPayload != nil || !turn.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        SelineChatAssistantTurnView(
                            turn: turn,
                            colorScheme: colorScheme,
                            currentLocation: locationService.currentLocation,
                            onOpenEvidence: handleEvidenceTap,
                            onOpenPlace: handlePlaceTap
                        )
                    }
                } else {
                    SelineChatUserTurnView(turn: turn, colorScheme: colorScheme)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            ForEach(quickPrompts) { suggestion in
                Button {
                    submitPrompt(suggestion.title)
                } label: {
                    SelineChatQuickActionButton(
                        suggestion: suggestion,
                        colorScheme: colorScheme
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 332)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var composerInset: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.appBorder(colorScheme))
                .frame(height: 0.5)

            HStack(alignment: .center, spacing: 10) {
                Button {
                    HapticManager.shared.voiceInput()
                } label: {
                    Image(systemName: "waveform")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.appTextSecondary(colorScheme))
                        .frame(width: 28, height: 28, alignment: .center)
                }
                .buttonStyle(.plain)
                .frame(width: 28, height: 28, alignment: .center)

                VStack(spacing: 0) {
                    TextField("Ask anything grounded in your day…", text: $draft, axis: .vertical)
                        .font(FontManager.geist(size: 15, weight: .regular))
                        .foregroundColor(Color.appTextPrimary(colorScheme))
                        .lineLimit(1...4)
                        .focused($isComposerFocused)
                        .submitLabel(.send)
                        .onSubmit {
                            submitDraft()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .center)

                Button {
                    submitDraft()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(canSendDraft ? Color.appTextPrimary(.light) : Color.appTextSecondary(colorScheme))
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(canSendDraft ? Color.homeGlassAccent : Color.appChip(colorScheme))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSendDraft)
            }
            .frame(minHeight: 44, alignment: .center)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(colorScheme == .dark ? Color.appSurface(colorScheme) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.appBorder(colorScheme), lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)
        }
        .background(Color.appBackground(colorScheme))
    }

    private var sidebarContent: some View {
        ZStack {
            sidebarBackgroundColor
                .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.35))

                        TextField("Search", text: $sidebarSearchText)
                            .textFieldStyle(.plain)
                            .font(FontManager.geist(size: 15, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(searchFieldFillColor)
                    )

                    Button(action: {
                        beginNewChat()
                    }) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.55))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New chat")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(sidebarBackgroundColor)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(filteredSidebarSections) { section in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(section.title.uppercased())
                                    .font(FontManager.geist(size: 11, weight: .medium))
                                    .foregroundColor(sectionLabelColor)
                                    .textCase(.uppercase)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 6)

                                ForEach(section.threads) { thread in
                                    Button {
                                        selectThread(thread.id)
                                    } label: {
                                        SelineChatSidebarRow(
                                            thread: thread,
                                            timestamp: formattedSidebarTimestamp(thread.updatedAt),
                                            isSelected: thread.id == store.selectedThreadID,
                                            fillColor: sidebarRowFill(isSelected: thread.id == store.selectedThreadID),
                                            colorScheme: colorScheme
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if isSidebarSearching && filteredSidebarSections.isEmpty {
                            VStack(spacing: 8) {
                                Text("No chats found")
                                    .font(FontManager.geist(size: 15, weight: .medium))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.6))
                                Text("Try another search term")
                                    .font(FontManager.geist(size: 13, weight: .regular))
                                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.45) : .black.opacity(0.45))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 12)
                        }

                        Spacer()
                            .frame(height: 100)
                    }
                    .padding(.vertical, 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(sidebarBackgroundColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(sidebarBackgroundColor)
    }

    private var canSendDraft: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitDraft() {
        let trimmedDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDraft.isEmpty else { return }
        draft = ""
        isComposerFocused = false
        submitPrompt(trimmedDraft)
    }

    private func submitPrompt(_ prompt: String) {
        HapticManager.shared.aiActionStart()
        store.send(prompt)
    }

    private func beginNewChat() {
        HapticManager.shared.selection()
        draft = ""
        sidebarSearchText = ""
        isComposerFocused = false
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.88)) {
            isSidebarPresented = false
        }
        store.beginNewThread()
    }

    private func selectThread(_ threadID: UUID) {
        HapticManager.shared.selection()
        sidebarSearchText = ""
        store.selectThread(threadID)
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.88)) {
            isSidebarPresented = false
        }
    }

    private func scrollToBottom(using proxy: ScrollViewProxy, animated: Bool = true) {
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.24)) {
                    proxy.scrollTo(scrollAnchorID, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(scrollAnchorID, anchor: .bottom)
            }
        }
    }

    private func sidebarSectionTitle(for date: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()), date >= weekAgo {
            return "This Week"
        }
        return "Older"
    }

    private func formattedSidebarTimestamp(_ date: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return FormatterCache.shortTime.string(from: date)
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()), date >= weekAgo {
            return FormatterCache.weekdayFull.string(from: date)
        }
        return FormatterCache.shortDate.string(from: date)
    }

    private func handleEvidenceTap(_ item: SelineChatEvidenceItem) {
        switch item.kind {
        case .email:
            guard let emailID = item.emailID,
                  let email = (EmailService.shared.inboxEmails + EmailService.shared.sentEmails).first(where: { $0.id == emailID }) else {
                return
            }
            onOpenEmail?(email)
        case .event:
            guard let taskID = item.taskID,
                  let task = TaskManager.shared.getAllFlattenedTasks().first(where: { $0.id == taskID }) else {
                return
            }
            onOpenTask?(task)
        case .note, .receipt:
            guard let noteID = item.noteID,
                  let note = NotesManager.shared.notes.first(where: { $0.id == noteID }) else {
                return
            }
            onOpenNote?(note)
        case .visit:
            guard let placeID = item.placeID,
                  let place = LocationsManager.shared.savedPlaces.first(where: { $0.id == placeID }) else {
                return
            }
            onOpenPlace?(place)
        case .person:
            guard let personID = item.personID,
                  let person = PeopleManager.shared.people.first(where: { $0.id == personID }) else {
                return
            }
            onOpenPerson?(person)
        case .daySummary:
            break
        }
    }

    private func handlePlaceTap(_ result: SelineChatPlaceResult) {
        onOpenPlace?(result.resolvedSavedPlace())
    }
}

private struct SelineChatPromptSuggestion: Identifiable, Hashable {
    let id = UUID()
    let title: String

    var systemImage: String {
        switch title {
        case "How's my day today":
            return "sun.max"
        case "Any new emails?":
            return "tray"
        case "What's nearby?":
            return "location"
        case "Spending this week":
            return "creditcard"
        default:
            return "sparkles"
        }
    }
}

private struct SelineChatSidebarSection: Identifiable {
    let title: String
    let threads: [SelineChatThread]

    var id: String { title }
}

private struct SelineChatAssistantTurnView: View {
    let turn: SelineChatTurn
    let colorScheme: ColorScheme
    let currentLocation: CLLocation?
    let onOpenEvidence: (SelineChatEvidenceItem) -> Void
    let onOpenPlace: (SelineChatPlaceResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let chips = turn.assistantPayload?.sourceChips, !chips.isEmpty {
                HStack(spacing: 6) {
                    ForEach(chips, id: \.self) { chip in
                        Text(chip)
                            .font(FontManager.geist(size: 10, weight: .semibold))
                            .foregroundColor(Color.appTextSecondary(colorScheme))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.appChip(colorScheme))
                            )
                    }
                }
            }

            if let payload = turn.assistantPayload {
                ForEach(Array(payload.responseBlocks.enumerated()), id: \.offset) { entry in
                    SelineChatResponseBlockView(
                        block: entry.element,
                        colorScheme: colorScheme,
                        currentLocation: currentLocation,
                        onOpenEvidence: onOpenEvidence,
                        onOpenPlace: onOpenPlace
                    )
                }
            } else {
                MarkdownText(markdown: turn.text, colorScheme: colorScheme)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SelineChatResponseBlockView: View {
    let block: SelineChatResponseBlock
    let colorScheme: ColorScheme
    let currentLocation: CLLocation?
    let onOpenEvidence: (SelineChatEvidenceItem) -> Void
    let onOpenPlace: (SelineChatPlaceResult) -> Void

    var body: some View {
        switch block {
        case .markdown(let markdown):
            MarkdownText(markdown: markdown, colorScheme: colorScheme)
        case .evidence(let title, let items):
            VStack(alignment: .leading, spacing: 10) {
                Text(title.uppercased())
                    .font(FontManager.geist(size: 11, weight: .semibold))
                    .foregroundColor(Color.appTextSecondary(colorScheme))
                    .tracking(0.6)

                ForEach(items) { item in
                    Button {
                        onOpenEvidence(item)
                    } label: {
                        SelineChatEvidenceCardView(item: item, colorScheme: colorScheme)
                    }
                    .buttonStyle(.plain)
                }
            }
        case .places(let title, let results, let showMap):
            SelineChatPlacesBlockView(
                title: title,
                results: results,
                showMap: showMap,
                currentLocation: currentLocation,
                colorScheme: colorScheme,
                onOpenPlace: onOpenPlace
            )
        case .citations(let citations):
            VStack(alignment: .leading, spacing: 10) {
                Text("Sources")
                    .font(FontManager.geist(size: 11, weight: .semibold))
                    .foregroundColor(Color.appTextSecondary(colorScheme))
                    .tracking(0.6)

                ForEach(citations) { citation in
                    if let url = URL(string: citation.url) {
                        Link(destination: url) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "link")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(Color.homeGlassAccent)
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(citation.title)
                                        .font(FontManager.geist(size: 14, weight: .semibold))
                                        .foregroundColor(Color.appTextPrimary(colorScheme))
                                        .multilineTextAlignment(.leading)

                                    Text(citation.source ?? citation.url)
                                        .font(FontManager.geist(size: 12, weight: .regular))
                                        .foregroundColor(Color.appTextSecondary(colorScheme))
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(colorScheme == .dark ? Color.appInnerSurface(colorScheme) : Color.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.appBorder(colorScheme), lineWidth: 1)
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct SelineChatUserTurnView: View {
    let turn: SelineChatTurn
    let colorScheme: ColorScheme

    var body: some View {
        HStack {
            Spacer(minLength: 52)

            Text(turn.text)
                .font(FontManager.geist(size: 15, weight: .medium))
                .foregroundColor(Color.appTextPrimary(colorScheme))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(colorScheme == .dark ? Color.appInnerSurface(colorScheme) : Color.black.opacity(0.045))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.appBorder(colorScheme), lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SelineChatEvidenceCardView: View {
    let item: SelineChatEvidenceItem
    let colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: item.kind.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color.homeGlassAccent)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(Color.homeGlassAccent.opacity(colorScheme == .dark ? 0.16 : 0.12))
                    )

                Text(item.kind.label.uppercased())
                    .font(FontManager.geist(size: 10, weight: .semibold))
                    .foregroundColor(Color.appTextSecondary(colorScheme))
                    .tracking(0.6)

                Spacer(minLength: 0)

                if let footnote = item.footnote, !footnote.isEmpty {
                    Text(footnote)
                        .font(FontManager.geist(size: 11, weight: .medium))
                        .foregroundColor(Color.appTextSecondary(colorScheme))
                }
            }

            Text(item.title)
                .font(FontManager.geist(size: 14, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))

            Text(item.subtitle)
                .font(FontManager.geist(size: 13, weight: .regular))
                .foregroundColor(Color.appTextPrimary(colorScheme))

            if let detail = item.detail, !detail.isEmpty {
                Text(detail)
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(Color.appTextSecondary(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(colorScheme == .dark ? Color.appInnerSurface(colorScheme) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.appBorder(colorScheme), lineWidth: 1)
        )
    }
}

private struct SelineChatPlacesBlockView: View {
    let title: String
    let results: [SelineChatPlaceResult]
    let showMap: Bool
    let currentLocation: CLLocation?
    let colorScheme: ColorScheme
    let onOpenPlace: (SelineChatPlaceResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(FontManager.geist(size: 11, weight: .semibold))
                .foregroundColor(Color.appTextSecondary(colorScheme))
                .tracking(0.6)

            if showMap {
                SearchResultsMapView(
                    searchResults: results.map(\.asSearchResult),
                    currentLocation: currentLocation,
                    onResultTap: { tapped in
                        guard let place = results.first(where: { $0.googlePlaceID == tapped.id }) else { return }
                        onOpenPlace(place)
                    }
                )
            }

            VStack(spacing: 8) {
                ForEach(results) { result in
                    Button {
                        onOpenPlace(result)
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(Color.red.opacity(colorScheme == .dark ? 0.18 : 0.12))
                                    .frame(width: 30, height: 30)

                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.red)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.name)
                                    .font(FontManager.geist(size: 14, weight: .semibold))
                                    .foregroundColor(Color.appTextPrimary(colorScheme))
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text(result.subtitle)
                                    .font(FontManager.geist(size: 12, weight: .regular))
                                    .foregroundColor(Color.appTextSecondary(colorScheme))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(colorScheme == .dark ? Color.appInnerSurface(colorScheme) : Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.appBorder(colorScheme), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct SelineChatThinkingRow: View {
    let title: String
    let sourceChips: [String]
    let colorScheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(Color.homeGlassAccent)

                Text(title)
                    .font(FontManager.geist(size: 13, weight: .medium))
                    .foregroundColor(Color.appTextPrimary(colorScheme))
            }

            HStack(spacing: 6) {
                ForEach(sourceChips, id: \.self) { chip in
                    Text(chip)
                        .font(FontManager.geist(size: 10, weight: .semibold))
                        .foregroundColor(Color.appTextSecondary(colorScheme))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.appChip(colorScheme))
                        )
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(colorScheme == .dark ? Color.appSurface(colorScheme) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.appBorder(colorScheme), lineWidth: 1)
        )
    }
}

private struct SelineChatQuickActionButton: View {
    let suggestion: SelineChatPromptSuggestion
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.homeGlassAccent.opacity(colorScheme == .dark ? 0.16 : 0.10))
                    .frame(width: 30, height: 30)

                Image(systemName: suggestion.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.homeGlassAccent)
            }

            Text(suggestion.title)
                .font(FontManager.geist(size: 14, weight: .medium))
                .foregroundColor(Color.appTextPrimary(colorScheme))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.up.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.appTextSecondary(colorScheme))
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.025))
                )
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(
            Capsule(style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.025) : Color.black.opacity(0.015))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.appBorder(colorScheme), lineWidth: 1)
        )
    }
}

private struct SelineChatSidebarRow: View {
    let thread: SelineChatThread
    let timestamp: String
    let isSelected: Bool
    let fillColor: Color
    let colorScheme: ColorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "message")
                .font(.system(size: 14, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.45) : .black.opacity(0.38))
                .frame(width: 20)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) {
                    Text(thread.title)
                        .font(FontManager.geist(size: 15, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.96) : .black.opacity(0.88))
                        .lineLimit(1)

                    Spacer()

                    Text(timestamp)
                        .font(FontManager.geist(size: 12, weight: .regular))
                        .foregroundColor(colorScheme == .dark ? .white.opacity(0.4) : .black.opacity(0.4))
                        .lineLimit(1)
                }

                Text(thread.previewText)
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.58) : .black.opacity(0.52))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fillColor)
        .contentShape(Rectangle())
    }
}

#Preview {
    ChatView()
        .environmentObject(LocationService.shared)
}
