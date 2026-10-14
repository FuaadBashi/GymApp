import GRDB
import SwiftUI

/// The workout in progress: a list of exercise cards, or focus mode for the current one.
struct WorkoutView: View {
    @Environment(ActiveWorkoutModel.self) private var model
    @State private var addingExercise = false
    @State private var swapping: WorkoutSnapshot.Item?
    @State private var history: WorkoutSnapshot.Item?
    @State private var plates: WorkoutSnapshot.Item?
    @State private var confirmingDiscard = false
    @State private var confirmingFinish = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if let snapshot = model.snapshot {
                WorkoutHeader(snapshot: snapshot, confirmingFinish: $confirmingFinish,
                              onAdd: { addingExercise = true }, onDiscard: { confirmingDiscard = true })
                if model.focusMode {
                    FocusView(onAction: perform)
                } else {
                    list(snapshot)
                }
                WorkoutBottomBar()
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.background)
        .overlay(alignment: .top) {
            if let banner = model.banner {
                BestBannerView(banner: banner) { model.dismissBanner() }
                    .padding(.horizontal, 16).padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35), value: model.banner)
        .sensoryFeedback(trigger: model.banner) { _, new in
            switch new?.status {
            case .allTime: .success
            case .window: .impact(weight: .light)
            default: nil
            }
        }
        .sheet(isPresented: $addingExercise) {
            WorkoutExercisePicker(title: "Add exercise") { id in Task { await model.addExercise(id) } }
        }
        .sheet(item: $swapping) { item in
            SwapSheet(item: item)
        }
        .sheet(item: $history) { item in
            ExerciseHistorySheet(db: model.db, exerciseId: item.exercise.id)
        }
        .sheet(item: $plates) { item in
            PlateCalculatorView(set: item.sets.first { $0.id == model.selectedSetId } ?? item.sets.first,
                                equipment: item.exercise.equipment)
        }
        .confirmationDialog("Discard this workout?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard workout", role: .destructive) { Task { await model.discard() } }
        } message: {
            Text("Nothing from it is kept.")
        }
        .confirmationDialog("Finish workout?", isPresented: $confirmingFinish, titleVisibility: .visible) {
            Button("Finish") { Task { await model.finish() } }
        } message: {
            Text(finishMessage)
        }
        .alert("Something went wrong", isPresented: Binding(get: { model.lastError != nil }, set: { if !$0 { model.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.lastError ?? "")
        }
    }

    private var finishMessage: String {
        guard let s = model.snapshot else { return "" }
        let planned = s.totalSetCount - s.completedSetCount
        if s.completedSetCount == 0 { return "Nothing is logged, so the workout won't be kept." }
        return planned == 0 ? "Every set is logged." : "\(planned) unlogged set\(planned == 1 ? "" : "s") will be dropped."
    }

    private func perform(_ action: ExerciseCardAction, on item: WorkoutSnapshot.Item) {
        switch action {
        case .swap: swapping = item
        case .history: history = item
        case .plates: plates = item
        }
    }

    private func list(_ snapshot: WorkoutSnapshot) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(snapshot.items) { item in
                        ExerciseCard(item: item, isCurrent: item.id == model.currentItemId) { perform($0, on: item) }
                            .id(item.id)
                    }
                    Button("Add exercise", systemImage: "plus") { addingExercise = true }
                        .buttonStyle(SecondaryButtonStyle())
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: model.currentItemId) { _, id in
                guard let id else { return }
                withAnimation(.snappy) { proxy.scrollTo(id, anchor: .top) }
            }
            .onAppear {
                if let id = model.currentItemId { proxy.scrollTo(id, anchor: .top) }
            }
        }
    }
}

private struct WorkoutHeader: View {
    let snapshot: WorkoutSnapshot
    @Binding var confirmingFinish: Bool
    let onAdd: () -> Void
    let onDiscard: () -> Void
    @Environment(ActiveWorkoutModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 12) {
            Button { model.isPresented = false } label: {
                Image(systemName: "chevron.down").font(.headline).frame(width: 40, height: 40).background(Theme.row, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Minimise")

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.workout.title).font(.headline).lineLimit(1)
                Text(snapshot.workout.startedAt, style: .timer)
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)

            ProgressRing(done: snapshot.completedSetCount, total: snapshot.totalSetCount)

            Button { model.focusMode.toggle() } label: {
                Image(systemName: "scope").font(.headline)
                    .foregroundStyle(model.focusMode ? Theme.onAccent : .primary)
                    .frame(width: 40, height: 40)
                    .background(model.focusMode ? Theme.accent : Theme.row, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.focusMode ? "Show list" : "Focus mode")

            Menu {
                Button("Add exercise", systemImage: "plus", action: onAdd)
                Button("Discard workout", systemImage: "trash", role: .destructive, action: onDiscard)
            } label: {
                Image(systemName: "ellipsis").font(.headline).frame(width: 40, height: 40).background(Theme.row, in: Circle())
            }

            Button("Finish") { confirmingFinish = true }
                .font(.subheadline.bold())
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 14).frame(height: 40)
                .background(Theme.accent, in: Capsule())
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct ProgressRing: View {
    let done: Int
    let total: Int
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().stroke(Theme.row, lineWidth: 4)
            Circle()
                .trim(from: 0, to: total == 0 ? 0 : CGFloat(done) / CGFloat(total))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(done)").font(.caption2.bold().monospacedDigit())
        }
        .frame(width: size, height: size)
        .animation(.snappy, value: done)
        .accessibilityLabel("\(done) of \(total) sets")
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
