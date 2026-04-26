import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Bump")
                    .font(BumpTypography.screenTitle)
                    .foregroundStyle(BumpColors.primaryText)

                AvailabilityToggleCard()

                SectionCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Friends who are free")
                            .font(BumpTypography.sectionTitle)

                        if appState.isLoadingHome {
                            ProgressView()
                                .tint(BumpColors.primaryText)
                        } else if appState.freeFriends.isEmpty {
                            Text("No friends are free yet.")
                                .foregroundStyle(BumpColors.secondaryText)
                        } else {
                            ForEach(appState.freeFriends) { friend in
                                HStack {
                                    Circle()
                                        .fill(BumpColors.success)
                                        .frame(width: 8, height: 8)
                                    Text(friend.name)
                                    Spacer()
                                    Text(friend.vibe)
                                        .foregroundStyle(BumpColors.secondaryText)
                                }
                            }
                        }
                    }
                }

                SectionCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Suggested plans")
                            .font(BumpTypography.sectionTitle)

                        if appState.isLoadingHome {
                            ProgressView()
                                .tint(BumpColors.primaryText)
                        } else if appState.suggestedPlans.isEmpty {
                            Text("Once you and friends share goals, quick suggestions appear here.")
                                .foregroundStyle(BumpColors.secondaryText)
                        } else {
                            ForEach(appState.suggestedPlans) { plan in
                                Text("You and \(plan.friendName) both want to \(plan.activity)")
                                    .foregroundStyle(BumpColors.primaryText)
                            }
                        }
                    }
                }

                PrimaryButton(title: "Start a plan") {
                    // Wire to event creation flow.
                }

                if let authError = appState.authErrorMessage {
                    Text(authError)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            .padding(20)
        }
        .navigationTitle("Home")
        .task {
            await appState.loadHomeData()
        }
        .refreshable {
            await appState.loadHomeData(showLoading: false)
        }
    }
}
