//
//  PulseApp.swift
//  Pulse
//

import SwiftUI

@main
struct PulseApp: App {
    @State private var store = PulseStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
        }
    }
}
