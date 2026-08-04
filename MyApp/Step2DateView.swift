/// Step2DateView.swift — Step 2: choose the event date.
///
/// Shows a graphical `DatePicker`. The default date is pre-filled by `FlowViewModel`
/// with the next visible eclipse from the dataset (or today if none found).

import SwiftUI

struct Step2DateView: View {

    @Environment(FlowViewModel.self) private var flow

    var body: some View {
        @Bindable var flow = flow
        ZStack {
            Color.appBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button {
                        flow.step = .location
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .foregroundStyle(Color.gold)
                    }
                    .tourCard(TourContent.step(7))
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 16)

                Text("Event Date")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 8)

                Text("Select the date of the eclipse or rehearsal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 20)

                DatePicker(
                    "Date",
                    selection: $flow.eventDate,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .tint(Color.gold)
                .tourCard(TourContent.step(8))
                .padding()
                .background(Color.cardBackground, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                // "Today" shortcut below the calendar — useful for rehearsals.
                Button {
                    flow.eventDate = .now
                } label: {
                    Label("Today", systemImage: "calendar.badge.clock")
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.gold)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color.cardBackground, in: Capsule())
                }
                .tourCard(TourContent.step(9))
                .padding(.top, 12)

                Spacer()

                Button {
                    flow.evaluateEclipse()
                    flow.advance()
                } label: {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.gold)
                .controlSize(.large)
.tourCard(TourContent.step(10))
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
        }
    }
}
