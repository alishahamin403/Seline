import SwiftUI
import CoreLocation

struct ChatView: View {
    var isVisible: Bool = true
    var bottomTabSelection: Binding<PrimaryTab>? = nil
    var showsAttachedBottomTabBar: Bool = false
    var onOpenEmail: ((Email) -> Void)? = nil
    var onOpenTask: ((TaskItem) -> Void)? = nil
    var onOpenNote: ((Note) -> Void)? = nil
    var onOpenPlace: ((SavedPlace) -> Void)? = nil
    var onOpenPerson: ((Person) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var locationService: LocationService
    @FocusState private var isComposerFocused: Bool
    @StateObject private var store = SelineChatStore.shared
    @ObservedObject private var speechService = SpeechRecognitionService.shared
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

    @ViewBuilder
    private func attachedBottomTabBar(bottomSafeAreaInset: CGFloat) -> some View {
        if showsAttachedBottomTabBar, let bottomTabSelection {
            SidebarAttachedBottomTabBar(
                selectedTab: bottomTabSelection,
                bottomSafeAreaInset: bottomSafeAreaInset
            )
        }
    }

    var body: some View {
        GeometryReader { geometry in
            InteractiveSidebarOverlay(
                isPresented: $isSidebarPresented,
                canOpen: isVisible,
                sidebarWidth: min(336, geometry.size.width * 0.86),
                colorScheme: colorScheme
            ) {
                VStack(spacing: 0) {
                    ZStack {
                        AppAmbientBackgroundLayer(
                            colorScheme: colorScheme,
                            variant: .topLeading
                        )
                        chatShell(topInset: geometry.safeAreaInsets.top)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    attachedBottomTabBar(bottomSafeAreaInset: geometry.safeAreaInsets.bottom)
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            } sidebarContent: {
                sidebarContent
            }
        }
        .onChange(of: isVisible) { newValue in
            if !newValue { isSidebarPresented = false }
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
                    .background(Circle().fill(colorScheme == .dark ? Color.appInnerSurface(colorScheme) : Color.white))
                    .overlay(Circle().stroke(Color.appBorder(colorScheme), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Text("Chat")
                .font(FontManager.geist(size: 16, weight: .semibold))
                .foregroundColor(Color.appTextPrimary(colorScheme))

            Spacer(minLength: 0)

            Button { beginNewChat() } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.appTextPrimary(colorScheme))
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(colorScheme == .dark ? Color.appInnerSurface(colorScheme) : Color.white))
                    .overlay(Circle().stroke(Color.appBorder(colorScheme), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, topInset > 0 ? 4 : 6)
        .padding(.bottom, 4)
        .background(Color.appBackground(colorScheme))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.appBorder(colorScheme)).frame(height: 0.5)
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

                        Color.clear.frame(height: 8).id(scrollAnchorID)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .selinePrimaryPageScroll()
                .onAppear { scrollToBottom(using: proxy, animated: false) }
                .onChange(of: store.selectedThreadID) { _ in scrollToBottom(using: proxy, animated: false) }
                .onChange(of: selectedThreadTurnCount) { _ in scrollToBottom(using: proxy) }
                .onChange(of: shouldShowThinkingRow) { _ in scrollToBottom(using: proxy) }
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
                    SelineChatQuickActionButton(suggestion: suggestion, colorScheme: colorScheme)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: 332)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: — Composer

    private var composerInset: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                // Voice button
                Button {
                    if speechService.isRecording {
                        stopVoiceRecording()
                    } else {
                        startVoiceRecording()
                    }
                } label: {
                    ZStack {
                        if speechService.isRecording {
                            SelineChatRecordingPulse()
                                .frame(width: 28, height: 28)
                        } else {
                            Image(systemName: "waveform")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Color.appTextSecondary(colorScheme))
                                .frame(width: 28, height: 28)
                        }
                    }
                }
                .buttonStyle(.plain)

                // Text field
                TextField("Ask anything about your day…", text: $draft, axis: .vertical)
                    .font(FontManager.geist(size: 15, weight: .regular))
                    .foregroundColor(Color.appTextPrimary(colorScheme))
                    .lineLimit(1...4)
                    .focused($isComposerFocused)
                    .submitLabel(.send)
                    .onSubmit { submitDraft() }
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Send button
                Button { submitDraft() } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(canSendDraft ? Color.white : Color.appTextSecondary(colorScheme))
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(canSendDraft ? Color.homeGlassAccent : Color.appChip(colorScheme))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSendDraft)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(colorScheme == .dark ? Color.appSurface(colorScheme) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.appBorder(colorScheme), lineWidth: 1)
            )
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 6)
        }
        .background(Color.appBackground(colorScheme))
    }

    // MARK: — Sidebar

    private var sidebarContent: some View {
        ZStack {
            sidebarBackgroundColor.ignoresSafeArea()

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
                    .background(RoundedRectangle(cornerRadius: 10).fill(searchFieldFillColor))

                    Button { beginNewChat() } label: {
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
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 4)

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

                        Spacer().frame(height: 100)
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

    // MARK: — Helpers

    private var canSendDraft: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submitDraft() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        draft = ""
        isComposerFocused = false
        submitPrompt(trimmed)
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

    // MARK: — Voice

    private func startVoiceRecording() {
        HapticManager.shared.voiceInput()
        speechService.onTranscriptionUpdate = { text in
            self.draft = text
        }
        Task {
            try? await speechService.startRecording()
        }
    }

    private func stopVoiceRecording() {
        speechService.stopRecording()
        // draft already contains the final transcribed text via onTranscriptionUpdate
    }

    // MARK: — Date helpers

    private func sidebarSectionTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()), date >= weekAgo { return "This Week" }
        return "Older"
    }

    private func formattedSidebarTimestamp(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return FormatterCache.shortTime.string(from: date) }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date()), date >= weekAgo {
            return FormatterCache.weekdayFull.string(from: date)
        }
        return FormatterCache.shortDate.string(from: date)
    }

    // MARK: — Tap handlers

    private func handleEvidenceTap(_ item: SelineChatEvidenceItem) {
        switch item.kind {
        case .email:
            guard let emailID = item.emailID,
                  let email = (EmailService.shared.inboxEmails + EmailService.shared.sentEmails).first(where: { $0.id == emailID }) else { return }
            onOpenEmail?(email)
        case .event:
            guard let taskID = item.taskID,
                  let task = TaskManager.shared.getAllFlattenedTasks().first(where: { $0.id == taskID }) else { return }
            onOpenTask?(task)
        case .note, .receipt:
            guard let noteID = item.noteID,
                  let note = NotesManager.shared.notes.first(where: { $0.id == noteID }) else { return }
            onOpenNote?(note)
        case .visit:
            guard let placeID = item.placeID,
                  let place = LocationsManager.shared.savedPlaces.first(where: { $0.id == placeID }) else { return }
            onOpenPlace?(place)
        case .person:
            guard let personID = item.personID,
                  let person = PeopleManager.shared.people.first(where: { $0.id == personID }) else { return }
            onOpenPerson?(person)
        case .daySummary, .tracker:
            break
        }
    }

    private func handlePlaceTap(_ result: SelineChatPlaceResult) {
        onOpenPlace?(result.resolvedSavedPlace())
    }
}

