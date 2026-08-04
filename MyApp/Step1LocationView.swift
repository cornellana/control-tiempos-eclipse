/// Step1LocationView.swift — Step 1: choose the observation location.
///
/// Presents two parallel options: one-shot GPS fix and manual decimal-degree entry.
/// A bookmarks button in the toolbar opens `SavedLocationsSheet` where the user
/// can save the current coordinate with a name and recall any previously saved location.

import SwiftUI
import SwiftData
import CoreLocation

struct Step1LocationView: View {

    @Environment(FlowViewModel.self)  private var flow
    @Environment(AppSettings.self)    private var settings
    @Environment(\.modelContext)      private var modelContext

    @State private var locationService       = LocationService()
    @State private var latText               = ""
    @State private var lonText               = ""
    @State private var showSettings          = false
    @State private var showSavedLocations    = false

    // MARK: - Derived state

    private var parsedCoordinate: CLLocationCoordinate2D? {
        // Normaliza la coma decimal (teclado español) al punto que espera Double().
        let latClean = latText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let lonClean = lonText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let lat = Double(latClean), let lon = Double(lonClean),
              lat >= -90, lat <= 90, lon >= -180, lon <= 180 else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// Las coordenadas manuales tienen prioridad: el usuario puede estar en casa y teclear
    /// el sitio del eclipse. GPS es el fallback cuando los campos manuales están vacíos.
    private var activeCoordinate: CLLocationCoordinate2D? {
        parsedCoordinate ?? locationService.coordinate
    }

    private var canContinue: Bool { activeCoordinate != nil }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        headerSection
                        gpsSection
                        manualSection
                        continueButton
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSavedLocations = true
                    } label: {
                        Label("Saved Locations", systemImage: "bookmark")
                            .foregroundStyle(Color.gold)
                    }
                    .tourCard(TourContent.step(1))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gear")
                            .foregroundStyle(Color.gold)
                    }
                    .tourCard(TourContent.step(2))
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environment(settings)
        }
        .sheet(isPresented: $showSavedLocations) {
            // Pasar los bindings de texto para que el sheet siempre lea el valor actual,
            // sin depender de ninguna captura por valor en el momento del tap.
            SavedLocationsSheet(
                latText:      $latText,
                lonText:      $lonText,
                gpsCoordinate: locationService.coordinate
            ) { loc in
                // Clear GPS so the populated text fields take effect immediately.
                locationService.coordinate = nil
                latText = String(format: "%.5f", loc.latitude)
                lonText = String(format: "%.5f", loc.longitude)
                flow.locationName = loc.name
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "sun.max.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.gold)
            Text("Eclipse Timer")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
            Text("Choose your observation location")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var gpsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                if let coord = locationService.coordinate {
                    Label(
                        String(format: "%.5f°,  %.5f°", coord.latitude, coord.longitude),
                        systemImage: "location.fill"
                    )
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(Color.gold)
                }

                Button {
                    // Limpiar coordenadas manuales y nombre para que GPS tenga el control.
                    latText = ""
                    lonText = ""
                    flow.locationName = ""
                    locationService.requestOnce()
                } label: {
                    HStack {
                        if locationService.isLoading {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "location.fill")
                        }
                        Text("Use Current Location")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.gold)
                .controlSize(.large)
                .disabled(locationService.isLoading)
.tourCard(TourContent.step(3))

                if let error = locationService.locationError {
                    Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        } label: {
            Label("GPS Location", systemImage: "location.circle")
                .foregroundStyle(.secondary)
        }
        .backgroundStyle(Color.cardBackground)
    }

    private var manualSection: some View {
        GroupBox {
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    coordinateField(title: "Latitude",  placeholder: "41.68294", text: $latText)
                    coordinateField(title: "Longitude", placeholder: "0.47930",  text: $lonText)
                }

                if !latText.isEmpty || !lonText.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: parsedCoordinate != nil
                              ? "checkmark.circle.fill"
                              : "exclamationmark.circle.fill")
                            .foregroundStyle(parsedCoordinate != nil ? Color.green : Color.orange)
                        Text(parsedCoordinate != nil
                             ? "Valid coordinates"
                             : "Latitude ±90°, Longitude ±180°")
                            .font(.caption)
                            .foregroundStyle(parsedCoordinate != nil ? Color.gray : Color.orange)
                    }
                }
            }
        } label: {
            Label("Manual Coordinates", systemImage: "keyboard")
                .foregroundStyle(.secondary)
        }
        .backgroundStyle(Color.cardBackground)
        .tourCard(TourContent.step(4))
    }

    private func coordinateField(title: LocalizedStringKey, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(
                text: text,
                prompt: Text(placeholder).foregroundStyle(.tertiary)
            ) {
                Text(title)
            }
            .keyboardType(.numbersAndPunctuation)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
        }
    }

    private var continueButton: some View {
        Button {
            guard let coord = activeCoordinate else { return }
            flow.coordinate = coord
            // nextVisibleEclipseDate recorre los 24 eclipses del dataset aplicando el
            // algoritmo besseliano a cada uno: 0,9 ms medidos. Se ejecuta en línea —
            // mandarlo a un hilo de fondo y volver al MainActor costaba más que el
            // cálculo y retrasaba el cambio de paso un par de frames.
            let nextDate = EclipseEngine.nextVisibleEclipseDate(
                lat:   coord.latitude,
                lon:   coord.longitude,
                after: .now
            )
            flow.eventDate = nextDate ?? Calendar.current.startOfDay(for: .now)
            flow.advance()
        } label: {
            Text("Continue").frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color.gold)
        .controlSize(.large)
        .disabled(!canContinue)
        .padding(.bottom)
        .tourCard(TourContent.step(6))
    }
}

