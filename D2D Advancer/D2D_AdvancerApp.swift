//
//  D2D_AdvancerApp.swift
//  D2D Advancer
//
//  Created by Daniil Mukashev on 17/08/2025.
//

import SwiftUI

@main
struct D2D_AdvancerApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
