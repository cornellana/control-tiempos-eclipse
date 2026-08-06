/// GuidedTour.swift
/// Full-screen guided tour: one card per interactive control, with Previous / Next / Cancel navigation.
///
/// Entry points:
///   - `WelcomeView` (first launch, after language selection).
///   - `SettingsView` ("View tutorial" button, always available).
///
/// All user-visible strings are `LocalizedStringKey` so they respect the app locale.
/// Step `name` keys reuse existing localized strings where possible; `detail` keys
/// are new and must be present in `Localizable.xcstrings`.

import SwiftUI

// MARK: - TourStep

/// A single card in the guided tour, describing one button or interactive element.
struct TourStep: Identifiable {
    /// Sequential zero-based identifier that also serves as the array index.
    let id: Int
    /// Localised title of the app screen this control belongs to (e.g. "Step 1 — Location").
    let screenTitle: LocalizedStringKey
    /// SF Symbol name matching the actual icon used on the button or control in the app.
    let icon: String
    /// The button's label or control name; reuses existing localized keys where possible.
    let name: LocalizedStringKey
    /// Concise description of what the control does and when to use it.
    let detail: LocalizedStringKey
}

// MARK: - TourContent

/// Complete ordered inventory of all interactive controls across the app's five steps.
///
/// SF Symbols match those used in the actual views. `name` values reuse existing
/// localized strings to avoid duplication; `detail` values are new descriptive keys
/// added to `Localizable.xcstrings`.
enum TourContent {

    // MARK: Steps array

    /// All tour cards in display order, grouped by screen.
    static let steps: [TourStep] = [

        // MARK: Intro — long-press tip
        .init(id:  0,
              screenTitle: "Guided Tour",
              icon: "hand.tap",
              name: "Long-press any button",
              detail: "At any time in the app, press and hold any button for half a second to see a card like this one describing what it does. This works wherever you are — no need to open the tutorial."),

        // MARK: Step 1 — Location
        .init(id:  1,
              screenTitle: "Step 1 — Location",
              icon: "bookmark",
              name: "Saved Locations",
              detail: "Bookmarks the current coordinates under a custom name. Tap the bookmark to save your site and recall it instantly in future sessions."),
        .init(id:  2,
              screenTitle: "Step 1 — Location",
              icon: "gear",
              name: "Settings",
              detail: "Opens language, synthesised voice, speech speed, and data-management options. Changes take effect immediately."),
        .init(id:  3,
              screenTitle: "Step 1 — Location",
              icon: "location.fill",
              name: "Use Current Location",
              detail: "Requests a one-shot GPS fix accurate to ~100 m. The app needs your position to calculate which part of the eclipse path you are on."),
        .init(id:  4,
              screenTitle: "Step 1 — Location",
              icon: "keyboard",
              name: "Manual Coordinates",
              detail: "Type latitude and longitude in decimal degrees (e.g. 41.68294, 0.47930). A comma works as the decimal separator on the Spanish keyboard."),
        .init(id:  6,
              screenTitle: "Step 1 — Location",
              icon: "arrow.right.circle.fill",
              name: "Continue",
              detail: "Saves the coordinate and pre-selects the next visible eclipse at that location. Advances to date selection."),

        // MARK: Step 2 — Date
        .init(id:  7,
              screenTitle: "Step 2 — Date",
              icon: "chevron.left",
              name: "Back",
              detail: "Returns to the location screen. Any coordinate you entered is preserved."),
        .init(id:  8,
              screenTitle: "Step 2 — Date",
              icon: "calendar",
              name: "Date picker",
              detail: "Selects the eclipse or rehearsal date. The app pre-fills the next visible eclipse at your location; change it to any date for a rehearsal."),
        .init(id:  9,
              screenTitle: "Step 2 — Date",
              icon: "clock.fill",
              name: "Today",
              detail: "Sets the date to today, useful when running a full rehearsal without a real eclipse."),
        .init(id: 10,
              screenTitle: "Step 2 — Date",
              icon: "arrow.right.circle.fill",
              name: "Continue",
              detail: "Evaluates the eclipse circumstances for the chosen date and location, then opens the verification map."),

        // MARK: Step 3 — Verification
        .init(id: 11,
              screenTitle: "Step 3 — Verification",
              icon: "chevron.left",
              name: "Back",
              detail: "Returns to date selection."),
        .init(id: 12,
              screenTitle: "Step 3 — Verification",
              icon: "map.fill",
              name: "Verification map",
              detail: "Shows your observation point with a pin. Confirms visually that the coordinates correspond to your actual site."),
        .init(id: 13,
              screenTitle: "Step 3 — Verification",
              icon: "clock",
              name: "Simulation mode — C2 time",
              detail: "Appears when no eclipse is found for the chosen date. Enter an assumed start of totality (C2) to generate a practice timeline with realistic phase intervals."),
        .init(id:  5,
              screenTitle: "Step 3 — Verification",
              icon: "map",
              name: "View on Jubier map",
              detail: "Opens Xavier Jubier's interactive eclipse map for the entered point. Requires internet. Confirm whether your coordinates fall inside the totality band before the event."),
        .init(id: 25,
              screenTitle: "Step 3 — Verification",
              icon: "mountain.2",
              name: "Check the horizon",
              detail: "Opens PeakFinder's panorama from your exact spot, already aimed at the Sun and showing its path across the sky that day. Use it to check that no ridge, building or treeline blocks the eclipse. PeakFinder draws the Sun's path by default but not the Moon's — during an eclipse it is worth switching the Moon on in PeakFinder's own settings. Requires internet."),
        .init(id: 14,
              screenTitle: "Step 3 — Verification",
              icon: "arrow.right.circle.fill",
              name: "Continue",
              detail: "Advances to the announcement programme editor."),

        // MARK: Step 4 — Programme
        .init(id: 15,
              screenTitle: "Step 4 — Programme",
              icon: "chevron.left",
              name: "Back",
              detail: "Returns to the verification map."),
        .init(id: 16,
              screenTitle: "Step 4 — Programme",
              icon: "trash",
              name: "Delete all",
              detail: "Removes every event from the programme after asking for confirmation."),
        .init(id: 17,
              screenTitle: "Step 4 — Programme",
              icon: "bookmark",
              name: "Saved Programs",
              detail: "Saves a named snapshot of the current event list, or loads a previously saved programme replacing the current one."),
        .init(id: 18,
              screenTitle: "Step 4 — Programme",
              icon: "printer",
              name: "Print",
              detail: "Sends the event list to any AirPrint-compatible printer — a useful paper backup during the event."),
        .init(id: 19,
              screenTitle: "Step 4 — Programme",
              icon: "plus",
              name: "Add event",
              detail: "Creates a new timed announcement relative to an eclipse phase (C1, C2, MAX, C3, C4) with an offset in seconds. The app speaks the text at the exact scheduled moment."),
        .init(id: 20,
              screenTitle: "Step 4 — Programme",
              icon: "hand.tap",
              name: "Edit / swipe event",
              detail: "Tap any row to open the event editor and change the phase, offset, or text. Swipe left on a row to reveal the Delete action."),
        .init(id: 21,
              screenTitle: "Step 4 — Programme",
              icon: "play.fill",
              name: "Start Execution",
              detail: "Begins the countdown and voice announcement sequence. The screen stays on and the app speaks each cue at the exact calculated moment."),

        // MARK: Step 5 — Execution
        .init(id: 22,
              screenTitle: "Step 5 — Execution",
              icon: "map",
              name: "Background map",
              detail: "Displays your observation location underneath the execution overlay. Non-interactive during execution so accidental touches do not interfere."),
        .init(id: 23,
              screenTitle: "Step 5 — Execution",
              icon: "list.bullet",
              name: "Announcement list",
              detail: "Shows all scheduled cues in order. Auto-scrolls to keep the next upcoming event centred on screen with its countdown in large digits."),
        .init(id: 24,
              screenTitle: "Step 5 — Execution",
              icon: "stop.fill",
              name: "STOP — hold 3 seconds",
              detail: "Hold for three full seconds until the progress ring completes. Release early and nothing happens. Stopping returns the app to the location screen."),
    ]

