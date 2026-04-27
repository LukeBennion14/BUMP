import SwiftUI

struct MessagesView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Messages")
                    .font(BumpTypography.screenTitle)

                SectionCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Chats")
                            .font(BumpTypography.sectionTitle)
                        Text("Start a chat, then convert it into a plan.")
                            .foregroundStyle(BumpColors.secondaryText)
                    }
                }

                SectionCard {
                    Text("No conversations yet.")
                        .foregroundStyle(BumpColors.secondaryText)
                }
            }
            .padding(20)
        }
        .navigationTitle("Messages")
    }
}
