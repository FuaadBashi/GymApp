import GRDB
import SwiftUI

struct NewProgramView: View {
    let db: AppDatabase
    let created: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var split = Split.fullBody
    @State private var fullBodyDays = 3
    @State private var name = "Full Body"
    @State private var nameEdited = false
    @State private var makeActive = true
    @State private var lastError: String?

    private static let titles: [Split: String] = [
        .fullBody: "Full Body", .upperLower4: "Upper/Lower · 4 days", .upperLower6: "Upper/Lower · 6 days",
        .pushPullLegs3: "Push/Pull/Legs · 3 days", .pushPullLegs6: "Push/Pull/Legs · 6 days", .custom: "Custom",
    ]
    private static let defaultNames: [Split: String] = [
        .fullBody: "Full Body", .upperLower4: "Upper/Lower", .upperLower6: "Upper/Lower",
        .pushPullLegs3: "Push/Pull/Legs", .pushPullLegs6: "Push/Pull/Legs", .custom: "Custom",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Name", text: $name)
                        .font(.title3.weight(.semibold))
                        .padding(Tokens.Space.m)
                        .background(Theme.card, in: .rect(cornerRadius: Tokens.Radius.row))
                        .onChange(of: name) { if name != Self.defaultNames[split] { nameEdited = true } }
                    Text("SPLIT").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(Split.allCases, id: \.self) { option in
                        Button {
                            split = option
                            if !nameEdited { name = Self.defaultNames[option] ?? "" }
                        } label: {
                            splitCard(option)
                        }
                        .buttonStyle(.plain)
                    }
                    if split == .fullBody {
                        Picker("Days", selection: $fullBodyDays) {
                            Text("2 days").tag(2)
                            Text("3 days").tag(3)
                        }
                        .pickerStyle(.segmented)
                    }
                    Toggle("Make active", isOn: $makeActive).padding(.top, Tokens.Space.xs)
                }
                .padding()
            }
            .background(Theme.background)
            .navigationTitle("New program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .alert("Couldn't create", isPresented: Binding(get: { lastError != nil }, set: { if !$0 { lastError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(lastError ?? "") }
        }
    }

    private func splitCard(_ option: Split) -> some View {
        let selected = option == split
        return VStack(alignment: .leading, spacing: 4) {
            Text(Self.titles[option] ?? "").font(.headline)
            Text(ProgramWrites.template(for: option, fullBodyDays: fullBodyDays).map(\.name).joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Tokens.Space.m)
        .background(Theme.card, in: .rect(cornerRadius: Tokens.Radius.row))
        .overlay(RoundedRectangle(cornerRadius: Tokens.Radius.row).stroke(selected ? Theme.accent : .clear, lineWidth: 2))
    }

    private func create() {
        let (name, split, days, active) = (name, split, fullBodyDays, makeActive)
        Task {
            do {
                let program = try await db.writer.write {
                    try ProgramWrites.createProgram($0, name: name, split: split, fullBodyDays: days, makeActive: active, now: .now)
                }
                dismiss()
                created(program.id)
            } catch {
                lastError = error.localizedDescription
            }
        }
    }
}