// MARK: - SavedLocationsSheet

/// Sheet for managing named saved locations.
///
/// Lets the user save the current coordinate with a custom name and recall any
/// previously saved location. Uses a native `List` for swipe-to-delete support.
///
/// Receives the parent's text field contents as `@Binding` so the coordinate is
/// computed fresh on each render — no value-capture timing issues at button tap.
fileprivate struct SavedLocationsSheet: View {

    /// Raw latitude text from the parent's text field (binding = always current).
    @Binding var latText: String
    /// Raw longitude text from the parent's text field (binding = always current).
    @Binding var lonText: String
    /// GPS coordinate when available; nil otherwise.
    let gpsCoordinate: CLLocationCoordinate2D?
    /// Called when the user taps a saved location row; parent updates its fields.
    let onSelect: (SavedLocation) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss)      private var dismiss

    @Query(sort: \SavedLocation.name) private var savedLocations: [SavedLocation]

    @State private var showSaveAlert        = false
    @State private var saveName             = ""
    @State private var showOverwriteConfirm = false

    /// Coordenada a guardar: las coordenadas manuales tienen prioridad porque el usuario
    /// puede estar físicamente en otro lugar y querer guardar la ubicación del eclipse que
    /// ha tecleado. Si no hay texto manual válido, se usa GPS como fallback.
    private var currentCoordinate: CLLocationCoordinate2D? {
        let latNorm = latText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let lonNorm = lonText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        if let lat = Double(latNorm), let lon = Double(lonNorm),
           lat >= -90, lat <= 90, lon >= -180, lon <= 180 {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        return gpsCoordinate
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()

                List {
                    // Save current location — only visible when coordinates are available.
                    if let coord = currentCoordinate {
                        Section {
                            Button {
                                saveName = ""
                                showSaveAlert = true
                            } label: {
                                Label("Save current location…", systemImage: "bookmark.badge.plus")
                                    .foregroundStyle(Color.gold)
                            }
                            .listRowBackground(Color.cardBackground)
                        } footer: {
                            Text(String(format: "%.5f°, %.5f°", coord.latitude, coord.longitude))
                        }
                    }

                    // Saved locations list.
                    Section {
                        if savedLocations.isEmpty {
                            Text("No saved locations yet.")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                                .listRowBackground(Color.cardBackground)
                        } else {
                            ForEach(savedLocations) { loc in
                                Button {
                                    onSelect(loc)
                                    dismiss()
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(loc.name)
                                            .font(.callout)
                                            .foregroundStyle(.white)
                                        Text(String(format: "%.5f°, %.5f°",
                                                    loc.latitude, loc.longitude))
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 2)
                                }
                                .listRowBackground(Color.cardBackground)
                            }
                            .onDelete { indexSet in
                                indexSet.map { savedLocations[$0] }.forEach {
                                    modelContext.delete($0)
                                }
                            }
                        }
                    } header: {
                        Text("Saved")
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Saved Locations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.gold)
                }
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                        .foregroundStyle(Color.gold)
                }
            }
        }
        .alert("Save Location", isPresented: $showSaveAlert) {
            TextField("Name", text: $saveName)
            Button("Save") { saveCurrentLocation() }
            Button("Cancel", role: .cancel) { saveName = "" }
        } message: {
            if let coord = currentCoordinate {
                Text(String(format: "%.5f°, %.5f°", coord.latitude, coord.longitude))
            }
        }
        // Confirmación antes de sobrescribir una localización con el mismo nombre.
        .confirmationDialog(
            "Replace \"\(saveName.trimmingCharacters(in: .whitespaces))\"?",
            isPresented: $showOverwriteConfirm,
            titleVisibility: .visible
        ) {
            Button("Overwrite", role: .destructive) { overwriteLocation() }
            Button("Cancel", role: .cancel) { saveName = "" }
        } message: {
            Text("A saved location with this name already exists. Overwriting will replace it.")
        }
    }

    private func saveCurrentLocation() {
        let trimmed = saveName.trimmingCharacters(in: .whitespaces)
        guard let coord = currentCoordinate, !trimmed.isEmpty else { return }
        // Si ya existe una localización con ese nombre, pedir confirmación.
        if savedLocations.contains(where: { $0.name == trimmed }) {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                showOverwriteConfirm = true
            }
            return
        }
        performSaveLocation(name: trimmed, coord: coord)
    }

    /// Actualiza la localización existente con las nuevas coordenadas.
    private func overwriteLocation() {
        let trimmed = saveName.trimmingCharacters(in: .whitespaces)
        guard let coord = currentCoordinate, !trimmed.isEmpty else { return }
        if let existing = savedLocations.first(where: { $0.name == trimmed }) {
            modelContext.delete(existing)
        }
        performSaveLocation(name: trimmed, coord: coord)
    }

    /// Inserta una nueva `SavedLocation` con el nombre y coordenadas dados.
    private func performSaveLocation(name: String, coord: CLLocationCoordinate2D) {
        modelContext.insert(SavedLocation(name: name, latitude: coord.latitude, longitude: coord.longitude))
        saveName = ""
    }
}
