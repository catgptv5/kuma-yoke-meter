import SwiftUI

@main
struct KumaYokeMeterApp: App {
    @StateObject private var sightingStore = SightingStore()
    @StateObject private var locationManager = UserLocationManager()
    @StateObject private var tripPlanner = TripPlanner()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sightingStore)
                .environmentObject(locationManager)
                .environmentObject(tripPlanner)
                .task {
                    await sightingStore.refreshFromRemote()
                }
        }
    }
}
