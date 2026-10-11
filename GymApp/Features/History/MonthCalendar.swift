import SwiftUI

/// A month grid with a dot under each day that has a finished workout.
struct MonthCalendar: View {
    let month: Date
    let weekStartsOn: WeekStart
    let days: [Date: [String?]]
    let color: (String?) -> Color
    let onMonth: (Date) -> Void
    let onDay: (Date) -> Void

    private var calendar: Calendar { HistoryQueries.calendar(weekStartsOn) }

    private var cells: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: month) else { return [] }
        let first = interval.start
        let lead = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: month)?.count ?? 30
        return Array(repeating: nil, count: lead) + (0..<count).map { calendar.date(byAdding: .day, value: $0, to: first) }
    }

    private var symbols: [String] {
        let s = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        return Array(s[shift...] + s[..<shift])
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Button { move(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous month")
                Spacer()
                Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button { move(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Next month")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(symbols.indices, id: \.self) { i in
                    Text(symbols[i]).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day { cell(day) } else { Color.clear.frame(height: 38) }
                }
            }
        }
    }

    private func cell(_ day: Date) -> some View {
        let workouts = days[calendar.startOfDay(for: day)] ?? []
        let today = calendar.isDateInToday(day)
        return Button { if !workouts.isEmpty { onDay(day) } } label: {
            VStack(spacing: 3) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.subheadline.weight(today ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(today ? Theme.accent : (workouts.isEmpty ? .secondary : .primary))
                HStack(spacing: 2) {
                    ForEach(Array(workouts.prefix(3).enumerated()), id: \.offset) { _, dayId in
                        Circle().fill(color(dayId)).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 38)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .abbreviated, time: .omitted) + (workouts.isEmpty ? "" : ", \(workouts.count) workout\(workouts.count == 1 ? "" : "s")"))
    }

    private func move(_ months: Int) {
        if let next = calendar.date(byAdding: .month, value: months, to: month) { onMonth(next) }
    }
}
