/// FlowViewModel.swift — Central state machine for the five-step app flow.
///
/// Holds all shared state and drives navigation between steps.
/// Inject into the view tree via `.environment(flow)`.

import Foundation
import CoreLocation
import Observation

@Observable final class FlowViewModel {

    // MARK: - Step enum

    /// The five steps of the linear app flow (CLAUDE.md §2).
    enum Step {
        case location, eventDate, verification, program, execution
    }

    // MARK: - Navigation state

    var step: Step = .location

    // MARK: - Step 1 — Location

    /// Geographic coordinate chosen by the observer in Step 1.
    var coordinate: CLLocationCoordinate2D?

    /// Name of the selected saved location, if any. Empty when using GPS or raw manual input.
    var locationName: String = ""

    // MARK: - Step 2 — Date

    /// Event date chosen in Step 2.
    var eventDate: Date = Calendar.current.startOfDay(for: Date())

    // MARK: - Step 3 — Eclipse evaluation

    /// Circumstances computed from Besselian elements. Nil when no eclipse is visible.
    var circumstances: EclipseCircumstances?

    /// `true` when no real eclipse was found and the app operates in simulation mode.
    var isSimulation: Bool = false

    /// Assumed C2 time (start of totality) entered by the user in simulation mode.
    var simulatedC2: Date = Date()

    /// Simulated totality duration in seconds. Easily adjustable for field rehearsal.
    let simulatedTotalityDurationSeconds: Double = 80

    // MARK: - Effective circumstances

    /// Returns real circumstances, or simulated ones when `isSimulation` is true.
    var effectiveCircumstances: EclipseCircumstances? {
        isSimulation ? makeSimulatedCircumstances() : circumstances
    }

    // MARK: - Navigation helpers

    /// Advances to the next step.
    func advance() {
        switch step {
        case .location:      step = .eventDate
        case .eventDate:     step = .verification
        case .verification:  step = .program
        case .program:       step = .execution
        case .execution:     break
        }
    }

    /// Resets the flow to Step 1, clearing all derived state.
    func restart() {
        step          = .location
        coordinate    = nil
        locationName  = ""
        circumstances = nil
        isSimulation  = false
    }

    // MARK: - Eclipse evaluation

    /// Evaluates whether an eclipse is visible at the current coordinate and date.
    /// Sets `circumstances` and `isSimulation`. Call before advancing from Step 2.
    func evaluateEclipse() {
        guard let coord = coordinate else { return }
        circumstances = EclipseEngine.circumstances(
            lat:  coord.latitude,
            lon:  coord.longitude,
            date: eventDate
        )
        isSimulation = (circumstances == nil)
        if isSimulation {
            // Default simulated C2 to event day at 20:00 local time.
            var cal = Calendar.current
            simulatedC2 = cal.date(bySettingHour: 20, minute: 0, second: 0, of: eventDate) ?? eventDate
        }
    }

    // MARK: - Simulation

    /// Builds an `EclipseCircumstances` from the user-entered `simulatedC2`.
    ///
    /// Template (CLAUDE.md §2 — Paso 3):
    ///   C1 = C2 − 60 min, MAX = C2 + 40 s, C3 = C2 + 80 s, C4 = C2 + 60 min.
    private func makeSimulatedCircumstances() -> EclipseCircumstances {
        let c2  = simulatedC2
        let c1  = c2.addingTimeInterval(-3_600)
        let max = c2.addingTimeInterval(40)
        let c3  = c2.addingTimeInterval(simulatedTotalityDurationSeconds)
        let c4  = c2.addingTimeInterval(3_600)
        return EclipseCircumstances(
            kind:                    .simulated,
            contacts:                [.c1: c1, .c2: c2, .max: max, .c3: c3, .c4: c4],
            magnitude:               nil,
            sunAltitudeAtMax:        nil,
            sunAzimuthAtMax:         nil,
            obscuration:             nil,
            totalityDurationSeconds: simulatedTotalityDurationSeconds
        )
    }
}
