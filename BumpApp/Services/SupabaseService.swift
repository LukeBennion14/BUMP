import Foundation

struct SupabaseConfig {
    let url: URL
    let anonKey: String

    static func loadFromBundle() throws -> SupabaseConfig {
        guard
            let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
            let anonKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
            let url = URL(string: urlString),
            !anonKey.isEmpty
        else {
            throw SupabaseError.missingConfig
        }
        return SupabaseConfig(url: url, anonKey: anonKey)
    }
}

enum SupabaseError: LocalizedError {
    case missingConfig
    case missingSession
    case malformedResponse
    case api(String)

    var errorDescription: String? {
        switch self {
        case .missingConfig:
            return "Missing SUPABASE_URL or SUPABASE_ANON_KEY in Info.plist."
        case .missingSession:
            return "You are not authenticated."
        case .malformedResponse:
            return "Supabase returned an unexpected response."
        case let .api(message):
            return message
        }
    }
}

struct SupabaseUser: Codable {
    let id: UUID
    let email: String?
}

struct SupabaseSession: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let user: SupabaseUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}

struct HomeDataResult {
    let currentUser: BumpUser
    let isFree: Bool
    let freeUntil: Date?
    let freeFriends: [FriendAvailability]
    let suggestedPlans: [PlanSuggestion]
}

struct SharedCalendarDataResult {
    let calendars: [SharedCalendar]
    let slotsByCalendarID: [UUID: [SharedFreeSlot]]
}

final class SupabaseService {
    static let shared = SupabaseService()

    private let sessionStoreKey = "bump.supabase.session"
    private let urlSession = URLSession.shared

    private let config: SupabaseConfig
    private(set) var session: SupabaseSession?
    private let usingFallbackConfig: Bool

    private init() {
        do {
            self.config = try SupabaseConfig.loadFromBundle()
            self.usingFallbackConfig = false
        } catch {
            // Keeps the app running in Xcode previews before keys are added.
            self.config = SupabaseConfig(url: URL(string: "https://example.supabase.co")!, anonKey: "missing-key")
            self.usingFallbackConfig = true
        }
        self.session = Self.loadSession(from: sessionStoreKey)
    }

    func hasActiveSession() -> Bool {
        session != nil
    }

    func currentUserID() -> UUID? {
        session?.user.id
    }

    func currentAccessToken() -> String? {
        session?.accessToken
    }

    func realtimeWebSocketURL() -> URL {
        if usingFallbackConfig {
            return URL(string: "wss://example.supabase.co/realtime/v1/websocket?vsn=1.0.0")!
        }
        var components = URLComponents(url: config.url, resolvingAgainstBaseURL: false)
        components?.scheme = "wss"
        components?.path = "/realtime/v1/websocket"
        components?.queryItems = [
            URLQueryItem(name: "apikey", value: config.anonKey),
            URLQueryItem(name: "vsn", value: "1.0.0")
        ]
        return components?.url ?? URL(string: "wss://example.supabase.co/realtime/v1/websocket?vsn=1.0.0")!
    }

    func signUp(email: String, password: String, name: String, username: String) async throws {
        let endpoint = config.url.appendingPathComponent("/auth/v1/signup")
        let payload: [String: String] = [
            "email": email,
            "password": password
        ]
        let sessionResponse: SupabaseSession = try await request(
            endpoint: endpoint,
            method: "POST",
            body: payload,
            authorized: false
        )
        self.session = sessionResponse
        saveSession(sessionResponse)

        try await upsertProfile(
            id: sessionResponse.user.id,
            fullName: name,
            username: username
        )
    }

    func signIn(email: String, password: String) async throws {
        let endpoint = config.url.appendingPathComponent("/auth/v1/token")
        // Supabase's GoTrue fork reads grant_type from the JSON body.
        // Kong strips URL query params before forwarding to GoTrue.
        let payload: [String: String] = [
            "grant_type": "password",
            "email": email,
            "password": password
        ]
        let sessionResponse: SupabaseSession = try await request(
            endpoint: endpoint,
            method: "POST",
            body: payload,
            authorized: false
        )
        self.session = sessionResponse
        saveSession(sessionResponse)
    }

