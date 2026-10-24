import SwiftUI

enum TrainRoute: Hashable {
    case programs
    case program(String)
    case day(String)
}

struct TrainView: View {
    @Environment(ActiveWorkoutModel.self) private var workout
    @State private var model: TrainViewModel
    @State private var path: [TrainRoute] = []
    @State private var creating = false
    @State private var inbox = StudioInbox.shared
    @State private var showingSuggestions = false

    init(db: AppDatabase) { _model = State(initialValue: TrainViewModel(db: db)) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SigningExpiryBanner()
                    if !inbox.pending.isEmpty {
                        StudioSuggestionsCard(count: inbox.pending.count) { showingSuggestions = true }
                    }
                    SyncStatusLine(db: model.db)
                    if let program = model.program {
                        Text(program.name.uppercased())
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        if let next = model.next {
                            NextUpCard(card: next) { path.append(.day(next.id)) }
                        }
                        if !model.others.isEmpty {
                            Text("OTHER DAYS").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, Tokens.Space.s)
                            ForEach(model.others) { card in
                                Button { path.append(.day(card.id)) } label: { CompactDayCard(card: card) }
                                    .buttonStyle(.plain)
                            }
                        }
                    } else if model.loaded {
                        ContentUnavailableView {
                            Label("No program yet", systemImage: "list.bullet.rectangle")
                        } description: {
                            Text("Pick a split and the app sets up its days.")
                        } actions: {
                            Button("New program") { creating = true }.buttonStyle(.borderedProminent)
                        }
                        .padding(.top, Tokens.Space.emptyTop)
                    }
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("Train")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Programs") { path.append(.programs) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Empty workout", systemImage: "bolt") {
                            Task { try? await workout.start(dayId: nil) }
                        }
                        .disabled(workout.isActive)
                        Button("New program", systemImage: "list.bullet.rectangle") { creating = true }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New")
                }
            }
            .navigationDestination(for: TrainRoute.self) { route in
                switch route {
                case .programs: ProgramsListView(db: model.db, path: $path)
                case .program(let id): ProgramDetailView(db: model.db, programId: id, path: $path)
                case .day(let id): DayEditorView(db: model.db, dayId: id)
                }
            }
            .sheet(isPresented: $creating) {
                NewProgramView(db: model.db) { id in
                    Task { await model.reload() }
                    path.append(.program(id))
                }
            }
            .sheet(isPresented: $showingSuggestions) {
                StudioSuggestionsSheet(db: model.db) { Task { await model.reload() } }
            }
            .refreshable {
                await inbox.reload(model.db)
                await model.reload()
            }
            .countsUsage("screen.train")
            .task { await model.reload() }
            .onAppear { Task { await model.reload() } }
            .onChange(of: workout.isActive) { Task { await model.reload() } }
        }
    }
}

private struct NextUpCard: View {
    let card: DayCardData
    let open: () -> Void
    @Environment(ActiveWorkoutModel.self) private var workout
    @Environment(\.appDatabase) private var db

    private func row(_ item: DayItem) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(item.exercise.name).lineLimit(1)
            Spacer(minLength: 12)
            Text(card.lastTime[item.id] ?? "new").monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .font(.subheadline)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Next up").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                    }
                    Text(card.detail.day.name).font(.title2.bold())
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            if let db {
                // Redesign R.3: each lift opens its page in the plan.
                VStack(spacing: 0) {
                    ForEach(card.detail.items) { item in
                        NavigationLink {
                            ExerciseDetailView(db: db, exerciseId: item.exercise.id, plan: (item.dayExercise, card.detail.day.name))
                        } label: {
                            row(item).frame(minHeight: 44).contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let active = workout.snapshot?.workout {
                Button("Resume \(active.title)") { workout.isPresented = true }
                    .buttonStyle(PrimaryButtonStyle())
            } else {
                Button("Start \(card.detail.day.name)") {
                    Task { try? await workout.start(dayId: card.id) }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding()
        .background(Theme.card, in: .rect(cornerRadius: Tokens.Radius.card))
    }

    private var subtitle: String {
        let last = card.lastDone.map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? "never"
        return "\(card.detail.items.count) exercises · est. \(ProgramQueries.estimatedMinutes(for: card.detail)) min · last \(last)"
    }
}

private struct CompactDayCard: View {
    let card: DayCardData

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.detail.day.name).font(.headline)
                Text("\(card.detail.items.count) exercises · last \(card.lastDone.map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? "never")")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.secondary)
        }
        .padding()
        .background(Theme.card, in: .rect(cornerRadius: Tokens.Radius.card))
        .contentShape(.rect)
    }
}

/// Decision #3: two days before the free signing lapses, and after.
private struct SigningExpiryBanner: View {
    private let expiry = SigningExpiry.current()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            switch SigningExpiry.state(expiry: expiry, now: context.date) {
            case .fine:
                EmptyView()
            case .expiringSoon(let date):
                banner("This install expires \(date.formatted(.dateTime.weekday(.wide).hour().minute())). Reinstall from Xcode to keep training without interruption.",
                       color: Theme.warning)
            case .expired:
                banner("This install has expired. Reinstall from Xcode; your data is kept.", color: Theme.danger)
            }
        }
    }

    private func banner(_ text: String, color: Color) -> some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline)
            .foregroundStyle(color)
            .padding(Tokens.Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.15), in: .rect(cornerRadius: Tokens.Radius.row))
    }
}
