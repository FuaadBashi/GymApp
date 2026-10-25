import Foundation

/// Rulebook §16: keeping the habit. Long breaks cost the most strength, and they start as a slow
/// slide, so this watches the slide, with a forgiving "never miss twice" rule instead of a streak.
nonisolated enum BreakGuard {
    struct Status: Equatable {
        var thisWeek: Int
        var goal: Int
        var shortWeeksInRow: Int        // completed weeks below the goal, newest first
        var recentPerWeek: Double       // last 4 completed weeks
        var earlierPerWeek: Double      // the 8 completed weeks before those
        var message: String?
    }

    static func status(workouts: [Date], goal: Int, now: Date, weekStart: (Date) -> Date, calendar: Calendar = .current) -> Status {
        let thisStart = weekStart(now)
        func weekCount(_ back: Int) -> Int {
            let start = calendar.date(byAdding: .weekOfYear, value: -back, to: thisStart) ?? thisStart
            let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
            return workouts.filter { $0 >= start && $0 < end }.count
        }
        let thisWeek = weekCount(0)
        let completed = (1...12).map(weekCount)               // completed[0] = last week
        let everTrained = workouts.contains { $0 < thisStart }
        var short = 0
        for n in completed { if n < goal { short += 1 } else { break } }
        if !everTrained { short = 0 }
        let recent = Double(completed.prefix(4).reduce(0, +)) / 4
        let earlier = Double(completed.suffix(8).reduce(0, +)) / 8
        var message: String?
        if thisWeek >= goal {
            message = nil
        } else if short >= 2 {
            message = "\(short) weeks below your \(goal) a week. Your long breaks started like this. A short session today counts."
        } else if short == 1 {
            message = "Last week was short of \(goal) sessions. Never miss twice: \(goal - thisWeek) this week keeps the run going."
        } else if earlier >= 2, recent <= 0.6 * earlier {
            message = "Fewer sessions lately: \(String(format: "%.1f", recent)) a week, down from \(String(format: "%.1f", earlier)). Catch it early."
        }
        return Status(thisWeek: thisWeek, goal: goal, shortWeeksInRow: short, recentPerWeek: recent,
                      earlierPerWeek: earlier, message: message)
    }

    /// The hour you usually start: the median start hour of the last ten workouts (19 if none).
    static func usualHour(_ starts: [Date], calendar: Calendar = .current) -> Int {
        let hours = starts.suffix(10).map { calendar.component(.hour, from: $0) }.sorted()
        return hours.isEmpty ? 19 : hours[hours.count / 2]
    }

    /// When to nudge: at the usual hour on the day the gap reaches the most days the goal allows
    /// (4 days for 3 a week). Nil before any workout.
    static func nudgeDate(lastWorkout: Date?, goal: Int, usualHour: Int, now: Date, calendar: Calendar = .current) -> Date? {
        guard let lastWorkout else { return nil }
        let gap = Int((7.0 / Double(max(goal, 1))).rounded(.up)) + 1
        let day = calendar.date(byAdding: .day, value: gap, to: calendar.startOfDay(for: lastWorkout)) ?? lastWorkout
        let at = calendar.date(bySettingHour: usualHour, minute: 0, second: 0, of: day) ?? day
        return at > now ? at : nil
    }
}
