import SwiftUI
import CoreLocation

struct DailyOverviewWidget: View {
    @StateObject private var taskManager = TaskManager.shared
    @StateObject private var tagManager = TagManager.shared
    @StateObject private var weatherService = WeatherService.shared
    @StateObject private var locationService = LocationService.shared
    @StateObject private var quickNoteManager = QuickNoteManager.shared
    @Environment(\.colorScheme) var colorScheme

    @Binding var isExpanded: Bool

    var onNoteSelected: ((Note) -> Void)?
    var onEmailSelected: ((Email) -> Void)?
    var onTaskSelected: ((TaskItem) -> Void)?
    var onAddTask: (() -> Void)?
    var onAddTaskFromPhoto: (() -> Void)?
    var onAddNote: (() -> Void)?

    @State private var cachedTasks: [TaskItem] = []
    @State private var cachedTodayTasks: [TaskItem] = []
    @State private var lastWeatherFetch: Date?
    @State private var isTodoScrollInProgress = false
    @State private var expandedSection: ExpandedSection? = nil
    @State private var quickNoteInput: String = ""
    @State private var editingQuickNote: QuickNote? = nil

    @AppStorage("dismissedHomeMissedTodoIds") private var dismissedMissedTodoIdsString: String = ""
    
    private enum TodoRowMode {
        case today
        case missed
    }

    private enum ExpandedSection {
        case date
        case weather
        case quickNotes
    }

    private struct AllTodoCategoryGroup: Identifiable {
        let title: String
        let iconName: String
        let tasks: [TaskItem]
        var id: String { title.lowercased().replacingOccurrences(of: " ", with: "-") }
    }

