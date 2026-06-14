import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                RiskDashboardView()
            }
            .tabItem {
                Label("危険度", systemImage: "gauge.with.dots.needle.67percent")
            }

            NavigationStack {
                BearMapView()
            }
            .tabItem {
                Label("地図", systemImage: "map")
            }

            NavigationStack {
                DepartureChecklistView()
            }
            .tabItem {
                Label("出発チェック", systemImage: "checklist")
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SightingStore.preview)
        .environmentObject(UserLocationManager.preview)
        .environmentObject(TripPlanner())
}

