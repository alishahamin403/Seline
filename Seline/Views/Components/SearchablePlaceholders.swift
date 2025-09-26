import SwiftUI

// MARK: - Searchable Placeholder Views

struct EmailPlaceholderView: View, Searchable {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack {
            Spacer()
            Text("Email")
                .font(.system(size: 24, weight: .bold, design: .default))
                .foregroundColor(Color.shadcnMutedForeground(colorScheme))
            Text("Coming Soon")
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundColor(Color.shadcnMutedForeground(colorScheme))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.shadcnBackground(colorScheme))
        .onAppear {
            SearchService.shared.registerSearchableProvider(self, for: .email)
        }
    }

    func getSearchableContent() -> [SearchableItem] {
        return [
            SearchableItem(
                title: "Email Management",
                content: "Manage your emails, inbox, drafts, and sent messages. Stay organized with smart categorization.",
                type: .email,
                identifier: "email-main",
                metadata: ["category": "communication", "status": "coming-soon"]
            ),
            SearchableItem(
                title: "Inbox",
                content: "View and manage incoming emails with intelligent filtering and sorting.",
                type: .email,
                identifier: "email-inbox",
                metadata: ["feature": "inbox", "priority": "high"]
            ),
            SearchableItem(
                title: "Compose Email",
                content: "Write and send new emails with rich text formatting and attachments.",
                type: .email,
                identifier: "email-compose",
                metadata: ["feature": "compose", "action": "send"]
            )
        ]
    }
}

struct EventsPlaceholderView: View, Searchable {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack {
            Spacer()
            Text("Events")
                .font(.system(size: 24, weight: .bold, design: .default))
                .foregroundColor(Color.shadcnMutedForeground(colorScheme))
            Text("Coming Soon")
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundColor(Color.shadcnMutedForeground(colorScheme))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.shadcnBackground(colorScheme))
        .onAppear {
            SearchService.shared.registerSearchableProvider(self, for: .events)
        }
    }

    func getSearchableContent() -> [SearchableItem] {
        return [
            SearchableItem(
                title: "Calendar Events",
                content: "Schedule and manage your calendar events, meetings, and appointments.",
                type: .events,
                identifier: "events-main",
                metadata: ["category": "scheduling", "status": "coming-soon"]
            ),
            SearchableItem(
                title: "Create Event",
                content: "Schedule new meetings, appointments, and reminders with smart suggestions.",
                type: .events,
                identifier: "events-create",
                metadata: ["feature": "create", "action": "schedule"]
            ),
            SearchableItem(
                title: "Today's Schedule",
                content: "View your daily agenda and upcoming events at a glance.",
                type: .events,
                identifier: "events-today",
                metadata: ["feature": "agenda", "timeframe": "today"]
            )
        ]
    }
}

struct NotesPlaceholderView: View, Searchable {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack {
            Spacer()
            Text("Notes")
                .font(.system(size: 24, weight: .bold, design: .default))
                .foregroundColor(Color.shadcnMutedForeground(colorScheme))
            Text("Coming Soon")
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundColor(Color.shadcnMutedForeground(colorScheme))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.shadcnBackground(colorScheme))
        .onAppear {
            SearchService.shared.registerSearchableProvider(self, for: .notes)
        }
    }

    func getSearchableContent() -> [SearchableItem] {
        return [
            SearchableItem(
                title: "Note Taking",
                content: "Create, edit, and organize your notes with rich text formatting and multimedia support.",
                type: .notes,
                identifier: "notes-main",
                metadata: ["category": "productivity", "status": "coming-soon"]
            ),
            SearchableItem(
                title: "Quick Notes",
                content: "Capture thoughts and ideas instantly with voice-to-text and smart formatting.",
                type: .notes,
                identifier: "notes-quick",
                metadata: ["feature": "quick-capture", "input": "voice"]
            ),
            SearchableItem(
                title: "Notebooks",
                content: "Organize your notes into categorized notebooks for better project management.",
                type: .notes,
                identifier: "notes-notebooks",
                metadata: ["feature": "organization", "type": "notebooks"]
            )
        ]
    }
}

struct MapsPlaceholderView: View, Searchable {
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack {
            Spacer()
            Text("Maps")
                .font(.system(size: 24, weight: .bold, design: .default))
                .foregroundColor(Color.shadcnMutedForeground(colorScheme))
            Text("Coming Soon")
                .font(.system(size: 12, weight: .regular, design: .default))
                .foregroundColor(Color.shadcnMutedForeground(colorScheme))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.shadcnBackground(colorScheme))
        .onAppear {
            SearchService.shared.registerSearchableProvider(self, for: .maps)
        }
    }

    func getSearchableContent() -> [SearchableItem] {
        return [
            SearchableItem(
                title: "Maps & Navigation",
                content: "Navigate, explore, and discover locations with intelligent routing and local insights.",
                type: .maps,
                identifier: "maps-main",
                metadata: ["category": "navigation", "status": "coming-soon"]
            ),
            SearchableItem(
                title: "Find Places",
                content: "Search for restaurants, shops, services, and points of interest near you.",
                type: .maps,
                identifier: "maps-search",
                metadata: ["feature": "search", "scope": "local"]
            ),
            SearchableItem(
                title: "Directions",
                content: "Get turn-by-turn navigation with traffic updates and route optimization.",
                type: .maps,
                identifier: "maps-directions",
                metadata: ["feature": "navigation", "realtime": "traffic"]
            ),
            SearchableItem(
                title: "Saved Places",
                content: "Save your favorite locations, home, work, and frequently visited places.",
                type: .maps,
                identifier: "maps-saved",
                metadata: ["feature": "bookmarks", "personal": "favorites"]
            )
        ]
    }
}