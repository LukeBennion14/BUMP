import Foundation

struct BumpUser: Identifiable {
    let id: UUID
    var name: String
    var username: String
    var hobbies: [Hobby]
    var goals: [GoalInput]
}

struct Hobby: Identifiable, Hashable {
    let id: Int
    let name: String
    let prompt: String
}

struct GoalInput: Identifiable, Hashable {
    let id = UUID()
    let hobby: Hobby
    let value: String
}

struct FriendAvailability: Identifiable {
    let id: UUID
    let name: String
    let username: String
    let isFree: Bool
    let vibe: String
}

struct PlanSuggestion: Identifiable {
    let id = UUID()
    let friendName: String
    let activity: String
}

struct SharedCalendar: Identifiable {
    let id: UUID
    let title: String
    let type: String
    let memberIDs: [UUID]
}

struct AvailabilityWindow: Identifiable {
    let id: UUID
    let userID: UUID
    let startsAt: Date
    let endsAt: Date
}

struct SharedFreeSlot: Identifiable {
    let id = UUID()
    let startsAt: Date
    let endsAt: Date
    let participantCount: Int
}

enum SeedData {
    static let hobbies: [Hobby] = [
        Hobby(id: 1, name: "Movies", prompt: "What movies do you want to watch?"),
        Hobby(id: 2, name: "Hiking", prompt: "What places do you want to hike?"),
        Hobby(id: 3, name: "Food", prompt: "What restaurants do you want to try?"),
        Hobby(id: 4, name: "Sports", prompt: "What sports do you want to play?"),
        Hobby(id: 5, name: "Gym", prompt: "What gym goals are you focused on?"),
        Hobby(id: 6, name: "Board Games", prompt: "Which games do you want to play?"),
        Hobby(id: 7, name: "Travel", prompt: "Where do you want to go next?")
    ]
}
