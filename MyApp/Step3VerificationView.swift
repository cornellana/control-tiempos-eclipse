/// Step3VerificationView.swift — Step 3: map verification and eclipse card.
///
/// Shows the observation point on a map (200 m zoom) and either:
///   • A real eclipse card with computed contact times, including an xjubier button; or
///   • A simulation card (SIMULATION badge) where the user enters the assumed C2.
///
/// The Continue button is pinned outside the scroll area so it is always visible.
/// The xjubier button lives inside EclipseCardView (between kind badge and contacts)
/// and opens the eclipse-specific GoogleMapFull page in Safari.app via openURL.

import SwiftUI
import MapKit

struct Step3VerificationView: View {

    @Environment(FlowViewModel.self) private var flow

    /// Radio del encuadre inicial del mapa, en metros.
    private static let mapSpanMeters: CLLocationDistance = 200

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
            if !flow.locationName.isEmpty {
                Text(flow.locationName)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            Color.clear.frame(width: 60, height: 1)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    // MARK: - Map

    /// Mapa centrado en el punto de observación.
    ///
    /// Usa `initialPosition` en lugar de un binding con `.automatic` + `onAppear`: así
    /// MapKit se encuadra una sola vez. Con la versión anterior el mapa se disponía primero
    /// con la región automática deducida del marcador y se volvía a encuadrar en cuanto
    /// aparecía, duplicando el trabajo de layout justo al entrar en el paso.
    private func mapSection(height: CGFloat) -> some View {
        Map(initialPosition: initialCameraPosition) {
            if let coord = flow.coordinate {
                Marker("Observation Point", systemImage: "location.fill", coordinate: coord)
                    .tint(Color.gold)
            }
        }
        .frame(height: height)
        .clipShape(Rectangle())
    }

    /// Encuadre inicial: el punto de observación con un radio de `mapSpanMeters`.
    private var initialCameraPosition: MapCameraPosition {
        guard let coord = flow.coordinate else { return .automatic }
        return .region(MKCoordinateRegion(
            center:             coord,
            latitudinalMeters:  Self.mapSpanMeters,
            longitudinalMeters: Self.mapSpanMeters
        ))
    }

    // MARK: - Content card

    @ViewBuilder
    private var contentCard: some View {
        if flow.isSimulation {
            simulationCard
        } else if let circ = flow.circumstances {
            EclipseCardView(circumstances: circ, xjubierURL: xjubierURL())
        }
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
.tourCard(TourContent.step(14))
    }

    // MARK: - Helpers

    /// Construye la URL del mapa interactivo de xjubier.free.fr para el eclipse concreto,
    /// con las coordenadas del observador pre-cargadas.
    ///
    /// Formato verificado: http://xjubier.free.fr/en/site_pages/solar_eclipses/
    ///     TSE_2026_GoogleMapFull.html?Lat=41.68294&Lng=0.47930&Elv=0&Zoom=7&LC=1
    ///
    /// El prefijo del fichero ("TSE", "ASE", "HSE") se deduce del tipo global del eclipse
    /// (última letra del ID del dataset, p.ej. "SE2026Aug12T" → T → TSE). Los eclipses
    /// parciales globales (letra P) no tienen página GoogleMapFull en xjubier; en ese caso
    /// la función devuelve nil y el botón queda oculto.
    ///
    /// xjubier solo ofrece este mapa en inglés (/en/): las rutas /es/ y /fr/ dan 404.
    private func xjubierURL() -> URL? {
        guard let coord = flow.coordinate,
              let eclipseID = EclipseEngine.xjubierID(for: flow.eventDate),
              let typeChar = eclipseID.last else { return nil }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let year = cal.dateComponents([.year], from: flow.eventDate).year else { return nil }

        let prefix: String
        switch typeChar {
        case "T": prefix = "TSE"
        case "A": prefix = "ASE"
        case "H": prefix = "HSE"
        default:  return nil    // eclipses globalmente parciales no tienen mapa dedicado
        }

        let filename = "\(prefix)_\(year)_GoogleMapFull.html"
        var uc = URLComponents(string: "http://xjubier.free.fr/en/site_pages/solar_eclipses/\(filename)")!
        uc.queryItems = [
            URLQueryItem(name: "Lat",  value: String(format: "%.5f", coord.latitude)),
            URLQueryItem(name: "Lng",  value: String(format: "%.5f", coord.longitude)),
            URLQueryItem(name: "Elv",  value: "0"),
            URLQueryItem(name: "Zoom", value: "18"),
            URLQueryItem(name: "LC",   value: "1"),
        ]
        return uc.url
    }
}
