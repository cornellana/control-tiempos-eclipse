/// RestoreSheet.swift — Program import sheet for .cteprog backup archives.
///
/// Shows the programs contained in a backup, lets the user choose which ones
/// to import, and handles name conflicts with a per-session overwrite toggle.

import SwiftUI
import SwiftData

struct RestoreSheet: View {

    let backup: BackupFile

    @Environment(\.modelContext)     private var modelContext
    @Environment(\.dismiss)          private var dismiss
    @Query(sort: \SavedProgram.name) private var existingPrograms: [SavedProgram]

    @State private var selected:          Set<Int>
    @State private var overwriteConflicts = true

    /// - Parameter backup: Decoded backup file whose programs are shown.
    init(backup: BackupFile) {
        self.backup = backup
        _selected   = State(initialValue: Set(backup.programs.indices))
    }

    // MARK: - Derived

    /// Indices of backup programs whose names collide with an existing saved program.
    private var conflictIndices: Set<Int> {
        Set(backup.programs.indices.filter { i in
            existingPrograms.contains { $0.name == backup.programs[i].name }
        })
    }

    /// Number of programs that will actually be imported after applying conflict rules.
    private var importCount: Int {
        selected.filter { i in
            !conflictIndices.contains(i) || overwriteConflicts
        }.count
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                List {
                    // Overwrite toggle — only shown when at least one conflict exists.
                    if !conflictIndices.isEmpty {
                        Section {
                            Toggle("Overwrite existing programs", isOn: $overwriteConflicts)
                                .tint(Color.gold)
                                .listRowBackground(Color.cardBackground)
                        } footer: {
                            Text("Saved programs with the same name will be replaced. Disable to skip them.")
                        }
                    }

                    // Program list with per-row conflict indicators.
                    Section {
                        ForEach(Array(backup.programs.enumerated()), id: \.offset) { index, prog in
                            programRow(index: index, prog: prog)
                        }
                    } header: {
                        HStack {
                            Text("\(backup.programs.count) program(s) in backup")
                            Spacer()
                            Button("All")  { selected = Set(backup.programs.indices) }
                                .font(.caption.bold()).foregroundStyle(Color.gold)
                            Text("·").foregroundStyle(.tertiary).font(.caption)
                            Button("None") { selected = [] }
                                .font(.caption.bold()).foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Restore Programs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import (\(importCount))") { performImport() }
                        .foregroundStyle(importCount > 0 ? Color.gold : .secondary)
                        .disabled(importCount == 0)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Row builder

    @ViewBuilder
    private func programRow(index: Int, prog: BackupProgram) -> some View {
        let isConflict = conflictIndices.contains(index)
        let isSelected = selected.contains(index)
        let willSkip   = isConflict && !overwriteConflicts

        Button {
            if isSelected { selected.remove(index) }
            else          { selected.insert(index) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.gold : .secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(prog.name)
                        .font(.callout)
                        .foregroundStyle(.white)
                    HStack(spacing: 8) {
                        Text("\(prog.events.count) events")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if isConflict {
                            Label(
                                willSkip ? "Will be skipped" : "Will overwrite",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(willSkip ? Color.gray.opacity(0.5) : Color.orange)
                        }
                    }
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.cardBackground)
        .opacity(willSkip ? 0.4 : 1.0)
    }

    // MARK: - Import

    private func performImport() {
        for index in selected.sorted() {
            let prog       = backup.programs[index]
            let isConflict = conflictIndices.contains(index)

            if isConflict {
                guard overwriteConflicts else { continue }
                if let existing = existingPrograms.first(where: { $0.name == prog.name }) {
                    modelContext.delete(existing)
                }
            }
            modelContext.insert(SavedProgram(from: prog))
        }
        dismiss()
    }
}
