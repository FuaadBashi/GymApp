import SwiftUI

struct SummaryView: View {
    @Environment(WorkoutStore.self) private var store
    let session: WorkoutSession
    let onDone: () -> Void

    private struct Record: Identifiable {
        let id = UUID()
        let exercise: String
        let kind: String
        let now: Double
        let before: Double
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Workout complete").font(.largeTitle.bold())
                        Text("\(session.dayName) · \(session.startedAt.formatted(.dateTime.weekday(.wide).day().month()))")
                            .foregroundStyle(.secondary)
                    }
                    stats
                    if !records.isEmpty { recordsSection }
                    ForEach(session.exercises) { exerciseCard($0) }
                }
                .padding()
            }
            .background(Color.black)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone).font(.headline)
                }
            }
        }
    }

    // MARK: Figures (rulebook §5, §6)

    private var volume: Double {
        session.exercises.reduce(0) {
            $0 + TrainingMath.volumeKg($1.loggedSets.map(\.asPastSet), loadMode: $1.equipment.loadMode, bodyWeightKg: store.bodyWeightKg)
        }
    }

    /// Last time's sets for the same exercises, so the comparison is like for like.
    private var lastVolume: Double? {
        let parts = session.exercises.compactMap { ex in
            ex.lastTime.map { TrainingMath.volumeKg($0.sets, loadMode: ex.equipment.loadMode, bodyWeightKg: store.bodyWeightKg) }
        }
        return parts.isEmpty ? nil : parts.reduce(0, +)
    }

    private var duration: String {
        let end = session.endedAt ?? .now
        let minutes = Int(end.timeIntervalSince(session.startedAt) / 60)
        return minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
    }

    private var records: [Record] {
        session.exercises.flatMap { ex -> [Record] in
            let before = store.history(for: ex.exerciseId)
                .filter { $0.date < session.startedAt }
                .flatMap(\.sets)
            let prior = TrainingMath.bests(before, loadMode: ex.equipment.loadMode)
            let today = TrainingMath.bests(ex.loggedSets.map(\.asPastSet), loadMode: ex.equipment.loadMode)
            var found: [Record] = []
            if let now = today.heaviestKg, let was = prior.heaviestKg, now > was {
                found.append(Record(exercise: ex.name, kind: "Heaviest", now: now, before: was))
            }
            if let now = today.bestE1RM, let was = prior.bestE1RM, now > was + 0.01 {
                found.append(Record(exercise: ex.name, kind: "Best est. 1RM", now: now, before: was))
            }
            return found
        }
    }

    // MARK: Sections

    private var stats: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            stat("Duration", duration)
            stat("Volume", "\(Load.format(volume.rounded())) kg",
                 detail: lastVolume.map { "last time \(Load.format($0.rounded())) kg" })
            stat("Sets", "\(session.loggedSetCount)")
            stat("Records", "\(records.count)")
        }
    }

    private func stat(_ title: String, _ value: String, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold().monospacedDigit())
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Theme.card, in: .rect(cornerRadius: 14))
    }

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NEW RECORDS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(records) { record in
                HStack {
                    Image(systemName: "trophy.fill").foregroundStyle(Theme.note)
                    VStack(alignment: .leading) {
                        Text(record.exercise).font(.subheadline.weight(.semibold))
                        Text("\(record.kind): \(Load.format(record.now)) kg, was \(Load.format(record.before)) kg")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 14))
    }

    private func exerciseCard(_ ex: ExerciseInWorkout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ex.name).font(.headline)
            ForEach(Array(ex.loggedSets.enumerated()), id: \.element.id) { index, set in
                HStack {
                    Text(set.type == .warmUp ? "W" : "\(index + 1)").frame(width: 24, alignment: .leading)
                    Text("\(set.load.formatted) \(set.load.unit.rawValue) × \(set.reps)")
                    Spacer()
                    if let e1rm = TrainingMath.displayableE1RM(kg: set.load.kg, reps: set.reps, loadMode: ex.equipment.loadMode) {
                        Text("1RM \(Load.format((e1rm * 10).rounded() / 10))").foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline.monospacedDigit())
            }
            if let last = ex.lastTime {
                Text("Last: " + last.sets.map(\.shortText).joined(separator: " · "))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 14))
    }
}