    func signOut() {
        session = nil
        UserDefaults.standard.removeObject(forKey: sessionStoreKey)
    }

    func saveOnboarding(hobbies: [Hobby], goals: [GoalInput]) async throws {
        guard let userID = currentUserID() else { throw SupabaseError.missingSession }

        struct UserHobbyRow: Encodable {
            let user_id: UUID
            let hobby_id: Int
        }
        struct GoalRow: Encodable {
            let user_id: UUID
            let hobby_id: Int
            let goal_value: String
        }

        let userHobbyRows = hobbies.map { UserHobbyRow(user_id: userID, hobby_id: $0.id) }
        let goalRows = goals.map { GoalRow(user_id: userID, hobby_id: $0.hobby.id, goal_value: $0.value) }

        try await upsertRows(table: "user_hobbies", rows: userHobbyRows)
        try await upsertRows(table: "goals", rows: goalRows)
    }

    func setAvailability(isFree: Bool, freeUntil: Date?) async throws {
        guard let userID = currentUserID() else { throw SupabaseError.missingSession }

        struct AvailabilityRow: Encodable {
            let user_id: UUID
            let is_free: Bool
            let free_until: String?
        }

        let row = AvailabilityRow(
            user_id: userID,
            is_free: isFree,
            free_until: freeUntil?.ISO8601Format()
        )

        try await upsertRows(table: "availability_status", rows: [row])
    }

    func fetchHomeData() async throws -> HomeDataResult {
        guard let userID = currentUserID() else { throw SupabaseError.missingSession }

        let me = try await fetchProfiles(ids: [userID]).first
        guard let me else { throw SupabaseError.api("Could not load your profile.") }

        let acceptedFriendIDs = try await fetchAcceptedFriendIDs(for: userID)
        let freeAvailabilityRows = try await fetchAvailabilityRows(userIDs: acceptedFriendIDs)
            .filter { $0.is_free }
        let freeFriendIDs = freeAvailabilityRows.map(\.user_id)

        let freeFriendProfiles = try await fetchProfiles(ids: freeFriendIDs)
        let availabilityByUser = Dictionary(uniqueKeysWithValues: freeAvailabilityRows.map { ($0.user_id, $0) })

        let freeFriends: [FriendAvailability] = freeFriendProfiles.map { profile in
            let vibe = availabilityByUser[profile.id]?.vibe?.replacingOccurrences(of: "_", with: " ") ?? "open"
            return FriendAvailability(
                id: profile.id,
                name: profile.full_name,
                username: profile.username,
                isFree: true,
                vibe: vibe
            )
        }

        let myGoals = try await fetchGoals(for: userID)
        let friendGoals = try await fetchGoals(forUsers: freeFriendIDs)
        let suggestions = Self.computeSuggestions(
            currentUserGoals: myGoals,
            friendGoals: friendGoals,
            friendProfiles: freeFriendProfiles
        )

        let myAvailability = try await fetchAvailabilityRows(userIDs: [userID]).first
        let myHobbies = try await fetchUserHobbies(for: userID)
        let hobbyMap = Dictionary(uniqueKeysWithValues: SeedData.hobbies.map { ($0.id, $0) })
        let goalInputs = myGoals.compactMap { goal -> GoalInput? in
            guard let hobby = hobbyMap[goal.hobby_id] else { return nil }
            return GoalInput(hobby: hobby, value: goal.goal_value)
        }
        let hobbyInputs = myHobbies.compactMap { hobbyMap[$0.hobby_id] }

        return HomeDataResult(
            currentUser: BumpUser(
                id: me.id,
                name: me.full_name,
                username: me.username,
                hobbies: hobbyInputs,
                goals: goalInputs
            ),
            isFree: myAvailability?.is_free ?? false,
            freeUntil: Self.parseISODate(myAvailability?.free_until),
            freeFriends: freeFriends.sorted { $0.name < $1.name },
            suggestedPlans: suggestions
        )
    }

