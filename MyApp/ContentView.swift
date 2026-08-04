/// ContentView.swift — Application entry point and step router.

import SwiftUI
import SwiftData
import UIKit

// MARK: - App

@main struct ControlTiemposEclipseApp: App {

    init() {
        // Fija el fondo de la ventana UIKit al color oscuro de la app para eliminar el
        // destello blanco que aparece entre el launch screen del sistema y el primer
        // frame de SwiftUI. UIWindow.appearance() actúa antes de que se cree cualquier ventana.
        UIWindow.appearance().backgroundColor = UIColor(red: 0.071, green: 0.071, blue: 0.082, alpha: 1)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [ProgramEvent.self, SavedLocation.self, SavedProgram.self])
    }
}

// MARK: - RootView

/// Hosts the `FlowViewModel` and routes to the view for the current step.
///
/// Strategy: `stepContent` is ALWAYS part of the view hierarchy (opacity 0 while the
/// splash is visible) so SwiftUI pre-renders it — including SwiftData queries — before
/// the splash fades out. This eliminates the black frame that would otherwise appear
/// when SwiftUI had to build the content tree from scratch during the transition.
struct RootView: View {

    @State private var flow     = FlowViewModel()
    @State private var settings = AppSettings()
    @State private var isReady  = false

    /// Tarjeta de ayuda que sale al mantener pulsado un botón medio segundo.
    /// Vive aquí, en la raíz, para poder dibujarse por encima de cualquier paso.
    @State private var tourOverlay = TourOverlayState()

    // Backup import triggered from onOpenURL (AirDrop / Files "Open with…").
    @State private var pendingImport:  IdentifiableBackup? = nil
    @State private var preloadBackup:  BackupFile?         = nil
    @State private var openURLError:   String?             = nil

    var body: some View {
        ZStack {
            // Fondo permanente — nunca hay negro en ninguna capa.
            Color.appBackground.ignoresSafeArea()

            // stepContent siempre está en el árbol para pre-renderizarse.
            // Invisible durante el splash; aparece con fade cuando isReady = true.
            stepContent
                .opacity(isReady ? 1 : 0)

            // Splash superpuesto encima del contenido mientras !isReady.
            // Se desvanece cuando isReady = true y se elimina del árbol al terminar la animación.
            if !isReady {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }

            // Tarjeta de la pulsación larga: por encima de todo, incluida la
            // bienvenida, para que el truco funcione desde el primer momento.
            if let step = tourOverlay.activeStep {
                TourCardPopup(step: step) {
                    withAnimation(.easeInOut(duration: 0.2)) { tourOverlay.activeStep = nil }
                }
                .transition(.opacity)
                .zIndex(2)
            }
        }
        .environment(tourOverlay)
        // Fundido corto: 0,4 s se percibían como parte del tiempo de carga.
        .animation(.easeInOut(duration: 0.18), value: isReady)
        .preferredColorScheme(.dark)
        .environment(\.locale, settings.locale)
        .onOpenURL { url in
            guard url.pathExtension.lowercased() == BackupService.fileExtension else { return }
            let needsAccess = url.startAccessingSecurityScopedResource()
            defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let backup = try BackupService.importFile(from: url)
                if isReady {
                    pendingImport = IdentifiableBackup(backup: backup)
                } else {
                    preloadBackup = backup
                }
            } catch {
                openURLError = error.localizedDescription
            }
        }
        .onChange(of: isReady) { _, ready in
            if ready, let backup = preloadBackup {
                pendingImport = IdentifiableBackup(backup: backup)
                preloadBackup = nil
            }
        }
        .sheet(item: $pendingImport) { item in
            RestoreSheet(backup: item.backup)
        }
        .alert("Import Error", isPresented: Binding(
            get: { openURLError != nil },
            set: { if !$0 { openURLError = nil } }
        )) {
            Button("OK") { openURLError = nil }
        } message: {
            Text(openURLError ?? "")
        }
        .task {
            // Cede el MainActor para que SwiftUI confirme el primer frame (SplashView).
            await Task.yield()

            // Precalentamiento del motor: carga eclipses.json, lo decodifica y parsea las
            // fechas del dataset. Medido en 4,8 ms — se hace en el MainActor porque montar
            // un hilo de fondo y volver cuesta más que el propio trabajo.
            _ = EclipseEngine.hasEclipse(for: .now)

            // Sin pausa artificial: el splash dura lo que tarde el primer frame real.
            isReady = true
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        // En el primer arranque manda la bienvenida: elige idioma y ofrece el tour.
        // Al pulsar «Empezar» se marca la bandera y ya nunca vuelve a salir sola.
        if !settings.hasCompletedOnboarding {
            WelcomeView()
                .environment(settings)
        } else {
            flowContent
        }
    }

    @ViewBuilder
    private var flowContent: some View {
        switch flow.step {
        case .location:
            Step1LocationView()
                .environment(flow)
                .environment(settings)
        case .eventDate:
            Step2DateView()
                .environment(flow)
        case .verification:
            Step3VerificationView()
                .environment(flow)
        case .program:
            Step4ProgramView()
                .environment(flow)
                .environment(settings)
        case .execution:
            Step5ExecutionView()
                .environment(flow)
                .environment(settings)
        }
    }
}

// MARK: - SplashView

/// Branded loading screen shown during app startup.
private struct SplashView: View {

    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 28) {
                ZStack {
                    Circle()
                        .fill(Color.gold.opacity(0.14))
                        .frame(width: 128, height: 128)
                        .scaleEffect(pulse ? 1.28 : 1.0)
                        .animation(
                            .easeInOut(duration: 1.3).repeatForever(autoreverses: true),
                            value: pulse
                        )
                    Image(systemName: "sun.max.circle.fill")
                        .font(.system(size: 76))
                        .foregroundStyle(Color.gold)
                }

                Text("Eclipse Timer")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)

                ProgressView()
                    .tint(Color.gold)
                    .scaleEffect(1.3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { pulse = true }
    }
}