// MARK: — Supporting structs

private struct SelineChatPromptSuggestion: Identifiable, Hashable {
    let id = UUID()
    let title: String

    var systemImage: String {
        switch title {
        case "How's my day today": return "sun.max"
        case "Any new emails?": return "tray"
        case "What's nearby?": return "location"
        case "Spending this week": return "creditcard"
        default: return "sparkles"
        }
    }
}

private struct SelineChatSidebarSection: Identifiable {
    let title: String
    let threads: [SelineChatThread]
    var id: String { title }
}

// MARK: — Recording pulse indicator

private struct SelineChatRecordingPulse: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 6, height: 6)
            .scaleEffect(pulsing ? 1.35 : 1.0)
            .opacity(pulsing ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
    }
}

// MARK: — Assistant turn

private struct SelineChatAssistantTurnView: View {
    let turn: SelineChatTurn
    let colorScheme: ColorScheme
    let currentLocation: CLLocation?
    let onOpenEvidence: (SelineChatEvidenceItem) -> Void
    let onOpenPlace: (SelineChatPlaceResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Source chips — redesigned as minimal pills
            if let chips = turn.assistantPayload?.sourceChips, !chips.isEmpty {
                HStack(spacing: 6) {
                    ForEach(chips, id: \.self) { chip in
                        SelineChatSourceChip(label: chip, colorScheme: colorScheme)
                    }
                }
            }

            if let payload = turn.assistantPayload {
                let firstMarkdownIndex = payload.responseBlocks.firstIndex { block in
                    if case .markdown = block {
                        return true
                    }
                    return false
                }

                ForEach(Array(payload.responseBlocks.enumerated()), id: \.offset) { entry in
                    SelineChatResponseBlockView(
                        block: entry.element,
                        inlineSources: entry.offset == (firstMarkdownIndex ?? -1) ? payload.inlineSources : [],
                        colorScheme: colorScheme,
                        currentLocation: currentLocation,
                        onOpenEvidence: onOpenEvidence,
                        onOpenPlace: onOpenPlace
                    )
                }
            } else {
                MarkdownText(markdown: turn.text, colorScheme: colorScheme)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: — Flow layout for wrapping chips

private struct SelineChatChipFlow<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        _SelineChatFlowLayout(spacing: spacing) {
            content()
        }
    }
}

private struct _SelineChatFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: width, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: — Source chip (minimal pill)

private struct SelineChatSourceChip: View {
    let label: String
    let colorScheme: ColorScheme