    func createSharedCalendar(title: String, type: String, memberIDs: [UUID]) async throws {
        guard let userID = currentUserID() else { throw SupabaseError.missingSession }
        let allMembers = Array(Set(memberIDs + [userID]))

        struct SharedCalendarInsert: Encodable {
            let title: String
            let type: String
            let created_by: UUID
        }
        struct SharedCalendarInsertResponse: Decodable {
            let id: UUID
        }
        struct SharedCalendarMemberInsert: Encodable {
            let calendar_id: UUID
            let user_id: UUID
            let role: String
        }

        let endpoint = config.url.appendingPathComponent("/rest/v1/shared_calendars")
        let inserted: [SharedCalendarInsertResponse] = try await request(
            endpoint: endpoint,
            method: "POST",
            body: [SharedCalendarInsert(title: title, type: type, created_by: userID)],
            authorized: true,
            additionalHeaders: ["Prefer": "return=representation"]
        )
        guard let calendarID = inserted.first?.id else {
            throw SupabaseError.api("Could not create shared calendar.")
        }

        let members = allMembers.map { memberID in
            SharedCalendarMemberInsert(
                calendar_id: calendarID,
                user_id: memberID,
                role: memberID == userID ? "owner" : "member"
            )
        }
        try await upsertRows(table: "shared_calendar_members", rows: members)
    }

    func addAvailabilityWindow(startsAt: Date, endsAt: Date, note: String?, isWeekendPreferred: Bool) async throws {
        guard let userID = currentUserID() else { throw SupabaseError.missingSession }
        struct AvailabilityWindowInsert: Encodable {
            let user_id: UUID
            let starts_at: String
            let ends_at: String
            let note: String?
            let is_weekend_preferred: Bool
        }

        let row = AvailabilityWindowInsert(
            user_id: userID,
            starts_at: startsAt.ISO8601Format(),
            ends_at: endsAt.ISO8601Format(),
            note: note,
            is_weekend_preferred: isWeekendPreferred
        )
        try await upsertRows(table: "availability_windows", rows: [row])
    }

    func fetchSharedCalendarData(daysAhead: Int = 21, weekendsOnly: Bool = false) async throws -> SharedCalendarDataResult {
        guard let userID = currentUserID() else { throw SupabaseError.missingSession }
        let persistedCalendars = try await fetchSharedCalendars(for: userID)
        let members = try await fetchSharedCalendarMembers(calendarIDs: persistedCalendars.map(\.id))
        let memberIDs = Array(Set(members.map(\.user_id)))
        let friendIDs = try await fetchAcceptedFriendIDs(for: userID)
        let friendProfiles = try await fetchProfiles(ids: friendIDs)

        let existingPairs = Set(
            persistedCalendars
                .filter { $0.type == "friend" }
                .map { Set($0.memberIDs) }
        )
        let autoFriendCalendars: [SharedCalendar] = friendProfiles.compactMap { profile in
            let pair = Set([userID, profile.id])
            guard !existingPairs.contains(pair) else { return nil }
            return SharedCalendar(
                id: profile.id,
                title: "You + \(profile.nameOrUsername)",
                type: "friend",
                memberIDs: [userID, profile.id]
            )
        }
        let calendars = persistedCalendars + autoFriendCalendars

        let now = Date()
        let upperBound = Calendar.current.date(byAdding: .day, value: daysAhead, to: now) ?? now
        let windows = try await fetchAvailabilityWindows(
            userIDs: Array(Set(memberIDs + friendIDs + [userID])),
            from: now,
            to: upperBound
        )

        let membersByCalendar = Dictionary(grouping: members, by: \.calendar_id)
        let windowsByUser = Dictionary(grouping: windows, by: \.user_id)

        var slotsByCalendarID: [UUID: [SharedFreeSlot]] = [:]
        for calendar in calendars {
            let explicitMembers = membersByCalendar[calendar.id]?.map(\.user_id) ?? []
            let memberList = explicitMembers.isEmpty ? calendar.memberIDs : explicitMembers
            guard !memberList.isEmpty else {
                slotsByCalendarID[calendar.id] = []
                continue
            }
            let windowsPerMember: [[AvailabilityWindow]] = memberList.map { memberID in
                (windowsByUser[memberID] ?? []).map { row in
                    AvailabilityWindow(
                        id: row.id,
                        userID: row.user_id,
                        startsAt: Self.parseISODate(row.starts_at) ?? now,
                        endsAt: Self.parseISODate(row.ends_at) ?? now
                    )
                }
            }
            let overlap = Self.computeOverlaps(windowsPerMember, weekendsOnly: weekendsOnly)
            slotsByCalendarID[calendar.id] = overlap
        }

        return SharedCalendarDataResult(calendars: calendars, slotsByCalendarID: slotsByCalendarID)
    }

