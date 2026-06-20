import SwiftUI

@main
struct KumaYokeMeterApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var sightingStore = SightingStore()
    @StateObject private var locationManager = UserLocationManager()
    @StateObject private var tripPlanner = TripPlanner()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sightingStore)
                .environmentObject(locationManager)
                .environmentObject(tripPlanner)
                .task(id: scenePhase) {
                    guard scenePhase == .active else {
                        return
                    }
                    await sightingStore.refreshFromRemote()
                }
        }
    }
}
