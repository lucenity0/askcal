//
//  AskcalApp.swift
//  Askcal
//

import SwiftUI

@main
struct AskcalApp: App {
    @State private var store = AskcalStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