    private func upsertProfile(id: UUID, fullName: String, username: String) async throws {
        struct ProfileRow: Encodable {
            let id: UUID
            let full_name: String
            let username: String
        }

        let payload = [
            ProfileRow(
                id: id,
                full_name: fullName,
                username: username
            )
        ]
        try await upsertRows(table: "profiles", rows: payload)
    }

    private func upsertRows<T: Encodable>(table: String, rows: [T]) async throws {
        guard !rows.isEmpty else { return }
        let endpoint = config.url.appendingPathComponent("/rest/v1/\(table)")
        _ = try await requestRaw(
            endpoint: endpoint,
            method: "POST",
            body: rows,
            authorized: true,
            additionalHeaders: [
                "Prefer": "resolution=merge-duplicates,return=minimal"
            ]
        )
    }

    private func getRows<Response: Decodable>(path: String, queryItems: [URLQueryItem]) async throws -> [Response] {
        var components = URLComponents(url: config.url.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        guard let endpoint = components?.url else {
            throw SupabaseError.api("Could not build Supabase request URL.")
        }
        let data = try await requestRaw(
            endpoint: endpoint,
            method: "GET",
            body: Optional<String>.none,
            authorized: true,
            additionalHeaders: [:]
        )
        do {
            return try JSONDecoder().decode([Response].self, from: data)
        } catch {
            throw SupabaseError.malformedResponse
        }
    }

    private func request<Response: Decodable, Body: Encodable>(
        endpoint: URL,
        method: String,
        body: Body?,
        authorized: Bool,
        additionalHeaders: [String: String] = [:]
    ) async throws -> Response {
        let data = try await requestRaw(
            endpoint: endpoint,
            method: method,
            body: body,
            authorized: authorized,
            additionalHeaders: additionalHeaders
        )
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw SupabaseError.malformedResponse
        }
    }

    private func requestRaw<Body: Encodable>(
        endpoint: URL,
        method: String,
        body: Body?,
        authorized: Bool,
        additionalHeaders: [String: String]
    ) async throws -> Data {
        if usingFallbackConfig {
            throw SupabaseError.missingConfig
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        additionalHeaders.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        if authorized {
            guard let token = session?.accessToken else { throw SupabaseError.missingSession }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SupabaseError.malformedResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let message = (object["msg"] as? String) ?? (object["error_description"] as? String) ?? (object["message"] as? String)
            {
                throw SupabaseError.api(message)
            }
            throw SupabaseError.api("Request failed with status \(http.statusCode).")
        }
        return data
    }

    private func fetchAcceptedFriendIDs(for userID: UUID) async throws -> [UUID] {
        struct FriendshipRow: Decodable {
            let requester_id: UUID
            let addressee_id: UUID
        }
        let rows: [FriendshipRow] = try await getRows(
            path: "/rest/v1/friendships",
            queryItems: [
                URLQueryItem(name: "select", value: "requester_id,addressee_id"),
                URLQueryItem(name: "status", value: "eq.accepted"),
                URLQueryItem(
                    name: "or",
                    value: "(requester_id.eq.\(userID.uuidString),addressee_id.eq.\(userID.uuidString))"
                )
            ]
        )
        return rows.map { row in
            row.requester_id == userID ? row.addressee_id : row.requester_id
        }
    }

    private func fetchSharedCalendars(for userID: UUID) async throws -> [SharedCalendar] {
        let memberships: [SharedCalendarMemberRow] = try await getRows(
            path: "/rest/v1/shared_calendar_members",
            queryItems: [
                URLQueryItem(name: "select", value: "calendar_id,user_id,role"),
                URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)")
            ]
        )
        let calendarIDs = memberships.map(\.calendar_id)
        guard !calendarIDs.isEmpty else { return [] }
        let list = calendarIDs.map(\.uuidString).joined(separator: ",")
        let rows: [SharedCalendarRow] = try await getRows(
            path: "/rest/v1/shared_calendars",
            queryItems: [
                URLQueryItem(name: "select", value: "id,title,type"),
                URLQueryItem(name: "id", value: "in.(\(list))")
            ]
        )
        let allMembers = try await fetchSharedCalendarMembers(calendarIDs: calendarIDs)
        let memberIDsByCalendar = Dictionary(grouping: allMembers, by: \.calendar_id).mapValues { rows in
            rows.map(\.user_id)
        }
        return rows.map { row in
            SharedCalendar(
                id: row.id,
                title: row.title,
                type: row.type,
                memberIDs: memberIDsByCalendar[row.id] ?? []
            )
        }.sorted { $0.title < $1.title }
    }

