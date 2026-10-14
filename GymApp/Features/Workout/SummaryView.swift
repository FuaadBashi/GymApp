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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back to workout", systemImage: "chevron.backward") {
                        Task { await pending?.value; await model.reopen(workoutId) }
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: save) }
            }
            .onAppear { if loaded { Task { await reload() } } }
        }
        .onChange(of: note) { autosave() }
        .onChange(of: effort) { autosave() }
        .interactiveDismissDisabled(saveError != nil)
        .task {
            await reload()
            effort = summary?.workout.effort
            note = summary?.workout.note ?? ""
            loaded = true
        }
    }

    private func reload() async {
        let id = workoutId
        if let fresh = try? await model.db.reader.read({ try SummaryQueries.summary($0, workoutId: id) }) { summary = fresh }
    }

    private func content(_ s: WorkoutSummary) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Workout complete").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                Text(s.workout.title).font(.largeTitle.bold())
                Text(s.workout.startedAt.formatted(date: .complete, time: .shortened)).foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                tile("Duration", Duration.seconds(s.duration).formatted(.time(pattern: s.duration >= 3600 ? .hourMinute : .minuteSecond)),
                     s.previous.map { Self.change(s.duration / 60, $0.duration / 60, unit: " min") })
                tile("Total lifted", "\(Load.format(s.volumeKg.rounded())) kg",
                     s.previous.map { Self.change(s.volumeKg, $0.volumeKg, unit: " kg") })
                tile("Sets", "\(s.setCount)", s.previous.map { Self.change(Double(s.setCount), Double($0.setCount), unit: "") })
                tile("Records", "\(s.records.count)", s.previous.map { "last time \($0.records)" })
            }
            if let p = s.previous {
                Text("Compared with \(p.workout.title), \(p.workout.startedAt.formatted(.dateTime.day().month(.abbreviated)))")
                    .font(.caption).foregroundStyle(.secondary)
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
                    BodyMapView(sets: Dictionary(uniqueKeysWithValues: s.muscles.map { ($0.muscle, $0.sets) })) { sets in
                        sets < 0.5 ? Theme.idle : Theme.accent.opacity(min(1, 0.3 + sets / 6))
                    }
                    .frame(height: 220)
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
                    NavigationLink {
                        WorkoutDetailView(db: model.db, workoutId: workoutId)
                    } label: {
                        exerciseRow(line)
                    }
                    .buttonStyle(.plain)
                }
                Text("Tap an exercise to fix or delete a set.").font(.caption2).foregroundStyle(.secondary)
            }

            if let saveError { Text(saveError).font(.caption).foregroundStyle(Theme.warning) }
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

    private func exerciseRow(_ line: WorkoutSummary.ExerciseLine) -> some View {
        let tint: Color? = line.best.map { $0.color }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(line.exercise.name).font(.headline)
                if let best = line.best { BestBadge(status: best) }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            if let best = line.best {
                Text(best.title).font(.caption.weight(.semibold)).foregroundStyle(best.color)
            }
            Text(SetFormat.line(line.sets, loadMode: line.exercise.loadMode))
                .font(.subheadline.monospacedDigit()).foregroundStyle(.primary.opacity(0.85))
            if let last = line.lastTime {
                Text("Last time: " + SetFormat.line(last, loadMode: line.exercise.loadMode))
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(spacing: 10) {
                if let c = line.e1RMChange { changeChip("e1RM", c, unit: " kg") }
                if let c = line.volumeChange { changeChip("volume", c, unit: " kg") }
            }
            if let note = line.note { Text(note).font(.caption).foregroundStyle(Theme.note) }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((tint ?? .clear).opacity(tint == nil ? 0 : 0.12), in: .rect(cornerRadius: 12))
        .overlay {
            if let tint { RoundedRectangle(cornerRadius: 12).strokeBorder(tint.opacity(0.5), lineWidth: 1) }
        }
        .contentShape(.rect)
    }

    private func changeChip(_ label: String, _ value: Double, unit: String) -> some View {
        let rounded = (value * 10).rounded() / 10
        let color: Color = rounded > 0 ? Theme.accent : rounded < 0 ? Theme.warning : .secondary
        return Text("\(label) \(rounded > 0 ? "+" : "")\(Load.format(rounded))\(unit)")
            .font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(color)
    }

    /// "+12 kg vs last" style captions for the tiles.
    static func change(_ now: Double, _ before: Double, unit: String) -> String {
        let d = ((now - before) * 10).rounded() / 10
        return d == 0 ? "same as last" : "\(d > 0 ? "+" : "")\(Load.format(d.rounded()))\(unit) vs last"
    }

    private func tile(_ title: String, _ value: String, _ caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Text(value).font(Theme.number(.title2, weight: .bold)).rollingNumber(value).lineLimit(1).minimumScaleFactor(0.6)
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
