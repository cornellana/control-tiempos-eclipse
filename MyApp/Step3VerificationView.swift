/// Step3VerificationView.swift — Step 3: map verification and eclipse card.
///
/// Shows the observation point on a map (200 m zoom) and either:
///   • A real eclipse card with computed contact times, including an xjubier button; or
///   • A simulation card (SIMULATION badge) where the user enters the assumed C2.
///
/// The Continue button is pinned outside the scroll area so it is always visible.
/// The xjubier button lives inside EclipseCardView (between kind badge and contacts)
/// and opens the eclipse-specific GoogleMapFull page in Safari.app via openURL.
///
/// ## Exploration mode
///
/// The toolbar's magnifier turns the map into a scouting instrument: a crosshair pins the
/// centre, and whatever point it lands on is evaluated live — total or partial, magnitude,
/// length of totality, height of the Sun and distance back to the current site. The point
/// can then be adopted as the observation site or filed under a name.
///
/// This is worth having because `EclipseEngine` is closed-form and offline, so a reading
/// costs nothing. The same question previously had to be put to xjubier.free.fr in Safari,
/// one point at a time, copying coordinates back by hand. It matters most near the edge of
/// the band: at Raimat on 2026-08-12 the eclipse comes out partial, and the nearest total
/// ground is a few kilometres to the south.

import SwiftUI
import MapKit
import SwiftData

struct Step3VerificationView: View {

    @Environment(FlowViewModel.self) private var flow
    @Environment(\.modelContext) private var modelContext

    /// Radio del encuadre inicial del mapa, en metros.
    private static let mapSpanMeters: CLLocationDistance = 200

    /// Radio del encuadre al entrar en exploración, en metros.
    ///
    /// Los 200 m de la verificación sirven para reconocer el sitio, pero exploran fatal: un
    /// arrastre de pantalla completa mueve doscientos metros, y el borde de la franja de
    /// totalidad está a kilómetros. A 6 km cada arrastre cubre una distancia con la que la
    /// insignia llega a cambiar de PARCIAL a TOTAL.
    private static let exploreSpanMeters: CLLocationDistance = 6_000

    // MARK: - Exploration state

    /// True while the map is being used to scout points rather than to confirm one.
    @State private var exploring = false

    /// Coordinate under the crosshair. Seeded with the observation point on entry, so the
    /// card describes something from the first frame instead of waiting for a pan.
    @State private var exploredCoordinate: CLLocationCoordinate2D?

    /// Bumped to rebuild the `Map` and re-apply `initialPosition`.
    ///
    /// The map keeps using `initialPosition` rather than a `position` binding, because a
    /// binding starts at `.automatic` and re-frames once on appear — the duplicated layout
    /// this view was explicitly written to avoid. Changing the identity instead gives the
    /// one thing the binding was wanted for: recentring on the observation point when
    /// exploration ends, and nothing else.
    @State private var mapIdentity = 0