    /// Devuelve la ficha con ese `id`.
    ///
    /// Las vistas se anotan con `.tourCard(TourContent.step(6))`, no con un índice
    /// del array: reordenar las fichas —como se hizo al mover la de Jubier del
    /// paso 1 al 3— desplazaría los índices y cada botón acabaría enseñando la
    /// explicación de otro.
    ///
    /// - Parameter id: Identificador estable de la ficha.
    /// - Returns: La ficha correspondiente, o la primera si el id no existe.
    static func step(_ id: Int) -> TourStep {
        steps.first { $0.id == id } ?? steps[0]
    }
}

// MARK: - GuidedTourView

/// Full-screen card-based guided tour.
///
/// Displays one `TourStep` at a time with a gold SF Symbol, localised name, and
/// description. The user navigates with Previous / Next buttons; the last card
/// shows "Done" instead of Next. A cancel (✕) button dismisses at any point.
struct GuidedTourView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var index: Int = 0

    // MARK: - Convenience

    private var step: TourStep { TourContent.steps[index] }
    private var isFirst: Bool  { index == 0 }
    private var isLast: Bool   { index == TourContent.steps.count - 1 }
    private var progress: Double { Double(index + 1) / Double(TourContent.steps.count) }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                progressHeader
                    .padding(.horizontal)
                    .padding(.top, 16)

                Spacer(minLength: 16)

                cardView
                    .padding(.horizontal)
                    .id(index)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .animation(.easeInOut(duration: 0.2), value: index)

                Spacer()

                navigationRow
                    .padding(.horizontal)
                    .padding(.bottom, 36)
            }

            // Cancel — always accessible
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .padding(20)
            }
            .accessibilityLabel(Text("Cancel"))
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Subviews

    /// Screen-group title + gold progress bar + step counter.
    private var progressHeader: some View {
        VStack(spacing: 8) {
            Text(step.screenTitle)
                .font(.caption)
                .fontWeight(.semibold)
                .textCase(.uppercase)
                .foregroundStyle(Color.gold)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Thin progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 4)
                    Capsule()
                        .fill(Color.gold)
                        .frame(width: geo.size.width * progress, height: 4)
                        .animation(.easeInOut(duration: 0.2), value: index)
                }
            }
            .frame(height: 4)

            Text("\(index + 1) / \(TourContent.steps.count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    /// Card showing the SF Symbol, control name, and description for the current step.
    private var cardView: some View {
        VStack(spacing: 28) {
            Image(systemName: step.icon)
                .font(.system(size: 72))
                .foregroundStyle(Color.gold)
                .frame(height: 88)

            VStack(spacing: 14) {
                Text(step.name)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(step.detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 20))
    }

    /// Previous / Next (or Done on the last card) navigation row.
    private var navigationRow: some View {
        HStack(spacing: 16) {
            Button {
                withAnimation { index -= 1 }
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Color.gold)
            .controlSize(.large)
            .disabled(isFirst)

            Button {
                if isLast { dismiss() }
                else { withAnimation { index += 1 } }
            } label: {
                Group {
                    if isLast {
                        Label("Done", systemImage: "checkmark")
                    } else {
                        Label("Next", systemImage: "chevron.right")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.gold)
            .controlSize(.large)
        }
    }
}
