import SwiftUI

struct SignUpView: View {
    enum AuthMode: String, CaseIterable, Identifiable {
        case signUp = "Sign up"
        case signIn = "Sign in"
        var id: String { rawValue }
    }

    @EnvironmentObject private var appState: AppState

    @State private var mode: AuthMode = .signUp
    @State private var name = ""
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer(minLength: 8)

            Text("Bump")
                .font(BumpTypography.screenTitle)
                .foregroundStyle(BumpColors.primaryText)

            Text("Go from \"I'm bored\" to \"I have a plan\".")
                .font(BumpTypography.body)
                .foregroundStyle(BumpColors.secondaryText)

            Picker("Auth Mode", selection: $mode) {
                ForEach(AuthMode.allCases) { current in
                    Text(current.rawValue).tag(current)
                }
            }
            .pickerStyle(.segmented)

            Group {
                if mode == .signUp {
                    textField("Name", text: $name)
                    textField("Username", text: $username)
                }
                textField("Email", text: $email)
                SecureField("Password", text: $password)
                    .textFieldStyle(.plain)
                    .padding()
                    .background(BumpColors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(BumpColors.primaryText)
            }

            if let authError = appState.authErrorMessage {
                Text(authError)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            PrimaryButton(title: mode == .signUp ? "Create account" : "Continue") {
                Task {
                    if mode == .signUp {
                        await appState.signUp(
                            name: name.isEmpty ? "New User" : name,
                            username: username.isEmpty ? "bump_user" : username,
                            email: email,
                            password: password
                        )
                    } else {
                        await appState.signIn(email: email, password: password)
                    }
                }
            }
            .disabled(isSubmitDisabled)
            .opacity(isSubmitDisabled ? 0.6 : 1)

            Spacer()
        }
        .padding(20)
    }

    private var isSubmitDisabled: Bool {
        if appState.isBusy || email.isEmpty || password.count < 6 {
            return true
        }
        if mode == .signUp {
            return name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            username.trimmingCharacters(in: .whitespacesAndNewlines).count < 3
        }
        return false
    }

    private func textField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .padding()
            .background(BumpColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .foregroundStyle(BumpColors.primaryText)
    }
}
