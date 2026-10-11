import SwiftUI

enum TrainRoute: Hashable {
    case programs
    case program(String)
    case day(String)
}

struct TrainView: View {
    @State private var model: TrainViewModel
    @State private var path: [TrainRoute] = []
    @State private var creating = false

    init(db: AppDatabase) { _model = State(initialValue: TrainViewModel(db: db)) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let program = model.program {
                        Text(program.name.uppercased())
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        if let next = model.next {
                            NextUpCard(card: next) { path.append(.day(next.id)) }
                        }
                        if !model.others.isEmpty {
                            Text("OTHER DAYS").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 8)
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
                        .padding(.top, 80)
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
                    Button("New program", systemImage: "plus") { creating = true }
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
            .task { await model.reload() }
            .onAppear { Task { await model.reload() } }
        }
    }
}

private struct NextUpCard: View {
    let card: DayCardData
    let open: () -> Void

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
                    VStack(spacing: 9) {
                        ForEach(card.detail.items) { item in
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.exercise.name).lineLimit(1)
                                Spacer(minLength: 12)
                                Text(card.lastTime[item.id] ?? "new").monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                            }
                            .font(.subheadline)
                        }
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Button("Start \(card.detail.day.name)") {}
                .buttonStyle(PrimaryButtonStyle())
                .disabled(true)
            Text("Logging moves here in phase 2. Use Settings → Prototype meanwhile.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .background(Theme.card, in: .rect(cornerRadius: 20))
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
        .background(Theme.card, in: .rect(cornerRadius: 16))
        .contentShape(.rect)
    }
}