    private func fetchSharedCalendarMembers(calendarIDs: [UUID]) async throws -> [SharedCalendarMemberRow] {
        guard !calendarIDs.isEmpty else { return [] }
        let list = calendarIDs.map(\.uuidString).joined(separator: ",")
        return try await getRows(
            path: "/rest/v1/shared_calendar_members",
            queryItems: [
                URLQueryItem(name: "select", value: "calendar_id,user_id,role"),
                URLQueryItem(name: "calendar_id", value: "in.(\(list))")
            ]
        )
    }

    private func fetchAvailabilityWindows(userIDs: [UUID], from: Date, to: Date) async throws -> [AvailabilityWindowRow] {
        guard !userIDs.isEmpty else { return [] }
        let list = userIDs.map(\.uuidString).joined(separator: ",")
        return try await getRows(
            path: "/rest/v1/availability_windows",
            queryItems: [
                URLQueryItem(name: "select", value: "id,user_id,starts_at,ends_at"),
                URLQueryItem(name: "user_id", value: "in.(\(list))"),
                URLQueryItem(name: "starts_at", value: "lte.\(to.ISO8601Format())"),
                URLQueryItem(name: "ends_at", value: "gte.\(from.ISO8601Format())"),
                URLQueryItem(name: "order", value: "starts_at.asc")
            ]
        )
    }

    private func fetchProfiles(ids: [UUID]) async throws -> [ProfileRow] {
        guard !ids.isEmpty else { return [] }
        let list = ids.map(\.uuidString).joined(separator: ",")
        return try await getRows(
            path: "/rest/v1/profiles",
            queryItems: [
                URLQueryItem(name: "select", value: "id,full_name,username"),
                URLQueryItem(name: "id", value: "in.(\(list))")
            ]
        )
    }

    private func fetchAvailabilityRows(userIDs: [UUID]) async throws -> [AvailabilityReadRow] {
        guard !userIDs.isEmpty else { return [] }
        let list = userIDs.map(\.uuidString).joined(separator: ",")
        return try await getRows(
            path: "/rest/v1/availability_status",
            queryItems: [
                URLQueryItem(name: "select", value: "user_id,is_free,free_until,vibe"),
                URLQueryItem(name: "user_id", value: "in.(\(list))")
            ]
        )
    }