    private var iconName: String {
        let l = label.lowercased()
        if l.contains("location") || l.contains("visit") || l.contains("place") { return "location.fill" }
        if l.contains("email") || l.contains("mail") { return "envelope.fill" }
        if l.contains("calendar") || l.contains("event") { return "calendar" }
        if l.contains("note") { return "note.text" }
        if l.contains("health") || l.contains("step") || l.contains("sleep") { return "heart.fill" }
        if l.contains("web") || l.contains("search") || l.contains("news") { return "globe" }
        if l.contains("contact") || l.contains("person") { return "person.fill" }
        if l.contains("spend") || l.contains("receipt") || l.contains("finance") { return "creditcard.fill" }
        return "sparkle"
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: iconName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Color.homeGlassAccent)

            Text(label)
                .font(FontManager.geist(size: 11, weight: .medium))
                .foregroundColor(Color.appTextSecondary(colorScheme))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(colorScheme == .dark
                    ? Color.homeGlassAccent.opacity(0.08)
                    : Color.homeGlassAccent.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.homeGlassAccent.opacity(0.18), lineWidth: 1)
        )
    }
}

// MARK: — Response block router

private struct SelineChatResponseBlockView: View {
    let block: SelineChatResponseBlock
    let inlineSources: [SelineChatInlineSource]
    let colorScheme: ColorScheme
    let currentLocation: CLLocation?
    let onOpenEvidence: (SelineChatEvidenceItem) -> Void
    let onOpenPlace: (SelineChatPlaceResult) -> Void