    @State private var showSaveAlert = false
    @State private var saveName = ""
    @State private var pendingOverwrite: SavedLocation?

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.appBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    mapSection(height: geo.size.height * 0.50)
                    ScrollView {
                        contentCard
                            .padding()
                        Color.clear.frame(height: 8)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                continueButton
                    .padding()
                    .background(Color.appBackground)
            }
        }
        .alert("Save Location", isPresented: $showSaveAlert) {
            TextField("Name", text: $saveName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { commitSave() }
        } message: {
            if let coord = exploredCoordinate {
                Text(String(format: "%.5f°, %.5f°", coord.latitude, coord.longitude))
            }
        }
        .alert("Overwrite", isPresented: overwriteBinding) {
            Button("Cancel", role: .cancel) { pendingOverwrite = nil }
            Button("Overwrite", role: .destructive) { commitOverwrite() }
        } message: {
            Text("A saved location with this name already exists. Overwrite it?")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button { flow.step = .eventDate } label: {
                Label("Back", systemImage: "chevron.left")
                    .foregroundStyle(Color.gold)
            }
            .tourCard(TourContent.step(11))
            Spacer()
            if !flow.locationName.isEmpty, !exploring {
                Text(flow.locationName)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            Button { toggleExploring() } label: {
                Image(systemName: "sparkle.magnifyingglass")
                    .foregroundStyle(exploring ? Color.gold : .secondary)
            }
            .frame(width: 60, alignment: .trailing)
            .accessibilityLabel(Text("Explore around"))
            .tourCard(TourContent.step(26))
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    /// Enters or leaves exploration, seeding the reading and re-framing the camera.
    ///
    /// The identity bump is what re-applies `initialCameraPosition`: wide on the way in,
    /// back to the observation point at verification zoom on the way out.
    private func toggleExploring() {
        exploring.toggle()
        exploredCoordinate = exploring ? flow.coordinate : nil
        mapIdentity += 1
    }

    // MARK: - Map

    /// Mapa centrado en el punto de observación.
    ///
    /// Usa `initialPosition` en lugar de un binding con `.automatic` + `onAppear`: así
    /// MapKit se encuadra una sola vez. Con la versión anterior el mapa se disponía primero
    /// con la región automática deducida del marcador y se volvía a encuadrar en cuanto
    /// aparecía, duplicando el trabajo de layout justo al entrar en el paso.
    ///
    /// Explorando, el marcador sigue en el punto de observación: es la referencia contra la
    /// que se mide todo lo demás. Quien se mueve es la cámara, y el punto de mira lee su
    /// centro. `frequency: .onEnd` evita recalcular en cada fotograma del arrastre.
    private func mapSection(height: CGFloat) -> some View {
        Map(initialPosition: initialCameraPosition) {
            if let coord = flow.coordinate {
                Marker("Observation Point", systemImage: "location.fill", coordinate: coord)
                    .tint(Color.gold)
            }
        }
        .id(mapIdentity)
        .onMapCameraChange(frequency: .onEnd) { context in
            guard exploring else { return }
            exploredCoordinate = context.region.center
        }
        .overlay {
            if exploring { crosshair }
        }
        .frame(height: height)
        .clipShape(Rectangle())
    }

    /// The fixed sight at the centre of an exploring map.
    ///
    /// Hollow on purpose: a filled marker would hide the very ground being judged, and what
    /// matters while scouting is what sits under the point — a ridge, a treeline, a road.
    private var crosshair: some View {
        ZStack {
            Circle()
                .stroke(Color.black.opacity(0.55), lineWidth: 5)
                .frame(width: 28, height: 28)
            Circle()
                .stroke(Color.gold, lineWidth: 2.5)
                .frame(width: 28, height: 28)
            Circle()
                .fill(Color.gold)
                .frame(width: 5, height: 5)
        }
        .allowsHitTesting(false)
    }

    /// Encuadre inicial: el punto de observación, ancho al explorar y cerrado al verificar.
    private var initialCameraPosition: MapCameraPosition {
        guard let coord = flow.coordinate else { return .automatic }
        let span = exploring ? Self.exploreSpanMeters : Self.mapSpanMeters
        return .region(MKCoordinateRegion(
            center:             coord,
            latitudinalMeters:  span,
            longitudinalMeters: span
        ))
    }

    // MARK: - Content card

    @ViewBuilder
    private var contentCard: some View {
        if exploring {
            explorationCard
        } else if flow.isSimulation {
            simulationCard
        } else if let circ = flow.circumstances {
            EclipseCardView(circumstances:  circ,
                            xjubierURL:     xjubierURL(),
                            peakFinderURL:  peakFinderURL(for: circ))
        }
    }

    // MARK: - Exploration card

    /// Live readout of the point under the crosshair, with the two things worth doing to it.
    private var explorationCard: some View {
        let circ = exploredCoordinate.flatMap {
            EclipseEngine.circumstances(lat: $0.latitude, lon: $0.longitude, date: flow.eventDate)
        }

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(exploredKindLabel(circ))
                    .font(.headline)
                    .foregroundStyle(circ == nil ? .white : .black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(circ == nil ? Color.orange.opacity(0.35) : Color.gold,
                                in: Capsule())
                Spacer()
                if let mag = circ?.magnitude {
                    Text(String(format: "mag %.3f", mag))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let coord = exploredCoordinate {
                Text(String(format: "%.5f°, %.5f°", coord.latitude, coord.longitude))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("Drag the map to read any point")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let totality = circ?.totalityDurationSeconds {
                explorationRow("Totality", formatDuration(totality))
            }
            if let altitude = circ?.sunAltitudeAtMax {
                explorationRow("Sun Altitude", String(format: "%.1f°", altitude))
            }
            if let distance = distanceToObservationPoint {
                explorationRow("Distance to current point", distance)
            }

            HStack(spacing: 10) {
                Button {
                    saveName = ""
                    showSaveAlert = true
                } label: {
                    Text("Save Location").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Color.gold)
                .disabled(exploredCoordinate == nil)
                .tourCard(TourContent.step(27))

                Button { adoptExploredPoint() } label: {
                    Text("Use this point").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.gold)
                .disabled(exploredCoordinate == nil)
                .tourCard(TourContent.step(28))
            }
        }
        .padding()
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16))
    }

    private func explorationRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack {
            Text(label).font(.callout).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.callout.monospacedDigit()).foregroundStyle(.white)
        }
    }

    /// Badge label for the explored point, including the "nothing here" case.
    private func exploredKindLabel(_ circumstances: EclipseCircumstances?) -> LocalizedStringKey {
        guard let kind = circumstances?.kind else { return "No eclipse here" }
        switch kind {
        case .total:     return "TOTAL"
        case .annular:   return "ANNULAR"
        case .partial:   return "PARTIAL"
        case .hybrid:    return "HYBRID"
        case .simulated: return "SIMULATION"
        }
    }

    /// Distance from the observation point to the crosshair, in metres or kilometres.
    ///
    /// Whole metres below a kilometre because at that range the question is how far to walk;
    /// two decimals above, so a pan still shows movement.
    private var distanceToObservationPoint: String? {
        guard let target = flow.coordinate, let explored = exploredCoordinate else { return nil }
        let metres = CLLocation(latitude: target.latitude, longitude: target.longitude)
            .distance(from: CLLocation(latitude: explored.latitude, longitude: explored.longitude))
        return metres < 1_000
            ? String(format: "%.0f m", metres)
            : String(format: "%.2f km", metres / 1_000)
    }

    // MARK: - Exploration actions

    /// Adopts the crosshair's point as the observation site and recomputes the eclipse.
    private func adoptExploredPoint() {
        guard let coord = exploredCoordinate else { return }
        flow.coordinate = coord
        // El nombre describía el punto anterior: mantenerlo mentiría en la cabecera, en el
        // enlace de PeakFinder y en el programa impreso.
        flow.locationName = ""
        flow.evaluateEclipse()
        exploring = false
        exploredCoordinate = nil
        mapIdentity += 1
    }

    /// Binding that drives the overwrite alert off `pendingOverwrite`.
    private var overwriteBinding: Binding<Bool> {
        Binding(get: { pendingOverwrite != nil },
                set: { if !$0 { pendingOverwrite = nil } })
    }

    /// Saves the explored point, asking first when the name is already taken.
    private func commitSave() {
        let trimmed = saveName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, let coord = exploredCoordinate else { return }

        let descriptor = FetchDescriptor<SavedLocation>(
            predicate: #Predicate { $0.name == trimmed }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            pendingOverwrite = existing
            return
        }
        modelContext.insert(SavedLocation(name: trimmed,
                                          latitude: coord.latitude,
                                          longitude: coord.longitude))
    }

    private func commitOverwrite() {
        guard let existing = pendingOverwrite, let coord = exploredCoordinate else { return }
        existing.latitude  = coord.latitude
        existing.longitude = coord.longitude
        pendingOverwrite = nil
    }

    private func formatDuration(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d m %02d s", s / 60, s % 60)
    }

    // MARK: - Simulation card

    private var simulationCard: some View {
        @Bindable var flow = flow
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("SIMULATION")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(Color.orange, in: Capsule())
                Spacer()
            }

            Text("No eclipse found for this date. Enter assumed C2 (start of totality) to generate the timeline.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            DatePicker("C2 — Start of totality",
                       selection: $flow.simulatedC2,
                       displayedComponents: [.date, .hourAndMinute])
                .tint(Color.gold)
                .tourCard(TourContent.step(13))

            if let circ = flow.effectiveCircumstances {
                Divider().background(.secondary.opacity(0.3))
                Text("Generated Phases")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                generatedPhasesRows(circ: circ)
            }
        }
        .padding()
        .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16))
    }

    private func generatedPhasesRows(circ: EclipseCircumstances) -> some View {
        let phases: [(EclipsePhase, LocalizedStringKey)] = [
            (.c1, "C1"), (.c2, "C2"), (.max, "MAX"), (.c3, "C3"), (.c4, "C4"),
        ]
        return VStack(spacing: 6) {
            ForEach(phases, id: \.0) { phase, label in
                if let date = circ.contacts[phase] {
                    HStack {
                        Text(label).font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Text(date.formatted(date: .omitted, time: .standard))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }

    // MARK: - Continue button

    private var continueButton: some View {
        Button { flow.advance() } label: {
            Text("Continue").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.gold)
        .controlSize(.large)
        // Explorando, el punto elegido aún no está decidido: avanzar al programa con la
        // coordenada anterior mientras el mapa muestra otra sería lo contrario de lo que
        // la pantalla parece decir.
        .disabled(exploring)
        .tourCard(TourContent.step(14))
    }

    // MARK: - Helpers

    /// URL del mapa interactivo de xjubier.free.fr para el eclipse de la fecha elegida.
    ///
    /// La construcción vive en `ExternalLinks` para poder probarla; aquí solo se
    /// resuelven los datos del flujo (coordenadas, id del eclipse y año en UTC).
    private func xjubierURL() -> URL? {
        guard let coord = flow.coordinate,
              let eclipseID = EclipseEngine.xjubierID(for: flow.eventDate) else { return nil }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let year = cal.dateComponents([.year], from: flow.eventDate).year else { return nil }

        return ExternalLinks.xjubier(latitude:  coord.latitude,
                                     longitude: coord.longitude,
                                     eclipseID: eclipseID,
                                     year:      year)
    }

    /// URL del panorama de peakfinder.com apuntando al Sol en el instante del máximo.
    ///
    /// Sirve para comprobar el perfil del horizonte antes de comprometerse con un sitio:
    /// el 12/08/2026 el Sol está a 5° sobre el horizonte en el máximo, así que un cerro
    /// o una hilera de chopos puede tapar la totalidad entera.
    private func peakFinderURL(for circumstances: EclipseCircumstances) -> URL? {
        guard let coord = flow.coordinate else { return nil }

        return ExternalLinks.peakFinder(latitude:      coord.latitude,
                                        longitude:     coord.longitude,
                                        name:          flow.locationName,
                                        circumstances: circumstances)
    }
}
