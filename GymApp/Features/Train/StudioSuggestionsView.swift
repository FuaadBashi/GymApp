import SwiftUI

/// Card 6.3: "Studio suggestions (n)" on Train.
struct StudioSuggestionsCard: View {
    let count: Int
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack {
                Image(systemName: "wand.and.stars").foregroundStyle(Theme.accent)
                Text("Studio suggestions (\(count))").font(.headline)
                Spacer()
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Theme.card, in: .rect(cornerRadius: 16))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

struct StudioSuggestionsSheet: View {
    let db: AppDatabase
    var onDecided: () -> Void = {}
    @State private var inbox = StudioInbox.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if inbox.pending.isEmpty {
                    Text("Nothing waiting. New suggestions appear when the studio publishes them to your backup folder.")
                        .foregroundStyle(.secondary)
                }
                ForEach(inbox.pending) { s in
                    NavigationLink {
                        StudioSuggestionDetail(suggestion: s, db: db, onDecided: onDecided)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(s.title).font(.headline)
                            Text(s.detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                            Text("\(s.kind.label) · \(s.created.formatted(.dateTime.day().month(.abbreviated)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .themedList()
            .navigationTitle("Studio suggestions")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await inbox.reload(db) }
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

private struct StudioSuggestionDetail: View {
    let suggestion: StudioSuggestion
    let db: AppDatabase
    let onDecided: () -> Void
    @State private var error: String?
    @State private var working = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                Text(suggestion.title).font(.headline)
                Text(suggestion.detail)
            }
            Section("Why") {
                Text(suggestion.reason)
                LabeledContent("Rule", value: suggestion.rule)
            }
            Section {
                Text(effect).font(.footnote).foregroundStyle(.secondary)
                Button("Accept", systemImage: "checkmark") { decide(accept: true) }.disabled(working)
                Button("Dismiss", systemImage: "xmark", role: .destructive) { decide(accept: false) }.disabled(working)
            } footer: {
                if let error { Text(error).foregroundStyle(Theme.danger) }
            }
        }
        .themedList()
        .navigationTitle(suggestion.kind.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var effect: String {
        switch suggestion.kind {
        case .target: "Accepting shows this target above the exercise's sets in your next workout, with a button to fill them."
        case .swap: "Accepting replaces the exercise in that program day. Past workouts are unchanged."
        case .note: "Accepting marks it as read. Nothing else changes."
        case .fix: "Accepting corrects that one logged set. Nothing is deleted, and records update to match."
        }
    }

    private func decide(accept: Bool) {
        working = true
        Task {
            defer { working = false }
            do {
                if accept { try await StudioInbox.shared.accept(suggestion, db: db) } else { try await StudioInbox.shared.dismiss(suggestion, db: db) }
                onDecided()
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

extension StudioSuggestion.Kind {
    var label: String {
        switch self {
        case .target: "Next target"
        case .swap: "Exercise swap"
        case .note: "Note"
        case .fix: "Data fix"
        }
    }
}
