/// TourOverlay.swift
/// Long-press tour card: hold any annotated button 0.5 s to reveal its description.
///
/// Three components work together:
///   - `TourOverlayState` — shared observable holding the currently visible `TourStep`.
///   - `TourCardModifier` — attaches a 0.5 s long-press gesture to any view.
///   - `TourCardPopup`    — the floating card rendered above all app content.
///
/// Setup in `RootView` (once):
///   1. `@State private var tourOverlay = TourOverlayState()`
///   2. `.environment(tourOverlay)` on the root `ZStack`.
///   3. Conditionally render `TourCardPopup` at the top of the root `ZStack`.
///
/// Usage on any button:
///   ```swift
///   Button { doSomething() } label: { Text("Continue") }
///       .tourCard(TourContent.steps[6])
///   ```

import SwiftUI

// MARK: - TourOverlayState

/// Shared observable that controls which tutorial card (if any) is displayed.
///
/// Declare once in `RootView` as `@State private var tourOverlay = TourOverlayState()`
/// and inject into the environment with `.environment(tourOverlay)`.
@Observable final class TourOverlayState {
    /// The step whose description card is currently visible, or `nil` when none is shown.
    var activeStep: TourStep? = nil
}

// MARK: - TourCardModifier

/// Adds a 0.5-second long-press gesture that shows a tour description card.
///
/// Uses `highPriorityGesture` so the long press takes precedence over the button's
/// built-in tap recogniser:
///
///   - Quick tap  → long press fails (duration not reached); button action fires normally.
///   - 0.5 s hold → long press wins; button tap is cancelled; tour card is shown.
private struct TourCardModifier: ViewModifier {

    let step: TourStep
    @Environment(TourOverlayState.self) private var tourOverlay

    func body(content: Content) -> some View {
        content
            .highPriorityGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .onEnded { _ in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            tourOverlay.activeStep = step
                        }
                    }
            )
    }
}

// MARK: - View extension

extension View {
    /// Attaches a long-press tour card to this view.
    ///
    /// Holding the view for 0.5 seconds shows `step`'s description card above all
    /// content. A normal tap is completely unaffected.
    ///
    /// - Parameter step: The `TourStep` whose card to display on long press.
    /// - Returns: The modified view with the gesture attached.
    func tourCard(_ step: TourStep) -> some View {
        modifier(TourCardModifier(step: step))
    }
}

// MARK: - TourCardPopup

/// Full-screen dimmed overlay showing a single tour step card.
///
/// Tapping the dimmed area outside the card calls `onDismiss`. The card itself
/// absorbs taps to prevent accidental dismissal.
/// Must be rendered inside the root `ZStack` to appear above all navigation content.
struct TourCardPopup: View {

    let step: TourStep
    /// Called when the user taps outside the card to dismiss it.
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Dimmed background — tap anywhere outside the card to dismiss.
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // Card — same visual language as GuidedTourView.cardView.
            VStack(spacing: 26) {
                Image(systemName: step.icon)
                    .font(.system(size: 64))
                    .foregroundStyle(Color.gold)
                    .frame(height: 76)

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
            .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 28)
            // Absorb taps on the card to prevent accidental background-tap dismissal.
            .contentShape(RoundedRectangle(cornerRadius: 20))
            .onTapGesture { }
        }
    }
}
