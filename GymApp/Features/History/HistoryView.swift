import SwiftUI

/// Every finished workout, newest first, under a month calendar.
struct HistoryView: View {
    @State private var model: HistoryViewModel
    @Environment(ActiveWorkoutModel.self) private var workout

    init(db: AppDatabase) { _model = State(initialValue: HistoryViewModel(db: db)) }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    Section {
                        MonthCalendar(month: model.month, weekStartsOn: model.settings.weekStartsOn, days: model.monthDays,
                                      color: model.color(for:),
                                      onMonth: { m in Task { await model.showMonth(m) } },
                                      onDay: { day in
                                          let week = HistoryQueries.weekStart(of: day, weekStartsOn: model.settings.weekStartsOn)
                                          withAnimation { proxy.scrollTo(week, anchor: .top) }
                                      })
                        Text(goalLine).font(.subheadline.weight(.semibold))
                    }
                    if model.loaded && model.weeks.isEmpty {
                        ContentUnavailableView("No workouts yet", systemImage: "calendar",
                                               description: Text("Finished workouts appear here."))
                    }
                    ForEach(model.weeks) { week in
                        Section {
                            ForEach(week.workouts) { item in
                                NavigationLink(value: item.workout.id) { WorkoutRow(item: item, dot: model.color(for: item.dayId)) }
                            }
                        } header: {
                            Text(header(week)).textCase(nil)
                        }
                        .id(week.start)
                    }
                }
                .themedList()
                .navigationTitle("History")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink { RecapsView(db: model.db) } label: { Label("Recaps", systemImage: "rectangle.stack") }
                    }
                }
                .navigationDestination(for: String.self) { id in
                    WorkoutDetailView(db: model.db, workoutId: id)
                }
            }
            .countsUsage("screen.history")
            .task { await model.reload() }
            .onAppear { Task { await model.reload() } }
            .onChange(of: workout.justFinishedWorkoutId) { Task { await model.reload() } }
        }
    }

    private var goalLine: String {
        let w = model.thisWeek
        return w.goal.map { "This week: \(w.done) of \($0)" } ?? "This week: \(w.done)"
    }

    private func header(_ week: HistoryWeek) -> String {
        let volume = week.workouts.reduce(0) { $0 + $1.volumeKg }
        let n = week.workouts.count
        return "Week of \(week.start.formatted(.dateTime.day().month(.abbreviated).year())) · \(n) workout\(n == 1 ? "" : "s") · \(Load.format(volume.rounded())) kg"
    }
}

struct WorkoutRow: View {
    let item: WorkoutListItem
    var dot: Color = .gray

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Circle().fill(dot).frame(width: 8, height: 8)
                Text(item.workout.title).font(.headline).lineLimit(1)
                Spacer()
                Text(item.workout.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("\(Self.duration(item.duration)) · \(item.setCount) sets · \(Load.format(item.volumeKg.rounded())) kg")
                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            if !item.exerciseNames.isEmpty {
                Text(item.exerciseNames.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }
}
