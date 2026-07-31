/// Step5ExecutionView.swift — Step 5: execution screen.
///
/// Full-screen map as background with a translucent overlay containing:
///   - Fixed header: current eclipse phase + countdown to next contact.
///   - Scrollable cue list, auto-scrolling to center the next pending event.
///     The next event shows a large countdown; past events are dimmed.
///   - Fixed footer: stop button with 3-second hold + progress ring.
///
/// Behaviour on entry: idle timer disabled, AVAudioSession .playback + .duckOthers.
/// Behaviour on exit (stop or last cue): session deactivated, idle timer re-enabled.

import SwiftUI
import MapKit
import SwiftData

struct Step5ExecutionView: View {

    @Environment(FlowViewModel.self)  private var flow
    @Environment(AppSettings.self)    private var settings
    @Query(sort: \ProgramEvent.sortIndex) private var events: [ProgramEvent]

    @State private var execVM: ExecutionViewModel? = nil

    /// Radio del encuadre del mapa de fondo, en metros.
    private static let mapSpanMeters: CLLocationDistance = 500

    // Stop-button hold state.
    @State private var holdProgress:  Double = 0
    @State private var holdTimer:     Timer? = nil

    // MARK: - Body

    var body: some View {
        ZStack {
            // Map fills the entire screen. Encuadre fijado de una vez con initialPosition:
            // el mapa es decorativo y no interactivo, así que no necesita binding de cámara.
            Map(initialPosition: initialCameraPosition) {
                if let coord = flow.coordinate {
                    Marker("", coordinate: coord).tint(Color.gold)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Overlaid content respects safe areas.
            if let vm = execVM {
                VStack(spacing: 0) {
                    eclipseHeader(vm: vm)
                    cueList(vm: vm)
                    stopBar
                }

                // Shown while Claude API translates cues before the timer starts.
                if vm.isTranslating {
                    translatingOverlay
                }
            }
        }
        .task {
            guard execVM == nil, let circ = flow.effectiveCircumstances else { return }
            let vm = ExecutionViewModel(
                circumstances:   circ,
                events:          events,
                voiceLanguage:   settings.language.rawValue,
                speechRate:      settings.speechRate,
                voiceIdentifier: settings.selectedVoiceIdentifier(for: settings.language)
            )
            execVM = vm
            // Translate cues whose textLanguage ≠ voiceLanguage before starting the timer.
            await vm.preTranslate(apiKey: settings.claudeApiKey)
            vm.start()
        }
        .onDisappear {
            holdTimer?.invalidate()
            execVM?.stop()
        }
    }

    // MARK: - Translating overlay

    private var translatingOverlay: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 18) {
                ProgressView()
                    .tint(Color.gold)
                    .scaleEffect(1.6)
                Text("Translating announcements…")
                    .font(.callout)
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Camera setup

    /// Encuadre inicial: el punto de observación con un radio de `mapSpanMeters`.
    private var initialCameraPosition: MapCameraPosition {
        guard let coord = flow.coordinate else { return .automatic }
        return .region(MKCoordinateRegion(
            center:             coord,
            latitudinalMeters:  Self.mapSpanMeters,
            longitudinalMeters: Self.mapSpanMeters
        ))
    }

    // MARK: - Header

    private func eclipseHeader(vm: ExecutionViewModel) -> some View {
        VStack(spacing: 6) {
            Text(vm.currentPhaseName.uppercased())
                .font(.caption.bold())
                .foregroundStyle(Color.gold)
                .tracking(1.5)

            if let contactDate  = vm.nextContactDate,
               let contactPhase = vm.nextContactPhase {
                HStack(spacing: 8) {
                    Text(contactPhase.rawValue.uppercased())
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    Text(formatInterval(contactDate.timeIntervalSince(vm.now)))
                        .font(.title3.monospacedDigit().bold())
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal)
        .background(.ultraThinMaterial)
    }

    // MARK: - Cue list

    private func cueList(vm: ExecutionViewModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 8) {
                    // Top padding so the first cue can be centred.
                    Color.clear.frame(height: 48)

                    if vm.allCues.isEmpty {
                        emptyProgramView
                    } else {
                        let nextID = vm.nextPendingCue?.id
                        ForEach(vm.allCues) { cue in
                            cueRow(cue: cue, isNext: cue.id == nextID, now: vm.now, vm: vm)
                                .id(cue.id)
                        }
                    }

                    Color.clear.frame(height: 48)
                }
                .padding(.horizontal)
            }
            .background(.ultraThinMaterial)
            // Scroll to next cue whenever it changes (new cue fires).
            .onChange(of: vm.nextPendingCue?.id) { _, newID in
                if let id = newID {
                    withAnimation(.easeInOut(duration: 0.6)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
            // Scroll to first pending cue on appear.
            .onAppear {
                if let id = vm.nextPendingCue?.id {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func cueRow(cue: ScheduledCue, isNext: Bool, now: Date, vm: ExecutionViewModel) -> some View {
        let isPast = cue.state != .pending

        VStack(alignment: .leading, spacing: 6) {
            if isNext {
                // Very large countdown — readable at arm's length.
                Text(formatInterval(cue.fireDate.timeIntervalSince(now)))
                    .font(.system(size: 60, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.gold)
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(cue.fireDate.formatted(date: .omitted, time: .shortened))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isPast ? .tertiary : .secondary)
            }

            // Use the translated text when available; falls back to the original message.
            Text(vm.displayMessage(for: cue))
                .font(isNext ? .title3.bold() : .callout)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(isNext ? 20 : 12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isNext ? Color.gold.opacity(0.12) : Color.cardBackground.opacity(0.7))
                .overlay {
                    if isNext {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.gold.opacity(0.45), lineWidth: 1)
                    }
                }
        )
        .opacity(isPast ? 0.35 : 1.0)
        .animation(.easeInOut(duration: 0.3), value: isNext)
    }

    private var emptyProgramView: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 44))
                .foregroundStyle(Color.gold.opacity(0.6))
            // Text(_:comment:) usa LocalizedStringKey y por tanto respeta el locale que la
            // raíz inyecta con .environment(\.locale, settings.locale). Con
            // String(localized:) estos textos salían en el idioma del sistema.
            Text("No events programmed",
                 comment: "Shown in execution when the cue list is empty")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Eclipse phase and countdown are active in the header.",
                 comment: "Explanation when no cues exist")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    // MARK: - Stop bar

    private var stopBar: some View {
        HStack {
            Spacer()
            stopButton
            Spacer()
        }
        .padding(.vertical, 24)
        .background(.ultraThinMaterial)
    }

    private var stopButton: some View {
        ZStack {
            // Track ring
            Circle()
                .stroke(Color.red.opacity(0.25), lineWidth: 5)

            // Progress ring — grows as the user holds.
            if holdProgress > 0 {
                Circle()
                    .trim(from: 0, to: holdProgress)
                    .stroke(Color.red,
                            style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.05), value: holdProgress)
            }

            VStack(spacing: 3) {
                Text("STOP", comment: "Stop execution button label")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                Text("Hold 3 s", comment: "Stop button instruction")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 90, height: 90)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if holdTimer == nil { startHold() } }
                .onEnded   { _ in cancelHold() }
        )
    }

    // MARK: - Hold logic

    private func startHold() {
        let startTime = Date.now
        let t = Timer(timeInterval: 0.05, repeats: true) { _ in
            Task { @MainActor in
                let elapsed = Date.now.timeIntervalSince(startTime)
                holdProgress = min(elapsed / 3.0, 1.0)
                if holdProgress >= 1.0 { performStop() }
            }
        }
        RunLoop.main.add(t, forMode: .common)
        holdTimer = t
    }

    private func cancelHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        withAnimation(.easeOut(duration: 0.25)) { holdProgress = 0 }
    }

    private func performStop() {
        cancelHold()
        execVM?.stop()
        flow.restart()
    }

    // MARK: - Helpers

    /// Formats a TimeInterval as MM:SS or H:MM:SS.
    private func formatInterval(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%02d:%02d", m, s)
    }
}
