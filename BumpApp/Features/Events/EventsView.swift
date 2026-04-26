import SwiftUI

struct EventsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Events")
                    .font(BumpTypography.screenTitle)

                SectionCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Top events near you")
                            .font(BumpTypography.sectionTitle)
                        Text("No events yet. Create one in 2 taps.")
                            .foregroundStyle(BumpColors.secondaryText)
                    }
                }

                SectionCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Private invites")
                            .font(BumpTypography.sectionTitle)
                        Text("Your private invites will appear here.")
                            .foregroundStyle(BumpColors.secondaryText)
                    }
                }

                PrimaryButton(title: "Create event") {
                    // Add event creation sheet.
                }
            }
            .padding(20)
        }
        .navigationTitle("Events")
    }
}
