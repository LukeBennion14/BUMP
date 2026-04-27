import SwiftUI

struct AvailabilityToggleCard: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("I'm Free")
                        .font(BumpTypography.sectionTitle)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { appState.isFree },
                        set: { newValue in
                            Task {
                                await appState.setAvailability(isFree: newValue, freeUntil: appState.freeUntil)
                            }
                        }
                    ))
                        .labelsHidden()
                }

                if appState.isFree {
                    DatePicker("Free until", selection: $appState.freeUntil, displayedComponents: [.hourAndMinute])
                        .datePickerStyle(.compact)
                        .foregroundStyle(BumpColors.primaryText)
                        .onChange(of: appState.freeUntil) { _, value in
                            Task {
                                await appState.setAvailability(isFree: true, freeUntil: value)
                            }
                        }

                    Text("Visible to friends right now")
                        .foregroundStyle(BumpColors.secondaryText)
                        .font(.subheadline)
                } else {
                    Text("Turn this on to show friends you're available")
                        .foregroundStyle(BumpColors.secondaryText)
                        .font(.subheadline)
                }
            }
        }
    }
}
