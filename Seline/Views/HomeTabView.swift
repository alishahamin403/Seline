import SwiftUI

struct HomeTabView<Content: View>: View {
    let isVisible: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
    }
}

struct HomeWidgetStackView: View {
    @ObservedObject var homeState: HomeDashboardState
    let isVisible: Bool
    @Binding var isDailyOverviewExpanded: Bool
    let currentLocationName: String
    let nearbyLocation: String?
    let nearbyLocationFolder: String?
    let nearbyLocationPlace: SavedPlace?
    let distanceToNearest: Double?
    @Binding var selectedPlace: SavedPlace?
    @Binding var showAllLocationsSheet: Bool
    let onNoteSelected: (Note) -> Void
    let onEmailSelected: (Email) -> Void
    let onTaskSelected: (TaskItem) -> Void
    let onPersonSelected: (Person) -> Void
    let onAddTask: () -> Void
    let onAddTaskFromPhoto: () -> Void
    let onAddNote: () -> Void
    let onAddReceiptFromCamera: () -> Void
    let onAddReceiptFromGallery: () -> Void
    let onReceiptSelected: (ReceiptStat) -> Void
    let onRefresh: () -> Void

    private var homeCardHorizontalPadding: CGFloat {
        max(ShadcnSpacing.screenEdgeHorizontal, 12)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
                if homeState.hasPendingLocationSuggestion {
                    NewLocationSuggestionCard()
                        .padding(.horizontal, homeCardHorizontalPadding)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                }

                DailyOverviewWidget(
                    homeState: homeState,
                    isExpanded: $isDailyOverviewExpanded,
                    isVisible: isVisible,
                    currentLocationName: currentLocationName,
                    nearbyLocation: nearbyLocation,
                    nearbyLocationPlace: nearbyLocationPlace,
                    distanceToNearest: distanceToNearest,
                    onNoteSelected: onNoteSelected,
                    onEmailSelected: onEmailSelected,
                    onTaskSelected: onTaskSelected,
                    onPersonSelected: onPersonSelected,
                    onLocationSelected: { place in
                        selectedPlace = place
                    },
                    onAddTask: onAddTask,
                    onAddTaskFromPhoto: onAddTaskFromPhoto,
                    onAddNote: onAddNote
                )
                .padding(.horizontal, homeCardHorizontalPadding)
                .zIndex(isDailyOverviewExpanded ? 10 : 1)

                SpendingAndETAWidget(
                    isVisible: isVisible,
                    onAddReceipt: onAddReceiptFromCamera,
                    onAddReceiptFromGallery: onAddReceiptFromGallery,
                    onReceiptSelected: onReceiptSelected
                )
                .padding(.horizontal, homeCardHorizontalPadding)
                .padding(.top, 4)
                .padding(.bottom, 6)
            }
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .selinePrimaryPageScroll()
        .refreshable {
            onRefresh()
        }
    }
}
