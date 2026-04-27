import SwiftUI

struct SharedCalendarsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var selectedCalendarID: UUID?
    @State private var showCreateCalendar = false
    @State private var showAddWindow = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Shared")
                    .font(BumpTypography.screenTitle)

                SectionCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your Availability Blocks")
                            .font(BumpTypography.sectionTitle)
                        Text("Add free time blocks so Bump can find overlap with friends and groups.")
                            .foregroundStyle(BumpColors.secondaryText)

                        PrimaryButton(title: "Add free block") {
                            showAddWindow = true
                        }
                    }
                }

                SectionCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Shared Calendars")
                                .font(BumpTypography.sectionTitle)
                            Spacer()
                            Button("New") {
                                showCreateCalendar = true
                            }
                            .foregroundStyle(BumpColors.accent)
                        }

                        Toggle("Weekends only", isOn: Binding(
                            get: { appState.weekendsOnlySharedView },
                            set: { newValue in
                                appState.weekendsOnlySharedView = newValue
                                Task {
                                    await appState.loadSharedCalendars(showLoading: false)
                                }
                            }
                        ))

                        if appState.sharedCalendars.isEmpty {
                            Text("Create a friend calendar or group getaway calendar.")
                                .foregroundStyle(BumpColors.secondaryText)
                        } else {
                            ForEach(appState.sharedCalendars) { calendar in
                                Button {
                                    selectedCalendarID = calendar.id
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(calendar.title)
                                                .foregroundStyle(BumpColors.primaryText)
                                            Text(calendar.type == "group" ? "Group" : "Friend")
                                                .foregroundStyle(BumpColors.secondaryText)
                                                .font(.caption)
                                        }
                                        Spacer()
                                        if selectedCalendarID == calendar.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(BumpColors.accent)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if let selectedCalendarID,
                   let slots = appState.sharedSlotsByCalendarID[selectedCalendarID] {
                    SectionCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Shared Free Slots")
                                .font(BumpTypography.sectionTitle)

                            if slots.isEmpty {
                                Text("No overlap yet. Add more availability blocks.")
                                    .foregroundStyle(BumpColors.secondaryText)
                            } else {
                                ForEach(slots.prefix(12)) { slot in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(slot.startsAt.formatted(date: .abbreviated, time: .shortened))
                                        Text("to \(slot.endsAt.formatted(date: .omitted, time: .shortened))")
                                            .foregroundStyle(BumpColors.secondaryText)
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                    }
                }

                if let authError = appState.authErrorMessage {
                    Text(authError)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
            .padding(20)
        }
        .navigationTitle("Shared")
        .task {
            await appState.loadSharedCalendars()
            if selectedCalendarID == nil {
                selectedCalendarID = appState.sharedCalendars.first?.id
            }
        }
        .sheet(isPresented: $showCreateCalendar) {
            CreateSharedCalendarSheet()
        }
        .sheet(isPresented: $showAddWindow) {
            AddAvailabilityWindowSheet()
        }
    }
}

private struct CreateSharedCalendarSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var type = "friend"
    @State private var rawMemberIDs = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Calendar title", text: $title)
                Picker("Type", selection: $type) {
                    Text("Friend").tag("friend")
                    Text("Group").tag("group")
                }
                .pickerStyle(.segmented)

                TextField("Member UUIDs (comma separated)", text: $rawMemberIDs)

                Text("For now, add friend IDs manually. Next pass can use in-app friend picker.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("New Shared Calendar")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let memberIDs = rawMemberIDs
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .compactMap(UUID.init(uuidString:))

                        Task {
                            await appState.createSharedCalendar(title: title, memberIDs: memberIDs, type: type)
                            dismiss()
                        }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct AddAvailabilityWindowSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var startsAt = Date()
    @State private var endsAt = Date().addingTimeInterval(7200)
    @State private var note = ""
    @State private var weekendPreferred = false

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Start", selection: $startsAt)
                DatePicker("End", selection: $endsAt)
                TextField("Note (optional)", text: $note)
                Toggle("Weekend preferred", isOn: $weekendPreferred)
            }
            .navigationTitle("Add Free Block")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await appState.addAvailabilityWindow(
                                startsAt: startsAt,
                                endsAt: endsAt,
                                note: note.isEmpty ? nil : note,
                                isWeekendPreferred: weekendPreferred
                            )
                            dismiss()
                        }
                    }
                    .disabled(endsAt <= startsAt)
                }
            }
        }
    }
}
