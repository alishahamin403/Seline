import SwiftUI

struct RetainedTabContainer<Tab: Hashable, Content: View>: View {
    @Binding private var selection: Tab

    private let allTabs: [Tab]
    private let content: (Tab, Bool) -> Content

    @State private var loadedTabs: [Tab]

    init(
        selection: Binding<Tab>,
        allTabs: [Tab],
        initialTabs: [Tab]? = nil,
        @ViewBuilder content: @escaping (Tab, Bool) -> Content
    ) {
        self._selection = selection
        self.allTabs = allTabs
        self.content = content

        let seededTabs = Self.deduplicated(initialTabs ?? [selection.wrappedValue])
        self._loadedTabs = State(initialValue: seededTabs)
    }

    var body: some View {
        ZStack {
            ForEach(orderedLoadedTabs, id: \.self) { tab in
                content(tab, tab == selection)
                    .opacity(tab == selection ? 1 : 0)
                    .allowsHitTesting(tab == selection)
                    .accessibilityHidden(tab != selection)
                    .zIndex(tab == selection ? 1 : 0)
            }
        }
        .onAppear {
            ensureLoaded(selection)
        }
        .onChange(of: selection) { newSelection in
            ensureLoaded(newSelection)
        }
    }

    private var orderedLoadedTabs: [Tab] {
        let loadedSet = Set(loadedTabs)
        return allTabs.filter { loadedSet.contains($0) }
    }

    private func ensureLoaded(_ tab: Tab) {
        guard !loadedTabs.contains(tab) else { return }
        loadedTabs.append(tab)
    }

    private static func deduplicated(_ tabs: [Tab]) -> [Tab] {
        var seen = Set<Tab>()
        return tabs.filter { seen.insert($0).inserted }
    }
}
