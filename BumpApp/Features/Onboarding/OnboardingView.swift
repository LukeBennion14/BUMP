import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState

    @State private var selectedHobbies = Set<Hobby>()
    @State private var hobbyGoals: [Int: String] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Set up your vibe")
                    .font(BumpTypography.screenTitle)
                    .foregroundStyle(BumpColors.primaryText)

                Text("Pick hobbies, then add specific goals so Bump can suggest instant plans.")
                    .foregroundStyle(BumpColors.secondaryText)

                Text("Hobbies")
                    .font(BumpTypography.sectionTitle)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 12)], spacing: 12) {
                    ForEach(SeedData.hobbies) { hobby in
                        hobbyChip(hobby)
                    }
                }

                if !selectedHobbies.isEmpty {
                    Text("Goals")
                        .font(BumpTypography.sectionTitle)

                    ForEach(Array(selectedHobbies).sorted(by: { $0.id < $1.id }), id: \.id) { hobby in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(hobby.prompt)
                                .foregroundStyle(BumpColors.secondaryText)
                            TextField("Add a goal", text: Binding(
                                get: { hobbyGoals[hobby.id] ?? "" },
                                set: { hobbyGoals[hobby.id] = $0 }
                            ))
                            .padding()
                            .background(BumpColors.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                }

                PrimaryButton(title: "Finish onboarding") {
                    let goals = selectedHobbies.compactMap { hobby -> GoalInput? in
                        let value = (hobbyGoals[hobby.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !value.isEmpty else { return nil }
                        return GoalInput(hobby: hobby, value: value)
                    }
                    Task {
                        await appState.completeOnboarding(selectedHobbies: Array(selectedHobbies), goals: goals)
                    }
                }
                .disabled(selectedHobbies.isEmpty || appState.isBusy)
                .opacity(selectedHobbies.isEmpty || appState.isBusy ? 0.6 : 1)

                if let authError = appState.authErrorMessage {
                    Text(authError)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            .padding(20)
        }
    }

    private func hobbyChip(_ hobby: Hobby) -> some View {
        let selected = selectedHobbies.contains(hobby)
        return Button {
            if selected {
                selectedHobbies.remove(hobby)
            } else {
                selectedHobbies.insert(hobby)
            }
        } label: {
            Text(hobby.name)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(selected ? Color.black : BumpColors.primaryText)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(selected ? Color.white : BumpColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
