import Foundation

/**
 * PaginationHelper - Simple pagination utility
 *
 * Provides paginated access to large lists to reduce memory usage
 * and improve performance.
 *
 * Usage:
 * ```
 * let paginator = PaginationHelper(items: allEvents, pageSize: 50)
 * let firstPage = paginator.getPage(0)
 * let secondPage = paginator.getPage(1)
 * ```
 */
struct PaginationHelper<T> {
    private let items: [T]
    private let pageSize: Int

    init(items: [T], pageSize: Int = 50) {
        self.items = items
        self.pageSize = pageSize
    }

    // MARK: - Pagination Methods

    /**
     * Get a specific page of items
     *
     * - Parameter page: Zero-based page index
     * - Returns: Array of items for that page
     */
    func getPage(_ page: Int) -> [T] {
        let startIndex = page * pageSize
        guard startIndex < items.count else { return [] }

        let endIndex = min(startIndex + pageSize, items.count)
        return Array(items[startIndex..<endIndex])
    }

    /**
     * Get total number of pages
     */
    var totalPages: Int {
        return (items.count + pageSize - 1) / pageSize
    }

    /**
     * Get total number of items
     */
    var totalItems: Int {
        return items.count
    }

    /**
     * Check if a page exists
     */
    func hasPage(_ page: Int) -> Bool {
        return page >= 0 && page < totalPages
    }

    /**
     * Get items up to a certain page (cumulative)
     *
     * Useful for "load more" patterns
     */
    func getItemsUpToPage(_ page: Int) -> [T] {
        let endIndex = min((page + 1) * pageSize, items.count)
        return Array(items[0..<endIndex])
    }
}

// MARK: - Observable Pagination State

/**
 * Observable pagination state for SwiftUI views
 *
 * Usage:
 * ```
 * @StateObject var paginationState = PaginationState(items: allEvents)
 *
 * // In view
 * ForEach(paginationState.visibleItems) { item in ... }
 * Button("Load More") { paginationState.loadNextPage() }
 * ```
 */
@MainActor
class PaginationState<T: Identifiable>: ObservableObject {
    @Published var visibleItems: [T] = []
    @Published var currentPage: Int = 0
    @Published var isLoading: Bool = false

    private let paginator: PaginationHelper<T>

    init(items: [T], pageSize: Int = 50) {
        self.paginator = PaginationHelper(items: items, pageSize: pageSize)
        loadNextPage()
    }

    /**
     * Load the next page of items
     */
    func loadNextPage() {
        guard !isLoading else { return }
        guard paginator.hasPage(currentPage) else { return }

        isLoading = true

        // Simulate async loading (could be real async in future)
        Task {
            let newItems = paginator.getPage(currentPage)
            await MainActor.run {
                visibleItems.append(contentsOf: newItems)
                currentPage += 1
                isLoading = false
            }
        }
    }

    /**
     * Reset to first page
     */
    func reset() {
        currentPage = 0
        visibleItems = []
        loadNextPage()
    }

    /**
     * Check if there are more pages to load
     */
    var hasMore: Bool {
        return paginator.hasPage(currentPage)
    }

    /**
     * Get loading progress (0.0 to 1.0)
     */
    var progress: Double {
        guard paginator.totalItems > 0 else { return 1.0 }
        return Double(visibleItems.count) / Double(paginator.totalItems)
    }
}

// MARK: - Convenience Extensions

extension Array {
    /**
     * Quick pagination without creating a helper
     */
    func paginated(pageSize: Int = 50, page: Int) -> [Element] {
        let helper = PaginationHelper(items: self, pageSize: pageSize)
        return helper.getPage(page)
    }

    /**
     * Get first N items (safe - won't crash if count < n)
     */
    func limited(to count: Int) -> [Element] {
        return Array(prefix(count))
    }
}