    private var dayStart: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var dayEnd: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: Date())
    }

    private var weatherSummary: String {
        guard let weather = weatherService.weatherData else {
            return "Weather unavailable"
        }

        let desc = weather.description.capitalized
        let temp = "\(weather.temperature)°"
        let feelsLike = "Feels like \(weather.feelsLike)°"
        let location = weather.locationName.isEmpty ? locationService.locationName : weather.locationName
        return "\(location) • \(desc) • \(temp) • \(feelsLike)"
    }

    private var weatherChipText: String {
        guard let weather = weatherService.weatherData else {
            return "Weather --"
        }
        return "\(weather.temperature)° Feels \(weather.feelsLike)°"
    }

    private var dismissedMissedTodoIds: Set<String> {
        Set(dismissedMissedTodoIdsString.split(separator: ",").map(String.init))
    }

    private var todayTodos: [TaskItem] {
        cachedTodayTasks.filter { task in
            !task.isDeleted
        }
    }

    private var upNextTodos: [TaskItem] {
        let now = Date()

        return todayTodos
            .filter { task in
                guard !isTaskCompleted(task, mode: .today) else { return false }
                let due = todayOccurrenceDate(for: task)
                return due >= now && due < dayEnd
            }
            .sorted { todayOccurrenceDate(for: $0) < todayOccurrenceDate(for: $1) }
    }

    private var upNextShown: [TaskItem] {
        Array(upNextTodos.prefix(3))
    }

    private var allTodosExcludingUpNext: [TaskItem] {
        let upNextIds = Set(upNextShown.map(\.id))

        return todayTodos
            .filter { !upNextIds.contains($0.id) }
            .sorted { lhs, rhs in
                let lhsCompleted = isTaskCompleted(lhs, mode: .today)
                let rhsCompleted = isTaskCompleted(rhs, mode: .today)
                if lhsCompleted != rhsCompleted { return !lhsCompleted }
                return todayOccurrenceDate(for: lhs) < todayOccurrenceDate(for: rhs)
            }
    }

    private var allTodoGroups: [AllTodoCategoryGroup] {
        let orderedTasks = allTodosExcludingUpNext
        var firstSeenOrder: [String: Int] = [:]

        for task in orderedTasks {
            let title = allTodoCategoryTitle(for: task)
            if firstSeenOrder[title] == nil {
                firstSeenOrder[title] = firstSeenOrder.count
            }
        }

        let grouped = Dictionary(grouping: orderedTasks, by: allTodoCategoryTitle(for:))

        return grouped.map { title, tasks in
            AllTodoCategoryGroup(
                title: title,
                iconName: allTodoCategoryIconName(for: title),
                tasks: tasks.sorted { lhs, rhs in
                    let lhsCompleted = isTaskCompleted(lhs, mode: .today)
                    let rhsCompleted = isTaskCompleted(rhs, mode: .today)
                    if lhsCompleted != rhsCompleted { return !lhsCompleted }
                    return todayOccurrenceDate(for: lhs) < todayOccurrenceDate(for: rhs)
                }
            )
        }
        .sorted { lhs, rhs in
            (firstSeenOrder[lhs.title] ?? Int.max) < (firstSeenOrder[rhs.title] ?? Int.max)
        }
    }

    private var missedTodos: [TaskItem] {
        cachedTasks
            .filter { task in
                guard !task.isDeleted else { return false }

                // Missed section should only include non-recurring non-expense todos.
                guard !task.isRecurring else { return false }
                guard task.parentRecurringTaskId == nil else { return false }
                guard !isRecurringExpenseTask(task) else { return false }
                guard !task.isCompletedOn(date: completionDate(for: task, mode: .missed)) else { return false }

                return dueDate(for: task) < dayStart && !dismissedMissedTodoIds.contains(task.id)
            }
            .sorted { dueDate(for: $0) > dueDate(for: $1) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if expandedSection != nil {
                Divider()
                    .overlay(colorScheme == .dark ? Color.white.opacity(0.13) : Color.black.opacity(0.1))

                expandedPanelContent
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: ShadcnRadius.xl)
                .fill(Color.shadcnTileBackground(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: ShadcnRadius.xl)
                .stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(
            color: colorScheme == .dark ? .black.opacity(0.18) : Color.black.opacity(0.08),
            radius: colorScheme == .dark ? 4 : 10,
            x: 0,
            y: colorScheme == .dark ? 2 : 4
        )
        .onAppear {
            refreshCardData()
            loadQuickNotes()
            locationService.requestLocationPermission()
            if let location = locationService.currentLocation {
                refreshWeatherIfNeeded(location: location)
            }
            if isExpanded && expandedSection == nil {
                expandedSection = .date
            }
        }
        .onReceive(taskManager.$tasks) { _ in
            refreshCardData()
        }
        .onChange(of: locationService.currentLocation) { location in
            guard let location else { return }
            refreshWeatherIfNeeded(location: location)
        }
        .onChange(of: isExpanded) { expanded in
            if expanded {
                if expandedSection == nil {
                    expandedSection = .date
                }
            } else {
                expandedSection = nil
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today")
                        .font(FontManager.geist(size: 12, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.62))
                        .textCase(.uppercase)
                        .tracking(0.5)

                    Text(formattedDate)
                        .font(FontManager.geist(size: 20, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 8)

                quickAddMenuButton
            }

            HStack(spacing: 8) {
                summaryChip(
                    title: "Todo \(todayTodos.count)",
                    isActive: expandedSection == .date,
                    action: {
                        toggleSection(.date)
                        HapticManager.shared.selection()
                    }
                )

                summaryChip(
                    title: weatherChipText,
                    isActive: expandedSection == .weather,
                    action: {
                        toggleSection(.weather)
                        HapticManager.shared.selection()
                    }
                )

                summaryChip(
                    title: "Notes \(quickNoteManager.quickNotes.count)",
                    isActive: expandedSection == .quickNotes,
                    action: {
                        toggleSection(.quickNotes)
                        HapticManager.shared.selection()
                    }
                )
            }
        }
    }

    private func summaryChip(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(FontManager.geist(size: 11, weight: .semibold))
                .foregroundColor(
                    isActive
                    ? (colorScheme == .dark ? .black : .white)
                    : (colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.72))
                )
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(
                            isActive
                            ? (colorScheme == .dark ? Color.white : Color.black)
                            : (colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
        .allowsParentScrolling()
    }

    private var quickAddMenuButton: some View {
        Menu {
            Button(action: {
                HapticManager.shared.selection()
                onAddTask?()
            }) {
                Label("Todo", systemImage: "checklist")
            }

            Button(action: {
                HapticManager.shared.selection()
                onAddTaskFromPhoto?()
            }) {
                Label("Todo Camera", systemImage: "camera.fill")
            }

            Button(action: {
                HapticManager.shared.selection()
                onAddNote?()
            }) {
                Label("New Note", systemImage: "note.text.badge.plus")
            }
        } label: {
            Image(systemName: "plus")
                .font(FontManager.geist(size: 14, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.06))
                )
                .overlay(
                    Circle()
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.13) : Color.black.opacity(0.1), lineWidth: 0.5)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .allowsParentScrolling()
    }

    @ViewBuilder
    private var expandedPanelContent: some View {
        switch expandedSection {
        case .date:
            dateExpandedContent
        case .weather:
            weatherExpandedContent
        case .quickNotes:
            quickNotesExpandedContent
        case .none:
            EmptyView()
        }
    }

    private var dateExpandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Up Next", count: upNextShown.count)
            if upNextShown.isEmpty {
                emptyState("No upcoming events for today")
            } else {
                ForEach(upNextShown, id: \.id) { task in
                    todoRow(task, allowsDismiss: false, mode: .today)
                }
            }

            Divider()
                .overlay(colorScheme == .dark ? Color.white.opacity(0.13) : Color.black.opacity(0.1))

            sectionHeader("All Todos", count: allTodosExcludingUpNext.count)
            if allTodosExcludingUpNext.isEmpty {
                emptyState("No additional todos for today")
            } else {
                ForEach(Array(allTodoGroups.enumerated()), id: \.element.id) { index, group in
                    allTodoGroupHeader(title: group.title, iconName: group.iconName)

                    ForEach(group.tasks, id: \.id) { task in
                        todoRow(task, allowsDismiss: false, mode: .today)
                    }

                    if index < allTodoGroups.count - 1 {
                        Divider()
                            .overlay(colorScheme == .dark ? Color.white.opacity(0.09) : Color.black.opacity(0.07))
                    }
                }
            }

            Divider()
                .overlay(colorScheme == .dark ? Color.white.opacity(0.13) : Color.black.opacity(0.1))

            sectionHeader("Missed Todos", count: missedTodos.count)
            if missedTodos.isEmpty {
                emptyState("No missed todos")
            } else {
                ForEach(missedTodos.prefix(20), id: \.id) { task in
                    todoRow(task, allowsDismiss: true, mode: .missed)
                }
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { _ in
                    isTodoScrollInProgress = true
                }
                .onEnded { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        isTodoScrollInProgress = false
                    }
                }
        )
    }

    private var weatherExpandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let weather = weatherService.weatherData {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(FontManager.geist(size: 11, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.58))

                        Text(weather.locationName.isEmpty ? locationService.locationName : weather.locationName)
                            .font(FontManager.geist(size: 12, weight: .semibold))
                            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.82) : Color.black.opacity(0.82))
                            .lineLimit(1)

                        Spacer(minLength: 8)
                    }

                    HStack(spacing: 8) {
                        weatherMetaChip(
                            iconName: weather.iconName,
                            text: weather.description.capitalized
                        )

                        weatherMetaChip(
                            iconName: "thermometer.medium",
                            text: "Feels \(weather.feelsLike)°"
                        )
                    }
                }

                weatherForecastSectionTitle("Next Hours")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(weather.hourlyForecasts.prefix(8).enumerated()), id: \.offset) { _, hour in
                            hourlyForecastChip(hour)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.horizontal, -16)
                .allowsParentScrolling()

                weatherForecastSectionTitle("Next Days")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(weather.dailyForecasts.prefix(8).enumerated()), id: \.offset) { _, day in
                            dailyForecastChip(day)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.horizontal, -16)
                .allowsParentScrolling()
            } else {
                emptyState(weatherService.isLoading ? "Loading forecast..." : "Weather unavailable")
            }
        }
    }

    private func weatherForecastSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(FontManager.geist(size: 12, weight: .semibold))
            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.62))
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private func weatherMetaChip(iconName: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(FontManager.geist(size: 11, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.7))

            Text(text)
                .font(FontManager.geist(size: 11, weight: .medium))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.7))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
        )
    }

    private func hourlyForecastChip(_ hour: HourlyForecast) -> some View {
        HStack(spacing: 6) {
            Image(systemName: hour.iconName)
                .font(FontManager.geist(size: 12, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.72))

            VStack(alignment: .leading, spacing: 1) {
                Text(hour.hour)
                    .font(FontManager.geist(size: 11, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.58) : Color.black.opacity(0.58))
                    .lineLimit(1)

                Text("\(hour.temperature)°")
                    .font(FontManager.geist(size: 13, weight: .semibold))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
        )
    }

    private func dailyForecastChip(_ day: DailyForecast) -> some View {
        HStack(spacing: 6) {
            Text(day.day)
                .font(FontManager.geist(size: 11, weight: .medium))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.58) : Color.black.opacity(0.58))

            Image(systemName: day.iconName)
                .font(FontManager.geist(size: 12, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.72))

            Text("\(day.temperature)°")
                .font(FontManager.geist(size: 13, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? .white : .black)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            Capsule()
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
        )
    }

    private var quickNotesExpandedContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField(editingQuickNote == nil ? "Add quick note..." : "Update quick note...", text: $quickNoteInput)
                    .font(FontManager.geist(size: 13, weight: .regular))
                    .foregroundColor(colorScheme == .dark ? .white : .black)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .onSubmit {
                        saveQuickNote()
                    }

                Button(action: {
                    saveQuickNote()
                }) {
                    Text(editingQuickNote == nil ? "Add" : "Save")
                        .font(FontManager.geist(size: 12, weight: .semibold))
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                        )
                }
                .buttonStyle(PlainButtonStyle())
                .allowsParentScrolling()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
            )

            if quickNoteManager.quickNotes.isEmpty {
                emptyState("No quick notes yet")
            } else {
                ForEach(quickNoteManager.quickNotes.prefix(8), id: \.id) { note in
                    HStack(spacing: 8) {
                        Button(action: {
                            editingQuickNote = note
                            quickNoteInput = note.content
                            HapticManager.shared.selection()
                        }) {
                            Text(note.content)
                                .font(FontManager.geist(size: 13, weight: .regular))
                                .foregroundColor(colorScheme == .dark ? .white : .black)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .allowsParentScrolling()

                        Button(action: {
                            deleteQuickNote(note)
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(FontManager.geist(size: 15, weight: .medium))
                                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.45) : Color.black.opacity(0.4))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .allowsParentScrolling()
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .onAppear {
            loadQuickNotes()
        }
    }

    private func todoRow(_ task: TaskItem, allowsDismiss: Bool, mode: TodoRowMode) -> some View {
        let isCompleted = isTaskCompleted(task, mode: mode)

        return HStack(spacing: 8) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .font(FontManager.geist(size: 15, weight: .medium))
                .foregroundColor(
                    isCompleted
                    ? (colorScheme == .dark ? Color.white.opacity(0.8) : Color.black.opacity(0.78))
                    : (colorScheme == .dark ? Color.white.opacity(0.45) : Color.black.opacity(0.4))
                )
                .contentShape(Rectangle())
                .scrollSafeTapAction(minimumDragDistance: 3) {
                    guard !isTodoScrollInProgress else { return }
                    HapticManager.shared.selection()
                    taskManager.toggleTaskCompletion(task, forDate: completionDate(for: task, mode: mode))
                }
                .allowsParentScrolling()

            HStack(spacing: 8) {
                Text(timeLabel(for: task, mode: mode))
                    .font(FontManager.geist(size: 12, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.6))
                    .frame(width: 88, alignment: .leading)

                Text(task.title)
                    .font(FontManager.geist(size: 13, weight: .regular))
                    .foregroundColor(
                        isCompleted
                        ? (colorScheme == .dark ? Color.white.opacity(0.55) : Color.black.opacity(0.55))
                        : (colorScheme == .dark ? .white : .black)
                    )
                    .strikethrough(isCompleted, color: colorScheme == .dark ? Color.white.opacity(0.45) : Color.black.opacity(0.4))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer()
            }
            .contentShape(Rectangle())
            .scrollSafeTapAction(minimumDragDistance: 3) {
                guard !isTodoScrollInProgress else { return }
                onTaskSelected?(task)
                HapticManager.shared.cardTap()
            }
            .allowsParentScrolling()

            if allowsDismiss {
                Image(systemName: "xmark.circle.fill")
                    .font(FontManager.geist(size: 15, weight: .medium))
                    .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.45) : Color.black.opacity(0.4))
                    .contentShape(Rectangle())
                    .scrollSafeTapAction(minimumDragDistance: 3) {
                        guard !isTodoScrollInProgress else { return }
                        HapticManager.shared.selection()
                        dismissMissedTodo(task.id)
                    }
                    .allowsParentScrolling()
            }
        }
        .padding(.vertical, 2)
        .simultaneousGesture(
            DragGesture(minimumDistance: 2)
                .onChanged { _ in
                    isTodoScrollInProgress = true
                }
                .onEnded { _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        isTodoScrollInProgress = false
                    }
                }
        )
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(FontManager.geist(size: 12, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.62))
                .textCase(.uppercase)
                .tracking(0.5)

            Text("\(count)")
                .font(FontManager.geist(size: 11, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.6) : Color.black.opacity(0.58))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05))
                )
        }
    }

    private func allTodoGroupHeader(title: String, iconName: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(FontManager.geist(size: 10, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.62) : Color.black.opacity(0.62))

            Text(title)
                .font(FontManager.geist(size: 11, weight: .semibold))
                .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.68) : Color.black.opacity(0.66))
        }
        .padding(.top, 2)
    }

    private func emptyState(_ text: String) -> some View {
        Text(text)
            .font(FontManager.geist(size: 13, weight: .regular))
            .foregroundColor(colorScheme == .dark ? Color.white.opacity(0.55) : Color.black.opacity(0.55))
            .padding(.vertical, 2)
    }

    private func refreshCardData() {
        let allTasks = taskManager.getAllFlattenedTasks()
        let tasksForToday = taskManager.getTasksForDate(dayStart)
        cachedTasks = allTasks
        cachedTodayTasks = tasksForToday
    }

    private func toggleSection(_ section: ExpandedSection) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedSection == section {
                expandedSection = nil
                isExpanded = false
            } else {
                expandedSection = section
                isExpanded = true
            }
        }
    }

    private func loadQuickNotes() {
        Task {
            do {
                try await quickNoteManager.fetchQuickNotes()
            } catch {
                print("❌ QuickNotes fetch failed: \(error)")
            }
        }
    }

    private func saveQuickNote() {
        let trimmed = quickNoteInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let noteToEdit = editingQuickNote
        quickNoteInput = ""
        editingQuickNote = nil

        Task {
            do {
                if let noteToEdit {
                    try await quickNoteManager.updateQuickNote(noteToEdit, content: trimmed)
                } else {
                    try await quickNoteManager.createQuickNote(content: trimmed)
                }
                HapticManager.shared.success()
            } catch {
                print("❌ QuickNotes save failed: \(error)")
            }
        }
    }

    private func deleteQuickNote(_ note: QuickNote) {
        Task {
            do {
                try await quickNoteManager.deleteQuickNote(note)
                if editingQuickNote?.id == note.id {
                    editingQuickNote = nil
                    quickNoteInput = ""
                }
                HapticManager.shared.selection()
            } catch {
                print("❌ QuickNotes delete failed: \(error)")
            }
        }
    }

    private func dismissMissedTodo(_ taskId: String) {
        var ids = dismissedMissedTodoIds
        ids.insert(taskId)
        dismissedMissedTodoIdsString = ids.joined(separator: ",")
    }

    private func refreshWeatherIfNeeded(location: CLLocation) {
        if let lastFetch = lastWeatherFetch,
           Date().timeIntervalSince(lastFetch) < 1800 {
            return
        }

        Task {
            await weatherService.fetchWeather(for: location)
            lastWeatherFetch = Date()
        }
    }

    private func dueDate(for task: TaskItem) -> Date {
        guard let targetDate = task.targetDate else { return task.createdAt }

        guard let scheduledTime = task.scheduledTime else {
            return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: targetDate) ?? targetDate
        }

        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: scheduledTime)
        return Calendar.current.date(
            bySettingHour: components.hour ?? 12,
            minute: components.minute ?? 0,
            second: components.second ?? 0,
            of: targetDate
        ) ?? targetDate
    }

    private func todayOccurrenceDate(for task: TaskItem) -> Date {
        guard let scheduledTime = task.scheduledTime else {
            return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: dayStart) ?? dayStart
        }

        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: scheduledTime)
        return Calendar.current.date(
            bySettingHour: components.hour ?? 12,
            minute: components.minute ?? 0,
            second: components.second ?? 0,
            of: dayStart
        ) ?? dayStart
    }

    private func timeLabel(for task: TaskItem, mode: TodoRowMode) -> String {
        switch mode {
        case .today:
            if task.scheduledTime == nil { return "Today" }
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter.string(from: todayOccurrenceDate(for: task))
        case .missed:
            let due = dueDate(for: task)
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE, MMM d"
            return formatter.string(from: due)
        }
    }

    private func completionDate(for task: TaskItem, mode: TodoRowMode) -> Date {
        switch mode {
        case .today:
            return task.isRecurring ? dayStart : (task.targetDate ?? dayStart)
        case .missed:
            return task.targetDate ?? dueDate(for: task)
        }
    }

    private func isTaskCompleted(_ task: TaskItem, mode: TodoRowMode) -> Bool {
        task.isCompletedOn(date: completionDate(for: task, mode: mode))
    }

    private func isRecurringExpenseTask(_ task: TaskItem) -> Bool {
        if task.id.hasPrefix("recurring_") {
            return true
        }

        if let tagId = task.tagId,
           let tag = tagManager.getTag(by: tagId),
           tag.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "recurring" {
            return true
        }

        if let description = task.description?.lowercased(),
           description.contains("amount:") && description.contains("category:") {
            return true
        }

        return false
    }

    private func allTodoCategoryTitle(for task: TaskItem) -> String {
        let trimmedTagId = task.tagId?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let tagId = trimmedTagId, !tagId.isEmpty {
            if let tagName = tagManager.getTag(by: tagId)?.name.trimmingCharacters(in: .whitespacesAndNewlines),
               !tagName.isEmpty {
                return tagName
            }

            if tagId == "cal_sync" {
                if let calendarTitle = task.calendarTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !calendarTitle.isEmpty {
                    return calendarTitle
                }
                return "Sync"
            }

            return "Uncategorized"
        }

        if task.isFromCalendar || task.calendarEventId != nil || task.id.hasPrefix("cal_") {
            if let calendarTitle = task.calendarTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
               !calendarTitle.isEmpty {
                return calendarTitle
            }

            if let sourceTitle = task.calendarSourceType?.trimmingCharacters(in: .whitespacesAndNewlines),
               !sourceTitle.isEmpty {
                return sourceTitle
            }

            return "Sync"
        }

        return "Personal"
    }

    private func allTodoCategoryIconName(for title: String) -> String {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if normalized.contains("work") {
            return "briefcase"
        }
        if normalized.contains("personal") {
            return "person"
        }
        if normalized.contains("recurring") {
            return "arrow.triangle.2.circlepath"
        }
        if normalized.contains("calendar") || normalized.contains("sync") {
            return "calendar"
        }
        if normalized.contains("expense") || normalized.contains("bill") || normalized.contains("payment") {
            return "creditcard"
        }
        return "tag"
    }
}

struct DailyOverviewWidget_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            DailyOverviewWidget(isExpanded: .constant(true))
                .padding()
            Spacer()
        }
        .background(Color.gray.opacity(0.1))
    }
}
