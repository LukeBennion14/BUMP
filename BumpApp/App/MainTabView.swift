import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack { HomeView() }
                .tabItem { Label("Home", systemImage: "house.fill") }

            NavigationStack { EventsView() }
                .tabItem { Label("Events", systemImage: "calendar.badge.plus") }

            NavigationStack { MessagesView() }
                .tabItem { Label("Messages", systemImage: "message.fill") }

            NavigationStack { SharedCalendarsView() }
                .tabItem { Label("Shared", systemImage: "person.3.fill") }

            NavigationStack { BumpMapView() }
                .tabItem { Label("Map", systemImage: "map.fill") }
        }
        .tint(BumpColors.accent)
    }
}
