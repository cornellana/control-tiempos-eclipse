/// WelcomeView.swift
/// First-run welcome screen: language selector + guided-tour launcher + "Get started".
///
/// Shown automatically on the first launch (when `AppSettings.hasCompletedOnboarding`
/// is `false`). Tapping "Get started" sets the flag and the app transitions to the
/// normal location step. The tour can also be accessed at any time from Settings.

import SwiftUI

struct WelcomeView: View {

    @Environment(AppSettings.self) private var settings
    @State private var showTour = false

    // MARK: - Body

    var body: some View {
        @Bindable var settings = settings

        ZStack {
            Color.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 32) {
                    heroSection
                    languageSection(settings: $settings.language)
                    actionButtons
                }
                .padding()
                .padding(.bottom, 16)
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showTour) {
            GuidedTourView()
        }
    }

    // MARK: - Subviews

    /// Branded header — mirrors the SplashView aesthetic for visual continuity.
    private var heroSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "sun.max.circle.fill")
                .font(.system(size: 76))
                .foregroundStyle(Color.gold)
                .padding(.top, 40)

            Text("Eclipse Timer")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)

            Text("Welcome! Choose your language to begin.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    /// Language picker — same mechanism as SettingsView (live locale update via AppSettings).
    private func languageSection(settings: Binding<VoiceLanguage>) -> some View {
        GroupBox {
            Picker("Language", selection: settings) {
                ForEach(VoiceLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang)
                }
            }
            .pickerStyle(.menu)
        } label: {
            Label("Language", systemImage: "globe")
                .foregroundStyle(.secondary)
        }
        .backgroundStyle(Color.cardBackground)
    }

    /// Tutorial button (secondary) and Get-started button (primary).
    private var actionButtons: some View {
        VStack(spacing: 14) {
            Button {
                showTour = true
            } label: {
                Label("View tutorial", systemImage: "questionmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Color.gold)
            .controlSize(.large)

            Button {
                withAnimation(.easeInOut(duration: 0.35)) {
                    settings.hasCompletedOnboarding = true
                }
            } label: {
                Text("Get started")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.gold)
            .controlSize(.large)
        }
    }
}
