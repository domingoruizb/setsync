import SwiftData
import SwiftUI

/// Weekly strength dashboard — replaces the old daily HealthKit
/// steps/calories summary and single-session banner (Task 3.4/6.3)
/// entirely: HealthKit access never reliably worked on this project's
/// actual sideloading path (see `TCXExportService.swift`'s doc comment),
/// and a week-at-a-glance view is more useful for a strength-training log
/// than a daily step count ever was.
///
/// A horizontally paged Monday-Sunday week selector (`weekOffset`, 0 =
/// current week, increasing = further into the past) drives both the
/// selected day's session list and the muscle-activation map, which
/// aggregates the *entire visible week*, not just the selected day.
struct TodayView: View {
    @Query(sort: \WorkoutSession.startDate, order: .reverse)
    private var sessions: [WorkoutSession]

    @State private var weekOffset = 0
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())

    private static let weekdayInitials = ["L", "M", "X", "J", "V", "S", "D"]
    // Two years back is effectively "unlimited" for a personal log and
    // keeps the pager a plain, finite ForEach rather than needing a
    // dynamically-growing/infinite page source.
    private static let maxWeeksBack = 104

    // A fixed Monday-first calendar, independent of the device's own
    // locale/region setting — this task asks for Monday-Sunday weeks
    // unconditionally ("L, M, X, J, V, S, D"), not whatever the user's
    // locale happens to consider the first day of the week.
    private static let mondayFirstCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday
        return calendar
    }()

    private func weekStart(forOffset offset: Int) -> Date {
        let calendar = Self.mondayFirstCalendar
        let currentWeekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? Date()
        return calendar.date(byAdding: .weekOfYear, value: -offset, to: currentWeekStart) ?? currentWeekStart
    }

    private func days(forWeekStart start: Date) -> [Date] {
        (0..<7).compactMap { Self.mondayFirstCalendar.date(byAdding: .day, value: $0, to: start) }
    }

    private var selectedDaySessions: [WorkoutSession] {
        sessions
            .filter { Calendar.current.isDate($0.startDate, inSameDayAs: selectedDate) }
            .sorted { $0.startDate < $1.startDate }
    }

    // The muscle map aggregates every set from every session whose
    // startDate falls within the visible week (Monday 00:00 through the
    // following Monday 00:00), regardless of which single day is selected.
    private var visibleWeekSets: [WorkoutSet] {
        let start = weekStart(forOffset: weekOffset)
        let end = Self.mondayFirstCalendar.date(byAdding: .day, value: 7, to: start) ?? start
        return sessions
            .filter { $0.startDate >= start && $0.startDate < end }
            .flatMap { $0.sets }
    }

    private var weeklyMuscleScores: [MuscleGroup: Double] {
        AnatomicalBodyView.muscleScores(from: visibleWeekSets)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    weekPager
                }

                Section(dayContentTitle) {
                    dayContent
                }

                Section("Activación Muscular (semana)") {
                    AnatomicalBodyView(scores: weeklyMuscleScores)
                }
            }
            .navigationTitle("SetSync")
            .onChange(of: weekOffset) { _, newOffset in
                // "seleccionar el día de hoy si es la semana actual, o el
                // lunes si se navega a una semana pasada."
                selectedDate = newOffset == 0
                    ? Calendar.current.startOfDay(for: Date())
                    : weekStart(forOffset: newOffset)
            }
        }
    }

    // MARK: - Week pager

    private var weekPager: some View {
        TabView(selection: $weekOffset) {
            ForEach(0...Self.maxWeeksBack, id: \.self) { offset in
                weekRow(forOffset: offset)
                    .tag(offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: 76)
        .listRowInsets(EdgeInsets())
    }

    private func weekRow(forOffset offset: Int) -> some View {
        let days = days(forWeekStart: weekStart(forOffset: offset))
        return HStack(spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                dayCell(day, initial: Self.weekdayInitials[index])
            }
        }
        .padding(.horizontal, 8)
    }

    private func dayCell(_ day: Date, initial: String) -> some View {
        let calendar = Calendar.current
        let isToday = calendar.isDateInToday(day)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        // "Días con entrenamiento": only *finished* sessions count toward
        // the completion dot — an in-progress session still shows up in
        // the day's own session list below, just without marking the
        // calendar cell as done yet.
        let hasCompletedWorkout = sessions.contains {
            $0.status == .completed && calendar.isDate($0.startDate, inSameDayAs: day)
        }
        let dayNumber = calendar.component(.day, from: day)

        return Button {
            selectedDate = day
        } label: {
            VStack(spacing: 4) {
                Text(initial)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("\(dayNumber)")
                    .font(.subheadline)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(isSelected ? Color.accentColor : Color.clear))
                    .overlay(
                        Circle().stroke(isToday && !isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
                    )

                Circle()
                    .fill(hasCompletedWorkout ? Color.accentColor : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Selected day's session list

    private var dayContentTitle: String {
        Calendar.current.isDateInToday(selectedDate)
            ? "Hoy"
            : selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    @ViewBuilder
    private var dayContent: some View {
        if selectedDaySessions.isEmpty {
            Text("Sin entrenamientos este día")
                .foregroundStyle(.secondary)
        } else {
            ForEach(selectedDaySessions) { session in
                NavigationLink {
                    // An in-progress session (today's, almost always)
                    // still needs ActiveWorkoutView specifically — it's
                    // the only place with the manual "Finalizar
                    // Entrenamiento" button (the field-tested fallback for
                    // when the watch's own SESSION_EVENT: STOP never
                    // arrives) and the live exercise-assignment/"Copy
                    // Down" flow. This was previously reachable from this
                    // tab's own dedicated "Sesión Activa" banner, which
                    // this weekly redesign replaced — routing by status
                    // here keeps that capability reachable at all, rather
                    // than sending every session through the
                    // review-only SessionDetailView regardless of state.
                    if session.status == .inProgress {
                        ActiveWorkoutView(session: session)
                    } else {
                        SessionDetailView(session: session)
                    }
                } label: {
                    sessionCard(session)
                }
            }
        }
    }

    private func sessionCard(_ session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(session.startDate.formatted(date: .omitted, time: .shortened))
                    .font(.headline)
                Spacer()
                if session.status == .inProgress {
                    Text("En curso")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if let endDate = session.endDate {
                    Text(formattedDuration(endDate.timeIntervalSince(session.startDate)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Label("\(session.sets.count) series", systemImage: "list.bullet")
                Spacer()
                Label("\(Int(totalVolumeKg(for: session))) kg", systemImage: "scalemass")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func totalVolumeKg(for session: WorkoutSession) -> Double {
        session.sets.reduce(0.0) { $0 + Double($1.reps) * $1.weightKg }
    }

    private func formattedDuration(_ interval: TimeInterval) -> String {
        let totalMinutes = Int(interval) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
    }
}
