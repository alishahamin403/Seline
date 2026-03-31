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
    let onAddReceiptManually: () -> Void
    let onAddReceiptFromCamera: () -> Void
    let onAddReceiptFromGallery: () -> Void
    let onReceiptSelected: (ReceiptStat) -> Void
    let onRefresh: () -> Void

    private var homeCardHorizontalPadding: CGFloat {
        ShadcnSpacing.screenEdgeHorizontal
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 8) {
                if homeState.hasPendingLocationSuggestion {
                    NewLocationSuggestionCard()
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
                .zIndex(isDailyOverviewExpanded ? 10 : 1)

                SpendingAndETAWidget(
                    isVisible: isVisible,
                    onAddReceiptManually: onAddReceiptManually,
                    onAddReceipt: onAddReceiptFromCamera,
                    onAddReceiptFromGallery: onAddReceiptFromGallery,
                    onReceiptSelected: onReceiptSelected
                )
                .padding(.top, 4)
                .padding(.bottom, 6)
            }
            .padding(.horizontal, homeCardHorizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 96)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .selinePrimaryPageScroll()
        .refreshable {
            onRefresh()
        }
    }
}
