import GRDB
import SwiftUI

/// After Finish: what was done, what beat last time, and a note and effort to keep.
struct SummaryView: View {
    let workoutId: String
    let onDone: () -> Void
    @Environment(ActiveWorkoutModel.self) private var model
    @State private var summary: WorkoutSummary?
    @State private var effort: Int?
    @State private var note = ""
    @State private var loaded = false
    @State private var pending: Task<Void, Never>?
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let summary { content(summary) } else { ProgressView().padding(.top, 80) }
            }
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: save) }
            }
        }
        .onChange(of: note) { autosave() }
        .onChange(of: effort) { autosave() }
        .interactiveDismissDisabled(saveError != nil)
        .task {
            let id = workoutId
            summary = try? await model.db.reader.read { try SummaryQueries.summary($0, workoutId: id) }
            effort = summary?.workout.effort
            note = summary?.workout.note ?? ""
            loaded = true
        }
    }

    private func content(_ s: WorkoutSummary) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Workout complete").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                Text(s.workout.title).font(.largeTitle.bold())
                Text(s.workout.startedAt.formatted(date: .complete, time: .shortened)).foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                tile("Duration", Duration.seconds(s.duration).formatted(.time(pattern: s.duration >= 3600 ? .hourMinute : .minuteSecond)))
                tile("Volume", "\(Load.format(s.volumeKg.rounded())) kg",
                     s.previousVolumeKg.map { "last time \(Load.format($0.rounded())) kg" })
                tile("Sets", "\(s.setCount)")
                tile("Records", "\(s.records.count)")
            }

            if !s.records.isEmpty {
                section("Records") {
                    ForEach(s.records) { r in
                        HStack(alignment: .firstTextBaseline) {
                            Image(systemName: "trophy.fill").foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.exercise.name).font(.headline)
                                Text(r.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(Load.format((r.valueKg * 10).rounded() / 10)) kg, was \(Load.format((r.previousKg * 100).rounded() / 100)) kg")
                                .font(.subheadline.monospacedDigit())
                        }
                    }
                }
            }

            if !s.muscles.isEmpty {
                section("Muscles trained") {
                    FlowLayout(spacing: 6) {
                        ForEach(s.muscles, id: \.muscle) { m in
                            Text("\(m.muscle.displayName) \(Load.format(m.sets))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.color(for: m.muscle.region))
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Theme.color(for: m.muscle.region).opacity(0.15), in: Capsule())
                        }
                    }
                }
            }

            section("Exercises") {
                ForEach(s.exercises) { line in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(line.exercise.name).font(.headline)
                        if let note = line.note { Text(note).font(.caption).foregroundStyle(Theme.note) }
                        ForEach(line.sets.filter { !$0.metadataText.isEmpty }) { set in
                            Text("Set \(set.position + 1): " + set.metadataText).font(.caption).foregroundStyle(Theme.note)
                        }
                        Text(SetFormat.line(line.sets, loadMode: line.exercise.loadMode))
                            .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        if let best = line.sets.compactMap({ TrainingMath.displayableE1RM(kg: SetFormat.kg($0), reps: $0.reps, loadMode: line.exercise.loadMode) }).max() {
                            Text("Est. 1RM \(Load.format((best * 10).rounded() / 10)) kg").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let saveError { Text(saveError).font(.caption).foregroundStyle(.orange) }
            section("How did it feel?") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(1...10, id: \.self) { n in
                            Chip(title: "\(n)", isSelected: effort == n) { effort = effort == n ? nil : n }
                        }
                    }
                }
                TextField("Note", text: $note, axis: .vertical)
                    .lineLimit(2...5)
                    .padding(10)
                    .background(Theme.row, in: .rect(cornerRadius: 10))
            }
        }
        .padding(16)
    }

    private func tile(_ title: String, _ value: String, _ caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Text(value).font(.title2.bold().monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
            Text(caption ?? " ").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card, in: .rect(cornerRadius: 16))
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased()).font(.caption.weight(.bold)).foregroundStyle(.secondary)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: .rect(cornerRadius: 16))
    }

    private func autosave() {
        guard loaded else { return }
        let draft = MetadataDraft(kind: .summary, id: workoutId, note: note, effort: effort)
        do { try draft.persist() } catch { saveError = error.localizedDescription; return }
        let previous = pending
        pending = Task {
            await previous?.value
            do {
                try await model.db.writer.write { try draft.apply($0) }
                try draft.clearIfCurrent()
                saveError = nil
            } catch { saveError = "Note kept as a recovery draft: " + error.localizedDescription }
        }
    }
    private func save() {
        autosave()
        Task { await pending?.value; if saveError == nil { onDone() } }
    }
}

/// Wraps chips onto as many lines as they need.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += line + spacing; line = 0 }
            x += size.width + spacing
            line = max(line, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += line + spacing; line = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
