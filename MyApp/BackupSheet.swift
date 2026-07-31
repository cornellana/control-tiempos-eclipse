/// BackupSheet.swift — Program selection and export sheet.
///
/// Lets the user choose which saved programs to export into a `.cteprog` backup
/// archive and share it via the system share sheet (AirDrop, Files, Mail, etc.).

import SwiftUI
import SwiftData
import UIKit             // UIActivityViewController — no SwiftUI equivalent for local file URLs.

// MARK: - BackupSheet

struct BackupSheet: View {

    @Environment(\.dismiss)          private var dismiss
    @Query(sort: \SavedProgram.name) private var savedPrograms: [SavedProgram]

    @State private var selected:    Set<Int> = []
    @State private var exportError: String?  = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                if savedPrograms.isEmpty {
                    ContentUnavailableView(
                        "No Saved Programs",
                        systemImage: "bookmark.slash",
                        description: Text("Save a program in Step 4 before creating a backup.")
                    )
                } else {
                    programList
                }
            }
            .navigationTitle("Backup Programs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        prepareExport()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .foregroundStyle(selected.isEmpty ? Color.secondary : Color.gold)
                    .disabled(selected.isEmpty)
                }
            }
        }
        .alert("Export Error", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
        .onAppear {
            selected = Set(0..<savedPrograms.count)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Program list

    private var programList: some View {
        List {
            Section {
                ForEach(Array(savedPrograms.enumerated()), id: \.offset) { index, prog in
                    Toggle(isOn: Binding(
                        get: { selected.contains(index) },
                        set: { on in
                            if on { selected.insert(index) }
                            else  { selected.remove(index) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(prog.name)
                                .font(.callout)
                                .foregroundStyle(.white)
                            Text("\(prog.eventCount) events · \(prog.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(Color.gold)
                    .listRowBackground(Color.cardBackground)
                }
            } header: {
                HStack {
                    Text("Select programs to include")
                    Spacer()
                    Button("All")  { selected = Set(0..<savedPrograms.count) }
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

    // MARK: - Export

    private func prepareExport() {
        let programs = selected.sorted().map { savedPrograms[$0] }
        do {
            let url = try BackupService.export(programs: programs)
            presentShareSheet(url: url)
        } catch {
            exportError = error.localizedDescription
        }
    }

    /// Presents `UIActivityViewController` from the topmost UIKit view controller.
    ///
    /// UIKit direct presentation is required because presenting UIActivityViewController
    /// through SwiftUI's `.sheet` system renders a blank gray screen when the caller
    /// is itself inside a sheet (a known SwiftUI/UIKit interaction limitation).
    private func presentShareSheet(url: URL) {
        guard let windowScene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = windowScene.keyWindow else { return }

        let activityVC = UIActivityViewController(
            activityItems: [url as Any],
            applicationActivities: nil
        )

        // iPad requires a source anchor; centre of the screen is safe.
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = window
            popover.sourceRect = CGRect(
                x: window.bounds.midX, y: window.bounds.midY,
                width: 0, height: 0
            )
            popover.permittedArrowDirections = []
        }

        // Walk up the presented-controller chain to find the topmost one.
        var topVC: UIViewController = window.rootViewController!
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        topVC.present(activityVC, animated: true)
    }
}
