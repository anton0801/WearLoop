//
//  WearLoopApp.swift
//  WearLoop
//
//  Created by Anton Danilov on 6/8/26.
//

import SwiftUI

@main
struct WearLoopApp: App {
    @StateObject private var dependencies = AppDependencies.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
                .environmentObject(dependencies)
                .environmentObject(dependencies.store)
                .preferredColorScheme(.light)
                .tint(Palette.anchor)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background, .inactive:
                // Write any pending change before the app is suspended.
                dependencies.store.flush()
                dependencies.rescheduleNotifications()
            case .active:
                break
            @unknown default:
                break
            }
        }
    }
}