    var body: some View {
        switch block {
        case .markdown(let markdown):
            if let annotations = SelineChatInlineSentenceAnnotation.annotations(
                for: markdown,
                sources: inlineSources
            ) {
                SelineChatInlineAnnotatedMarkdownView(
                    annotations: annotations,
                    colorScheme: colorScheme,
                    onOpenEvidence: onOpenEvidence,
                    onOpenPlace: onOpenPlace
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    MarkdownText(markdown: markdown, colorScheme: colorScheme)
                        .textSelection(.enabled)

                    if !inlineSources.isEmpty {
                        SelineChatInlineSourcesView(
                            sources: inlineSources,
                            colorScheme: colorScheme,
                            onOpenEvidence: onOpenEvidence,
                            onOpenPlace: onOpenPlace
                        )
                    }
                }
            }

        case .evidence(_, let items):
            SelineChatChipFlow(spacing: 6) {
                ForEach(items) { item in
                    Button {
                        onOpenEvidence(item)
                    } label: {
                        SelineChatEvidenceInlineChip(item: item, colorScheme: colorScheme)
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
            VStack(alignment: .leading, spacing: 8) {
                Text("SOURCES")
                    .font(FontManager.geist(size: 10, weight: .semibold))
                    .foregroundColor(Color.appTextSecondary(colorScheme))
                    .tracking(0.5)

                ForEach(citations) { citation in
                    if let url = URL(string: citation.url) {
                        Link(destination: url) {
                            HStack(alignment: .center, spacing: 10) {
                                Image(systemName: "link")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(Color.homeGlassAccent)
                                    .frame(width: 28, height: 28)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(Color.homeGlassAccent.opacity(
                                                colorScheme == .dark ? 0.12 : 0.09))
                                    )

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(citation.title)
                                        .font(FontManager.geist(size: 13, weight: .semibold))
                                        .foregroundColor(Color.appTextPrimary(colorScheme))
                                        .lineLimit(1)

                                    Text(citation.source ?? citation.url)
                                        .font(FontManager.geist(size: 11, weight: .regular))
                                        .foregroundColor(Color.appTextSecondary(colorScheme))
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)

                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(Color.appTextSecondary(colorScheme))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(colorScheme == .dark ? Color.appInnerSurface(colorScheme) : Color.white)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(Color.appBorder(colorScheme), lineWidth: 1)
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct SelineChatInlineSentenceAnnotation: Identifiable {
    let id: Int
    let text: String
    let sources: [SelineChatInlineSource]

    static func annotations(
        for markdown: String,
        sources: [SelineChatInlineSource]
    ) -> [SelineChatInlineSentenceAnnotation]? {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        let limitedSources = Array(sources.prefix(3))
        guard !trimmed.isEmpty, !limitedSources.isEmpty else { return nil }
        guard isSimpleInlineAnnotatable(markdown: trimmed) else { return nil }

        let sentences = splitSentences(from: trimmed)
        guard !sentences.isEmpty, sentences.count <= 3 else { return nil }

        if sentences.count == 1 {
            return [SelineChatInlineSentenceAnnotation(id: 0, text: sentences[0], sources: limitedSources)]
        }

        var assigned = Array(repeating: [SelineChatInlineSource](), count: sentences.count)
        var hadDirectMatch = false
        var overflow: [SelineChatInlineSource] = []

        for source in limitedSources {
            let bestMatch = sentences.enumerated()
                .map { index, sentence in
                    (index: index, score: relevanceScore(for: source, in: sentence))
                }
                .max { lhs, rhs in lhs.score < rhs.score }

            if let bestMatch, bestMatch.score > 0 {
                hadDirectMatch = true
                if assigned[bestMatch.index].count < 2 {
                    assigned[bestMatch.index].append(source)
                } else {
                    overflow.append(source)
                }
            } else {
                overflow.append(source)
            }
        }

        guard hadDirectMatch else { return nil }

        for source in overflow {
            guard let targetIndex = assigned.enumerated()
                .filter({ $0.element.count < 2 })
                .min(by: { $0.element.count < $1.element.count })?
                .offset else {
                break
            }
            assigned[targetIndex].append(source)
        }

        return sentences.enumerated().map { index, sentence in
            SelineChatInlineSentenceAnnotation(id: index, text: sentence, sources: assigned[index])
        }
    }

    private static func isSimpleInlineAnnotatable(markdown: String) -> Bool {
        if markdown.contains("```")
            || markdown.contains("|")
            || markdown.contains("\n\n")
            || markdown.contains("**")
            || markdown.contains("__")
            || markdown.contains("`")
            || markdown.contains("](")
            || markdown.contains("[") {
            return false
        }

        let lines = markdown
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty, lines.count <= 3 else { return false }

        for line in lines {
            if line.hasPrefix("#") || line.hasPrefix(">") || line.hasPrefix("- ") || line.hasPrefix("* ") {
                return false
            }

            if let firstScalar = line.unicodeScalars.first,
               CharacterSet.decimalDigits.contains(firstScalar),
               line.contains(". ") {
                return false
            }
        }

        return true
    }

    private static func splitSentences(from text: String) -> [String] {
        var sentences: [String] = []
        var current = ""

        for character in text {
            current.append(character)
            if character == "." || character == "!" || character == "?" {
                let sentence = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !sentence.isEmpty {
                    sentences.append(sentence)
                }
                current = ""
            }
        }

        let trailing = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trailing.isEmpty {
            sentences.append(trailing)
        }

        return sentences
    }

    private static func relevanceScore(
        for source: SelineChatInlineSource,
        in sentence: String
    ) -> Double {
        let normalizedSentence = normalized(sentence)
        guard !normalizedSentence.isEmpty else { return 0 }

        var score = 0.0
        for phrase in candidatePhrases(for: source) {
            guard !phrase.isEmpty else { continue }
            if normalizedSentence.contains(phrase) {
                score += phrase.contains(" ") ? 8 : 5
            } else {
                let tokens = phrase.split(separator: " ").map(String.init).filter { $0.count >= 4 }
                for token in tokens where normalizedSentence.contains(token) {
                    score += 1.5
                }
            }
        }

        return score
    }

    private static func candidatePhrases(for source: SelineChatInlineSource) -> [String] {
        var rawValues: [String] = [source.displayText]

        if let item = source.evidenceItem {
            rawValues.append(contentsOf: [
                item.title,
                item.subtitle,
                item.detail ?? "",
                item.footnote ?? ""
            ])
        }

        if let place = source.placeResult {
            rawValues.append(contentsOf: [
                place.name,
                place.subtitle,
                place.category ?? ""
            ])
        }

        if let citation = source.citation {
            rawValues.append(contentsOf: [
                citation.title,
                citation.source ?? "",
                URL(string: citation.url)?.host ?? ""
            ])
        }

        var seen = Set<String>()
        return rawValues
            .map(normalized)
            .flatMap { value -> [String] in
                guard !value.isEmpty else { return [] }
                let primary = value
                    .components(separatedBy: " · ")
                    .first?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? value
                return [value, primary]
            }
            .filter { phrase in
                guard phrase.count >= 3 else { return false }
                return seen.insert(phrase).inserted
            }
    }

    private static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

private struct SelineChatInlineAnnotatedMarkdownView: View {
    let annotations: [SelineChatInlineSentenceAnnotation]
    let colorScheme: ColorScheme
    let onOpenEvidence: (SelineChatEvidenceItem) -> Void
    let onOpenPlace: (SelineChatPlaceResult) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(annotations) { annotation in
                if annotation.sources.isEmpty {
                    sentenceText(annotation.text)
                        .textSelection(.enabled)
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            sentenceText(annotation.text)
                                .layoutPriority(1)
                                .textSelection(.enabled)

                            HStack(spacing: 4) {
                                ForEach(annotation.sources) { source in
                                    SelineChatInlineSourceControl(
                                        source: source,
                                        colorScheme: colorScheme,
                                        onOpenEvidence: onOpenEvidence,
                                        onOpenPlace: onOpenPlace,
                                        compact: true
                                    )
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            sentenceText(annotation.text)
                                .textSelection(.enabled)

                            SelineChatChipFlow(spacing: 4) {
                                ForEach(annotation.sources) { source in
                                    SelineChatInlineSourceControl(
                                        source: source,
                                        colorScheme: colorScheme,
                                        onOpenEvidence: onOpenEvidence,
                                        onOpenPlace: onOpenPlace,
                                        compact: true
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func sentenceText(_ text: String) -> some View {
        Text(text)
            .font(FontManager.geist(size: 15, weight: .regular))
            .foregroundColor(Color.appTextPrimary(colorScheme))
            .lineSpacing(4)
            .multilineTextAlignment(.leading)
    }
}

private struct SelineChatInlineSourcesView: View {
    let sources: [SelineChatInlineSource]
    let colorScheme: ColorScheme
    let onOpenEvidence: (SelineChatEvidenceItem) -> Void
    let onOpenPlace: (SelineChatPlaceResult) -> Void

    var body: some View {
        SelineChatChipFlow(spacing: 8) {
            ForEach(sources) { source in
                SelineChatInlineSourceControl(
                    source: source,
                    colorScheme: colorScheme,
                    onOpenEvidence: onOpenEvidence,
                    onOpenPlace: onOpenPlace,
                    compact: true
                )
            }
        }
    }
}

private struct SelineChatInlineSourceControl: View {
    let source: SelineChatInlineSource
    let colorScheme: ColorScheme
    let onOpenEvidence: (SelineChatEvidenceItem) -> Void
    let onOpenPlace: (SelineChatPlaceResult) -> Void
    let compact: Bool

    private var label: String {
        compactInlineSourceLabel(for: source)
    }

    private var systemImage: String {
        if let kind = source.evidenceItem?.kind {
            switch kind {
            case .email:
                return "envelope.fill"
            case .event:
                return "calendar"
            case .note:
                return "note.text"
            case .receipt:
                return "creditcard.fill"
            case .visit:
                return "mappin.and.ellipse"
            case .person:
                return "person.fill"
            case .daySummary:
                return "sun.max.fill"
            case .tracker:
                return "chart.line.uptrend.xyaxis"
            }
        }

        if source.placeResult != nil {
            return "mappin.circle.fill"
        }

        return "globe"
    }

    var body: some View {
        if let citation = source.citation,
           let url = URL(string: citation.url),
           !citation.url.isEmpty {
            Link(destination: url) {
                SelineChatInlineSourcePill(
                    label: label,
                    systemImage: systemImage,
                    colorScheme: colorScheme,
                    compact: compact
                )
            }
            .buttonStyle(.plain)
        } else if let evidenceItem = source.evidenceItem {
            Button {
                onOpenEvidence(evidenceItem)
            } label: {
                SelineChatInlineSourcePill(
                    label: label,
                    systemImage: systemImage,
                    colorScheme: colorScheme,
                    compact: compact
                )
            }
            .buttonStyle(.plain)
        } else if let placeResult = source.placeResult {
            Button {
                onOpenPlace(placeResult)
            } label: {
                SelineChatInlineSourcePill(
                    label: label,
                    systemImage: systemImage,
                    colorScheme: colorScheme,
                    compact: compact
                )
            }
            .buttonStyle(.plain)
        } else {
            EmptyView()
        }
    }

    private func compactInlineSourceLabel(for source: SelineChatInlineSource) -> String {
        if let item = source.evidenceItem {
            switch item.kind {
            case .email:
                return compactLabel(item.subtitle.isEmpty ? item.title : item.subtitle, maxWords: 2, maxLength: 18)
            case .daySummary:
                return compactLabel(item.subtitle.isEmpty ? item.title : item.subtitle, maxWords: 3, maxLength: 20)
            case .receipt:
                return compactLabel(item.title, maxWords: 2, maxLength: 18)
            case .event, .note, .visit, .person, .tracker:
                return compactLabel(item.title, maxWords: 3, maxLength: 18)
            }
        }

        if let place = source.placeResult {
            return compactLabel(place.name, maxWords: 3, maxLength: 18)
        }

        if let citation = source.citation {
            let base = citation.source?.trimmingCharacters(in: .whitespacesAndNewlines)
            let host = URL(string: citation.url)?
                .host?
                .replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
            return compactLabel(base?.isEmpty == false ? base! : (host ?? citation.title), maxWords: 2, maxLength: 18)
        }

        return compactLabel(source.displayText, maxWords: 3, maxLength: 18)
    }

    private func compactLabel(_ raw: String, maxWords: Int, maxLength: Int) -> String {
        let primary = raw
            .components(separatedBy: "·")
            .first?
            .components(separatedBy: "•")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? raw

        let cleaned = primary
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleaned.count > maxLength else { return cleaned }

        let words = cleaned.split(separator: " ")
        if words.count > 1 {
            let joined = words.prefix(maxWords).joined(separator: " ")
            if joined.count <= maxLength {
                return joined
            }
        }

        let clipped = String(cleaned.prefix(max(10, maxLength - 1)))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(clipped)…"
    }
}

// MARK: — User bubble

private struct SelineChatUserTurnView: View {
    let turn: SelineChatTurn
    let colorScheme: ColorScheme

    var body: some View {
        HStack {
            Spacer(minLength: 48)

            Text(turn.text)
                .font(FontManager.geist(size: 14.5, weight: .regular))
                .foregroundColor(Color.appTextPrimary(colorScheme))
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(colorScheme == .dark
                            ? Color.appInnerSurface(colorScheme)
                            : Color.black.opacity(0.045))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.appBorder(colorScheme), lineWidth: 1)
                )
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: — Evidence inline chip

private struct SelineChatEvidenceInlineChip: View {
    let item: SelineChatEvidenceItem
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: item.kind.systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color.homeGlassAccent)

            Text(item.title)
                .font(FontManager.geist(size: 12, weight: .medium))
                .foregroundColor(Color.appTextPrimary(colorScheme))
                .lineLimit(1)

            if let footnote = item.footnote, !footnote.isEmpty {
                Text("·")
                    .font(FontManager.geist(size: 12, weight: .regular))
                    .foregroundColor(Color.appTextSecondary(colorScheme))
                Text(footnote)
                    .font(FontManager.geist(size: 11, weight: .regular))
                    .foregroundColor(Color.appTextSecondary(colorScheme))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(colorScheme == .dark ? Color.appInnerSurface(colorScheme) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(Color.appBorder(colorScheme), lineWidth: 1)
        )
    }
}

private struct SelineChatInlineSourcePill: View {
    let label: String
    let systemImage: String
    let colorScheme: ColorScheme
    let compact: Bool

    var body: some View {
        HStack(spacing: compact ? 5 : 6) {
            Image(systemName: systemImage)
                .font(.system(size: compact ? 9 : 10, weight: .semibold))
                .foregroundColor(Color.appTextSecondary(colorScheme))

            Text(label)
                .font(FontManager.geist(size: compact ? 11 : 12, weight: .medium))
                .foregroundColor(Color.appTextPrimary(colorScheme))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, compact ? 9 : 11)
        .padding(.vertical, compact ? 6 : 8)
        .background(
            RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08), lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: — Places block (2-column grid)

private struct SelineChatPlacesBlockView: View {
    let title: String
    let results: [SelineChatPlaceResult]
    let showMap: Bool
    let currentLocation: CLLocation?
    let colorScheme: ColorScheme
    let onOpenPlace: (SelineChatPlaceResult) -> Void

    var body: some View {
        Group {
            if showMap {
                VStack(alignment: .leading, spacing: 10) {
                    Text(title.uppercased())
                        .font(FontManager.geist(size: 10, weight: .semibold))
                        .foregroundColor(Color.appTextSecondary(colorScheme))
                        .tracking(0.5)

                    SearchResultsMapView(
                        searchResults: results.map(\.asSearchResult),
                        currentLocation: currentLocation,
                        onResultTap: { tapped in
                            guard let place = results.first(where: { $0.googlePlaceID == tapped.id }) else { return }
                            onOpenPlace(place)
                        }
                    )
                }
            }
        }
    }
}

// MARK: — Thinking row

private struct SelineChatThinkingRow: View {
    let title: String
    let sourceChips: [String]
    let colorScheme: ColorScheme
    @State private var animateLogo = false

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            Image("AITabSIcon")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 13, height: 13)
                .foregroundColor(Color.homeGlassAccent)
                .opacity(animateLogo ? 1.0 : 0.32)
                .animation(
                    .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                    value: animateLogo
                )

            Text(title)
                .font(FontManager.geist(size: 13, weight: .medium))
                .foregroundColor(Color.appTextSecondary(colorScheme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
        .padding(.bottom, 2)
        .onAppear {
            animateLogo = true
        }
        .onDisappear {
            animateLogo = false
        }
    }
}

// MARK: — Quick action button (empty state)

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
                .background(Circle().fill(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.025)))
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(Capsule(style: .continuous).fill(colorScheme == .dark ? Color.white.opacity(0.025) : Color.black.opacity(0.015)))
        .overlay(Capsule(style: .continuous).stroke(Color.appBorder(colorScheme), lineWidth: 1))
    }
}

// MARK: — Sidebar row (no preview text)

private struct SelineChatSidebarRow: View {
    let thread: SelineChatThread
    let timestamp: String
    let isSelected: Bool
    let fillColor: Color
    let colorScheme: ColorScheme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "message")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.38) : .black.opacity(0.32))
                .frame(width: 18)

            Text(thread.title)
                .font(FontManager.geist(size: 14, weight: isSelected ? .semibold : .medium))
                .foregroundColor(colorScheme == .dark
                    ? .white.opacity(isSelected ? 1.0 : 0.82)
                    : .black.opacity(isSelected ? 0.9 : 0.76))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(timestamp)
                .font(FontManager.geist(size: 11, weight: .regular))
                .foregroundColor(colorScheme == .dark ? .white.opacity(0.35) : .black.opacity(0.35))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fillColor)
        .contentShape(Rectangle())
    }
}

#Preview {
    ChatView()
        .environmentObject(LocationService.shared)
}
