//
//  BumpAppApp.swift
//  BumpApp
//
//  Created by Luke Bennion on 4/25/26.
//

import SwiftUI
import CoreData

@main
struct BumpAppApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
