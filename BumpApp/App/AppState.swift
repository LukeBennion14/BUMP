import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    enum AuthState {
        case signedOut
        case onboarding
        case signedIn
    }

    @Published var authState: AuthState = .signedOut
    @Published var currentUser: BumpUser?
    @Published var freeFriends: [FriendAvailability] = []
    @Published var suggestedPlans: [PlanSuggestion] = []
    @Published var isBusy = false
    @Published var authErrorMessage: String?
    @Published var isFree = false
    @Published var freeUntil: Date = .now.addingTimeInterval(3600)
    @Published var isLoadingHome = false
    @Published var sharedCalendars: [SharedCalendar] = []
    @Published var sharedSlotsByCalendarID: [UUID: [SharedFreeSlot]] = [:]
    @Published var weekendsOnlySharedView = false

    private let supabase = SupabaseService.shared
    private let realtime = SupabaseRealtimeService.shared

    func bootstrap() {
        if supabase.hasActiveSession() {
            Task {
                await loadHomeData()
            }
        } else {
            authState = .signedOut
        }
    }

    func signUp(name: String, username: String, email: String, password: String) async {
        isBusy = true
        authErrorMessage = nil
        defer { isBusy = false }

        do {
            try await supabase.signUp(email: email, password: password, name: name, username: username)
            currentUser = BumpUser(
                id: supabase.currentUserID() ?? UUID(),
                name: name,
                username: username,
                hobbies: [],
                goals: []
            )
            authState = .onboarding
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    func signIn(email: String, password: String) async {
        isBusy = true
        authErrorMessage = nil
        defer { isBusy = false }

        do {
            try await supabase.signIn(email: email, password: password)
            currentUser = BumpUser(
                id: supabase.currentUserID() ?? UUID(),
                name: "Bump User",
                username: "bump_user",
                hobbies: [],
                goals: []
            )
            await loadHomeData()
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    func signOut() {
        realtime.disconnect()
        supabase.signOut()
        currentUser = nil
        freeFriends = []
        suggestedPlans = []
        sharedCalendars = []
        sharedSlotsByCalendarID = [:]
        authState = .signedOut
    }

    func completeOnboarding(selectedHobbies: [Hobby], goals: [GoalInput]) async {
        isBusy = true
        authErrorMessage = nil
        defer { isBusy = false }

        guard var user = currentUser else { return }

        do {
            try await supabase.saveOnboarding(hobbies: selectedHobbies, goals: goals)

            user.hobbies = selectedHobbies
            user.goals = goals
            currentUser = user
            await loadHomeData()
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    func setAvailability(isFree: Bool, freeUntil: Date) async {
        do {
            try await supabase.setAvailability(isFree: isFree, freeUntil: isFree ? freeUntil : nil)
            self.isFree = isFree
            self.freeUntil = freeUntil
            await loadHomeData(showLoading: false)
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    func loadHomeData(showLoading: Bool = true) async {
        if showLoading {
            isLoadingHome = true
        }
        authErrorMessage = nil
        defer { isLoadingHome = false }

        do {
            let data = try await supabase.fetchHomeData()
            currentUser = data.currentUser
            isFree = data.isFree
            if let freeUntil = data.freeUntil {
                self.freeUntil = freeUntil
            }
            freeFriends = data.freeFriends
            suggestedPlans = data.suggestedPlans
            authState = data.currentUser.hobbies.isEmpty ? .onboarding : .signedIn
            if authState == .signedIn {
                connectRealtimeIfNeeded()
                await loadSharedCalendars(showLoading: false)
            } else {
                realtime.disconnect()
            }
        } catch {
            if authState == .signedOut {
                authErrorMessage = error.localizedDescription
                return
            }
            authState = .onboarding
            realtime.disconnect()
        }
    }

    func loadSharedCalendars(showLoading: Bool = true) async {
        if showLoading {
            isBusy = true
        }
        defer { isBusy = false }

        do {
            let data = try await supabase.fetchSharedCalendarData(weekendsOnly: weekendsOnlySharedView)
            sharedCalendars = data.calendars
            sharedSlotsByCalendarID = data.slotsByCalendarID
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    func createSharedCalendar(title: String, memberIDs: [UUID], type: String) async {
        isBusy = true
        defer { isBusy = false }

        do {
            try await supabase.createSharedCalendar(title: title, type: type, memberIDs: memberIDs)
            await loadSharedCalendars(showLoading: false)
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    func addAvailabilityWindow(startsAt: Date, endsAt: Date, note: String?, isWeekendPreferred: Bool) async {
        isBusy = true
        defer { isBusy = false }

        do {
            try await supabase.addAvailabilityWindow(
                startsAt: startsAt,
                endsAt: endsAt,
                note: note,
                isWeekendPreferred: isWeekendPreferred
            )
            await loadSharedCalendars(showLoading: false)
        } catch {
            authErrorMessage = error.localizedDescription
        }
    }

    private func connectRealtimeIfNeeded() {
        let tables = ["availability_status", "availability_windows", "goals", "friendships", "shared_calendar_members"]
        let url = supabase.realtimeWebSocketURL()
        let accessToken = supabase.currentAccessToken()
        realtime.connect(
            websocketURL: url,
            accessToken: accessToken,
            tables: tables,
            onDatabaseChange: { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    await self.loadHomeData(showLoading: false)
                    await self.loadSharedCalendars(showLoading: false)
                }
            },
            onError: { [weak self] message in
                guard let self else { return }
                Task { @MainActor in
                    self.authErrorMessage = message
                }
            }
        )
    }
}
