import MapKit
import SwiftUI

struct BearMapView: View {
    @EnvironmentObject private var sightingStore: SightingStore
    @EnvironmentObject private var locationManager: UserLocationManager
    @EnvironmentObject private var tripPlanner: TripPlanner

    @State private var selectedSighting: BearSighting?
    @State private var timeFilter = MapTimeFilter.recent30
    @State private var position: MapCameraPosition = .region(.sapporoDefault)

    private var target: TripTarget? {
        tripPlanner.target(using: locationManager)
    }

    private var visibleSightings: [BearSighting] {
        switch timeFilter {
        case .recent30:
            return sightingStore.sightings.filter { sighting in
                guard let observedAt = sighting.observedAt else {
                    return false
                }
                return RiskEvaluator.daysBetween(observedAt, and: Date()) <= 30
            }
        case .all:
            return sightingStore.sightings
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $position) {
                if let target {
                    Annotation(target.name, coordinate: target.coordinate) {
                        TargetPinView()
                    }
                }

                ForEach(visibleSightings) { sighting in
                    Annotation(sighting.ward, coordinate: sighting.coordinate) {
                        Button {
                            selectedSighting = sighting
                        } label: {
                            SightingPinView(style: pinStyle(for: sighting))
                        }
                        .buttonStyle(.plain)
                    }
                }

                UserAnnotation()
            }
            .mapControls {
                MapCompass()
                MapScaleView()
                MapUserLocationButton()
            }
            .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 10) {
                Picker("表示期間", selection: $timeFilter) {
                    ForEach(MapTimeFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Label("\(visibleSightings.count)件表示", systemImage: "mappin")
                        .font(.subheadline.weight(.semibold))

                    Spacer()

                    Button {
                        focusTarget()
                    } label: {
                        Image(systemName: "scope")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("判定地点へ移動")
                }

                if timeFilter == .recent30 && visibleSightings.isEmpty {
                    Text("直近30日の同梱データはありません。必要ならデータを更新してください。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding()
        }
        .navigationTitle("地図")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedSighting) { sighting in
            SightingDetailSheet(sighting: sighting, target: target)
                .presentationDetents([.medium])
        }
        .onAppear {
            focusTarget()
        }
    }

    private func focusTarget() {
        if let target {
            position = .region(
                MKCoordinateRegion(
                    center: target.coordinate,
                    latitudinalMeters: 8_000,
                    longitudinalMeters: 8_000
                )
            )
        } else {
            position = .region(.sapporoDefault)
        }
    }

    private func pinStyle(for sighting: BearSighting) -> SightingPinStyle {
        guard let observedAt = sighting.observedAt else {
            return .older
        }

        let days = RiskEvaluator.daysBetween(observedAt, and: Date())
        if days <= 7 {
            return .lastSevenDays
        }
        if days <= 30 {
            return .lastThirtyDays
        }
        return .older
    }
}

private enum MapTimeFilter: String, CaseIterable, Identifiable {
    case recent30
    case all

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .recent30:
            return "30日"
        case .all:
            return "全件"
        }
    }
}

private enum SightingPinStyle {
    case lastSevenDays
    case lastThirtyDays
    case older

    var color: Color {
        switch self {
        case .lastSevenDays:
            return .red
        case .lastThirtyDays:
            return .orange
        case .older:
            return .gray
        }
    }

    var size: CGFloat {
        switch self {
        case .lastSevenDays:
            return 18
        case .lastThirtyDays:
            return 14
        case .older:
            return 10
        }
    }
}

private struct SightingPinView: View {
    let style: SightingPinStyle

    var body: some View {
        Circle()
            .fill(style.color)
            .frame(width: style.size, height: style.size)
            .overlay {
                Circle()
                    .stroke(.white, lineWidth: 2)
            }
            .shadow(radius: 2)
    }
}

private struct TargetPinView: View {
    var body: some View {
        Image(systemName: "scope")
            .font(.title3.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(.blue, in: Circle())
            .overlay {
                Circle()
                    .stroke(.white, lineWidth: 2)
            }
            .shadow(radius: 3)
    }
}

private struct SightingDetailSheet: View {
    let sighting: BearSighting
    let target: TripTarget?

    var body: some View {
        NavigationStack {
            List {
                Section("日時") {
                    Text(sighting.displayDateTime)
                }

                Section("場所") {
                    Text(sighting.place)
                    Text(sighting.ward)
                        .foregroundStyle(.secondary)
                }

                Section("内容") {
                    Text(sighting.detail)
                }

                if let distanceText {
                    Section("判定地点から") {
                        Text(distanceText)
                    }
                }
            }
            .navigationTitle("出没情報")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var distanceText: String? {
        guard let target else {
            return nil
        }

        let from = CLLocation(latitude: target.coordinate.latitude, longitude: target.coordinate.longitude)
        let to = CLLocation(latitude: sighting.latitude, longitude: sighting.longitude)
        let distanceKm = from.distance(from: to) / 1_000
        return String(format: "%.1fkm", distanceKm)
    }
}

private extension MKCoordinateRegion {
    static let sapporoDefault = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 43.0618, longitude: 141.3545),
        latitudinalMeters: 40_000,
        longitudinalMeters: 40_000
    )
}

#Preview {
    NavigationStack {
        BearMapView()
    }
    .environmentObject(SightingStore.preview)
    .environmentObject(UserLocationManager.preview)
    .environmentObject(TripPlanner())
}

