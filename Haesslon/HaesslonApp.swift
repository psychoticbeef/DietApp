//
//  HaesslonApp.swift
//  Haesslon
//
//  Created by Daniel Arndt on 09.01.26.
//

import SwiftUI
import SwiftData

@main
struct HaesslonApp: App {
    @State private var healthManager = HealthManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(healthManager)
        }
        .modelContainer(for: [StandardBreakfast.self, FillerFood.self])
    }
}
