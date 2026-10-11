import SwiftUI

struct ActiveWorkoutView: View {
    @Environment(WorkoutStore.self) private var store
    let onClose: () -> Void

    @State private var confirmEnd = false
    @State private var showingList = false
    @State private var restEndedTick = 0

    var body: some View {
        if let session = store.active {
            workout(session)
        } else if let finished = store.justFinished {
            SummaryView(session: finished) {
                store.justFinished = nil
                onClose()
            }
        } else {
            Color.black.onAppear(perform: onClose)
        }
    }

    private func workout(_ session: WorkoutSession) -> some View {
        VStack(spacing: 0) {
            header(session)
            segments(session)
            TabView(selection: Binding(
                get: { session.currentExercise },
                set: { store.select(exercise: $0) }
            )) {
                ForEach(session.exercises.indices, id: \.self) { index in
                    ExercisePage(exerciseIndex: index).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            bottomBar(session)
        }
        .background(Color.black)
        .task(id: session.restEndsAt) { await waitForRestEnd(session.restEndsAt) }
        .sensoryFeedback(.success, trigger: session.loggedSetCount)
        .sensoryFeedback(.warning, trigger: restEndedTick)
        .confirmationDialog(
            "\(session.loggedSetCount) sets logged",
            isPresented: $confirmEnd,
            titleVisibility: .visible
        ) {
            if session.loggedSetCount > 0 {
                Button("Finish and save") { store.finish() }
            }
            Button("Discard workout", role: .destructive) { store.discard() }
            Button("Keep training", role: .cancel) {}
        } message: {
            Text("Rows you haven't ticked are dropped.")
        }
        .sheet(isPresented: $showingList) {
            ExerciseList(session: session) { index in
                store.select(exercise: index)
                showingList = false
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func header(_ session: WorkoutSession) -> some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "chevron.down").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Minimise workout")
            VStack(alignment: .leading, spacing: 2) {
                Text(session.dayName).font(.headline)
                Text(session.startedAt, style: .timer)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { showingList = true } label: {
                Image(systemName: "list.bullet").font(.title3).frame(width: 44, height: 44)
            }
            .accessibilityLabel("All exercises")
            Button("Finish") { confirmEnd = true }
                .font(.headline)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func segments(_ session: WorkoutSession) -> some View {
        HStack(spacing: 4) {
            ForEach(session.exercises.indices, id: \.self) { index in
                let exercise = session.exercises[index]
                Capsule()
                    .fill(segmentColor(exercise, current: index == session.currentExercise))
                    .frame(height: index == session.currentExercise ? 6 : 4)
                    .frame(maxWidth: .infinity, minHeight: 24)
                    .contentShape(.rect)
                    .onTapGesture { withAnimation { store.select(exercise: index) } }
            }
        }
        .padding(.horizontal)
    }

    private func segmentColor(_ exercise: ExerciseInWorkout, current: Bool) -> Color {
        if current { return .accentColor }
        if exercise.isComplete { return Theme.logged.opacity(0.8) }
        if !exercise.loggedSets.isEmpty { return Theme.logged.opacity(0.35) }
        return Color(white: 0.25)
    }

    @ViewBuilder
    private func bottomBar(_ session: WorkoutSession) -> some View {
        let e = session.currentExercise
        let exercise = session.exercises[e]
        VStack(spacing: 0) {
            if let ends = session.restEndsAt {
                RestBar(endsAt: ends, duration: session.restDuration) { store.adjustRest(by: $0) }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Group {
                if session.restEndsAt != nil {
                    Button { store.skipRest() } label: {
                        Text("Skip rest").font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else if let target = targetSet(exercise) {
                    let set = exercise.sets[target]
                    Button { withAnimation { store.logSelected(exercise: e) } } label: {
                        Text("Log set \(target + 1) · \(set.load.formatted) × \(set.reps)")
                            .font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else if e + 1 < session.exercises.count {
                    Button { withAnimation { store.select(exercise: e + 1) } } label: {
                        Text("Next: \(session.exercises[e + 1].name)").font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button { confirmEnd = true } label: {
                        Text("Finish workout").font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.logged)
                }
            }
            .controlSize(.large)
            .padding()
        }
        .animation(.snappy, value: session.restEndsAt)
    }

    /// The row "Log set" acts on: the selected row if it is still open, else the next open one.
    private func targetSet(_ exercise: ExerciseInWorkout) -> Int? {
        if exercise.sets.indices.contains(exercise.selected), !exercise.sets[exercise.selected].isLogged {
            return exercise.selected
        }
        return exercise.nextUnlogged
    }

    private func waitForRestEnd(_ end: Date?) async {
        guard let end else { return }
        let wait = end.timeIntervalSinceNow
        if wait > 0 {
            try? await Task.sleep(for: .seconds(wait))
            if Task.isCancelled { return }
        }
        restEndedTick += 1
        store.restFinished()
    }
}

private struct ExerciseList: View {
    let session: WorkoutSession
    let select: (Int) -> Void

    var body: some View {
        NavigationStack {
            List(session.exercises.indices, id: \.self) { index in
                let exercise = session.exercises[index]
                Button { select(index) } label: {
                    HStack {
                        Image(systemName: exercise.isComplete ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(exercise.isComplete ? Theme.logged : Color.secondary)
                        Text(exercise.name).foregroundStyle(.primary)
                        Spacer()
                        Text("\(exercise.loggedSets.count)/\(exercise.sets.count)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowBackground(index == session.currentExercise ? Theme.row : Theme.card)
            }
            .navigationTitle(session.dayName)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
