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
    @State private var expanded: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                if let summary { content(summary) } else { ProgressView().padding(.top, Tokens.Space.emptyTop) }
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
        .countsUsage("screen.endOfWorkout")
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

    /// Redesign R.5: the bests and what went up first; detail one tap down; links obvious.
    private func content(_ s: WorkoutSummary) -> some View {
        let up = s.exercises.filter { ($0.e1RMChange ?? 0) > 0.05 }.count
        return VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(s.workout.title) · \(s.workout.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) · workout complete")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(Self.headline(bests: s.records.count, up: up)).font(.largeTitle.bold())
            }

            HStack(alignment: .top) {
                stat(Duration.seconds(s.duration).formatted(.time(pattern: s.duration >= 3600 ? .hourMinute : .minuteSecond)), "duration")
                stat("\(s.setCount)", "sets")
                stat("\(Load.format(s.volumeKg.rounded())) kg",
                     s.previous.map { Self.change(s.volumeKg, $0.volumeKg, unit: " kg") } ?? "volume")
            }

            if !s.records.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Bests").font(.headline).padding(.bottom, Tokens.Space.s)
                    ForEach(s.records) { r in
                        NavigationLink { ExerciseDetailView(db: model.db, exerciseId: r.exercise.id) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: "trophy.fill").foregroundStyle(Theme.accent).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(r.exercise.name).font(.subheadline)
                                    Text("\(r.kind.rawValue) · was \(Load.format((r.previousKg * 10).rounded() / 10)) kg")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(Load.format((r.valueKg * 10).rounded() / 10)) kg").font(Theme.number(.subheadline))
                                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                            }
                            .padding(.vertical, Tokens.Space.s)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Against last time").font(.headline)
                    Spacer()
                    Text("est. 1RM · tap for sets").font(.caption).foregroundStyle(.secondary)
                }
                .padding(.bottom, Tokens.Space.s)
                ForEach(s.exercises) { line in
                    lineRow(line)
                    Divider()
                }
                Text("Bar: today against last time. The share is today against the lift's best before today.")
                    .font(.caption2).foregroundStyle(.secondary).padding(.top, Tokens.Space.s)
            }

            if !s.muscles.isEmpty {
                DisclosureGroup("Muscles worked") {
                    BodyMapView(sets: Dictionary(uniqueKeysWithValues: s.muscles.map { ($0.muscle, $0.sets) })) { sets in
                        sets < 0.5 ? Theme.idle : Theme.accent.opacity(min(1, 0.3 + sets / 6))
                    }
                    .frame(height: 220)
                    FlowLayout(spacing: 6) {
                        ForEach(s.muscles, id: \.muscle) { m in
                            Text("\(m.muscle.displayName) \(Load.format(m.sets))")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.color(for: m.muscle.region))
                                .padding(.horizontal, Tokens.Space.s).padding(.vertical, Tokens.Space.xs)
                                .background(Theme.color(for: m.muscle.region).opacity(0.15), in: Capsule())
                        }
                    }
                }
                .font(.headline).tint(Theme.accent)
            }

            VStack(spacing: 0) {
                NavigationLink { WorkoutDetailView(db: model.db, workoutId: workoutId) } label: {
                    linkRow("Full workout and edit sets")
                }
                Divider()
                if let p = s.previous {
                    NavigationLink { WorkoutDetailView(db: model.db, workoutId: p.workout.id) } label: {
                        linkRow("Last time: \(p.workout.title), \(p.workout.startedAt.formatted(.dateTime.day().month(.abbreviated)))")
                    }
                }
            }
            .buttonStyle(.plain)

            if let saveError { Text(saveError).font(.caption).foregroundStyle(Theme.warning) }
            VStack(alignment: .leading, spacing: 10) {
                Text("How did it feel?").font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(1...10, id: \.self) { n in
                            Chip(title: "\(n)", isSelected: effort == n) { effort = effort == n ? nil : n }
                        }
                    }
                }
                TextField("Note", text: $note, axis: .vertical)
                    .lineLimit(2...5)
                    .padding(Tokens.Space.s)
                    .background(Theme.row, in: .rect(cornerRadius: Tokens.Radius.row))
            }
        }
        .padding(Tokens.Space.l)
    }

    /// "2 bests, 5 lifts up", "5 lifts up", "Matched last time".
    static func headline(bests: Int, up: Int) -> String {
        var parts: [String] = []
        if bests > 0 { parts.append("\(bests) best\(bests == 1 ? "" : "s")") }
        if up > 0 { parts.append("\(up) lift\(up == 1 ? "" : "s") up") }
        return parts.isEmpty ? "Workout logged" : parts.joined(separator: ", ")
    }

    /// "37% of best", or "new best" when today is above every earlier set.
    static func shareOfBest(today: Double?, before: Double?) -> String? {
        guard let today, let before, before > 0 else { return nil }
        return today - before > 0.01 ? "new best" : "\(Int((today / before * 100).rounded()))% of best"
    }

    private func lineRow(_ line: WorkoutSummary.ExerciseLine) -> some View {
        let open = expanded == line.id
        let change = line.e1RMChange
        let colour: Color = (change ?? 0) > 0.05 ? Theme.accent : (change ?? 0) < -0.05 ? Theme.warning : .secondary
        let lastBest = (line.todayBest ?? 0) - (change ?? 0)
        let scale = max(line.todayBest ?? 0, lastBest, 1)
        return VStack(alignment: .leading, spacing: 8) {
            Button { expanded = open ? nil : line.id } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(line.exercise.name).font(.subheadline)
                        if let best = line.best { BestBadge(status: best) }
                        Spacer()
                        Text(change.map { "\($0 >= 0 ? "↑ +" : "↓ −")\(Load.format((abs($0) * 10).rounded() / 10)) kg" } ?? "—")
                            .font(Theme.number(.subheadline)).foregroundStyle(colour)
                    }
                    if change != nil {
                        HStack(spacing: 8) {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Theme.row)
                                    Capsule().fill(Theme.neutral).frame(width: geo.size.width * lastBest / scale)
                                    Capsule().fill(colour).frame(width: geo.size.width * (line.todayBest ?? 0) / scale, height: 3)
                                }
                            }
                            .frame(height: 6)
                            .accessibilityHidden(true)
                            if let share = Self.shareOfBest(today: line.todayBest, before: line.bestBefore) {
                                Text(share).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.vertical, Tokens.Space.s)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(open ? "Hides the sets" : "Shows the sets")
            if open {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today  " + SetFormat.line(line.sets, loadMode: line.exercise.loadMode))
                    if let last = line.lastTime { Text("Last  " + SetFormat.line(last, loadMode: line.exercise.loadMode)).foregroundStyle(.secondary) }
                    HStack(spacing: 10) {
                        if let c = line.e1RMChange { changeChip("est. 1RM", c, unit: " kg") }
                        if let c = line.volumeChange { changeChip("volume", c, unit: " kg") }
                    }
                    if let note = line.note { Text(note).foregroundStyle(Theme.note) }
                    NavigationLink { ExerciseDetailView(db: model.db, exerciseId: line.exercise.id) } label: {
                        Label("Open \(line.exercise.name)", systemImage: "chevron.right")
                            .font(.caption.weight(.semibold)).padding(.horizontal, Tokens.Space.m).frame(minHeight: 36)
                            .background(Theme.row, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, Tokens.Space.xs)
                }
                .font(.caption.monospacedDigit())
                .padding(.bottom, Tokens.Space.s)
            }
        }
    }

    private func stat(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Theme.number(.title3, weight: .bold)).lineLimit(1).minimumScaleFactor(0.6)
            Text(caption).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func linkRow(_ title: String) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .padding(.vertical, Tokens.Space.m)
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