    private func fetchGoals(for userID: UUID) async throws -> [GoalReadRow] {
        try await getRows(
            path: "/rest/v1/goals",
            queryItems: [
                URLQueryItem(name: "select", value: "user_id,hobby_id,goal_value"),
                URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)")
            ]
        )
    }

    private func fetchGoals(forUsers userIDs: [UUID]) async throws -> [GoalReadRow] {
        guard !userIDs.isEmpty else { return [] }
        let list = userIDs.map(\.uuidString).joined(separator: ",")
        return try await getRows(
            path: "/rest/v1/goals",
            queryItems: [
                URLQueryItem(name: "select", value: "user_id,hobby_id,goal_value"),
                URLQueryItem(name: "user_id", value: "in.(\(list))")
            ]
        )
    }

    private func fetchUserHobbies(for userID: UUID) async throws -> [UserHobbyReadRow] {
        try await getRows(
            path: "/rest/v1/user_hobbies",
            queryItems: [
                URLQueryItem(name: "select", value: "hobby_id"),
                URLQueryItem(name: "user_id", value: "eq.\(userID.uuidString)")
            ]
        )
    }

    private static func computeSuggestions(
        currentUserGoals: [GoalReadRow],
        friendGoals: [GoalReadRow],
        friendProfiles: [ProfileRow]
    ) -> [PlanSuggestion] {
        let normalizedCurrentGoals = Set(currentUserGoals.map {
            "\($0.hobby_id)|\($0.goal_value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
        })
        let nameByFriendID = Dictionary(uniqueKeysWithValues: friendProfiles.map { ($0.id, $0.full_name) })

        var suggestions: [PlanSuggestion] = []
        var seen = Set<String>()
        for goal in friendGoals {
            let normalized = "\(goal.hobby_id)|\(goal.goal_value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
            guard normalizedCurrentGoals.contains(normalized) else { continue }
            guard let friendName = nameByFriendID[goal.user_id] else { continue }

            let key = "\(goal.user_id.uuidString)|\(normalized)"
            guard !seen.contains(key) else { continue }
            seen.insert(key)

            suggestions.append(
                PlanSuggestion(
                    friendName: friendName,
                    activity: goal.goal_value
                )
            )
        }
        return suggestions.sorted { $0.friendName < $1.friendName }
    }

    private static func parseISODate(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func computeOverlaps(_ memberWindows: [[AvailabilityWindow]], weekendsOnly: Bool) -> [SharedFreeSlot] {
        guard var overlap = memberWindows.first?.map({ DateInterval(start: $0.startsAt, end: $0.endsAt) }), !overlap.isEmpty else {
            return []
        }

        for windows in memberWindows.dropFirst() {
            let intervals = windows.map { DateInterval(start: $0.startsAt, end: $0.endsAt) }
            overlap = intersectIntervals(overlap, intervals)
            if overlap.isEmpty { break }
        }

        let calendar = Calendar.current
        let filtered = overlap.filter { interval in
            !weekendsOnly || calendar.isDateInWeekend(interval.start)
        }

        return filtered.map {
            SharedFreeSlot(
                startsAt: $0.start,
                endsAt: $0.end,
                participantCount: memberWindows.count
            )
        }
    }

    private static func intersectIntervals(_ a: [DateInterval], _ b: [DateInterval]) -> [DateInterval] {
        var i = 0
        var j = 0
        let left = a.sorted { $0.start < $1.start }
        let right = b.sorted { $0.start < $1.start }
        var result: [DateInterval] = []

        while i < left.count, j < right.count {
            let start = max(left[i].start, right[j].start)
            let end = min(left[i].end, right[j].end)
            if start < end {
                result.append(DateInterval(start: start, end: end))
            }
            if left[i].end < right[j].end {
                i += 1
            } else {
                j += 1
            }
        }
        return result
    }

    private func saveSession(_ session: SupabaseSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        UserDefaults.standard.set(data, forKey: sessionStoreKey)
    }

    private static func loadSession(from key: String) -> SupabaseSession? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SupabaseSession.self, from: data)
    }
}

private struct ProfileRow: Decodable {
    let id: UUID
    let full_name: String
    let username: String

    var nameOrUsername: String {
        if full_name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return username
        }
        return full_name
    }
}

private struct AvailabilityReadRow: Decodable {
    let user_id: UUID
    let is_free: Bool
    let free_until: String?
    let vibe: String?
}

private struct GoalReadRow: Decodable {
    let user_id: UUID
    let hobby_id: Int
    let goal_value: String
}

private struct UserHobbyReadRow: Decodable {
    let hobby_id: Int
}

private struct SharedCalendarRow: Decodable {
    let id: UUID
    let title: String
    let type: String
}

private struct SharedCalendarMemberRow: Decodable {
    let calendar_id: UUID
    let user_id: UUID
    let role: String
}

private struct AvailabilityWindowRow: Decodable {
    let id: UUID
    let user_id: UUID
    let starts_at: String
    let ends_at: String
}
