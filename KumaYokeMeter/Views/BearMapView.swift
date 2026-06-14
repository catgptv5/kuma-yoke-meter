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

    private var visibleAssessments: [(sighting: BearSighting, assessment: SightingMapAssessment)] {
        visibleMapSightings.map {
            ($0, SightingMapAssessor.assess(sighting: $0, target: target))
        }
    }

    private var visibleMapSightings: [BearSighting] {
        visibleSightings.filter { $0.coordinate != nil }
    }

    private var elevatedRiskCount: Int {
        visibleAssessments.count {
            $0.assessment.grade == .cancelRecommended || $0.assessment.grade == .high
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

                ForEach(visibleMapSightings) { sighting in
                    if let coordinate = sighting.coordinate {
                        Annotation(sighting.displayArea, coordinate: coordinate) {
                        Button {
                            selectedSighting = sighting
                        } label: {
                            SightingPinView(
                                assessment: SightingMapAssessor.assess(sighting: sighting, target: target)
                            )
                        }
                        .buttonStyle(.plain)
                        }
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
                    Label("\(visibleMapSightings.count)件表示", systemImage: "mappin")
                        .font(.subheadline.weight(.semibold))

                    if elevatedRiskCount > 0 {
                        Label("\(elevatedRiskCount)件", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.red.opacity(0.12), in: Capsule())
                    }

                    Spacer()

                    Button {
                        focusTarget()
                    } label: {
                        Image(systemName: "scope")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("判定地点へ移動")
                }

                if timeFilter == .recent30 && visibleMapSightings.isEmpty {
                    Text("直近30日の表示データはありません。必要ならデータを更新してください。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                MapLegendView()
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

private struct SightingPinView: View {
    let assessment: SightingMapAssessment

    var body: some View {
        VStack(spacing: 2) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: assessment.kind.symbolName)
                    .font(.system(size: iconSize, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: pinSize, height: pinSize)
                    .background(pinColor, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(borderColor, lineWidth: borderWidth)
                    }
                    .shadow(color: .black.opacity(0.22), radius: 4, y: 2)

                if assessment.grade == .cancelRecommended {
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 14, height: 14)
                        .background(.red, in: Circle())
                        .overlay {
                            Circle()
                                .stroke(.white, lineWidth: 1.5)
                        }
                        .offset(x: 4, y: -4)
                }
            }

            if let label = assessment.daysAgoLabel {
                Text(label)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.regularMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(.white.opacity(0.75), lineWidth: 1)
                    }
            }
        }
        .accessibilityLabel("\(assessment.grade.displayName)、\(assessment.detailText)")
    }

    private var pinColor: Color {
        switch assessment.freshness {
        case .withinThreeDays:
            return .red
        case .withinSevenDays:
            return .orange
        case .withinThirtyDays:
            return .yellow
        case .older:
            return .gray
        case .unknown:
            return Color.secondary
        }
    }

    private var borderColor: Color {
        switch assessment.grade {
        case .cancelRecommended:
            return .red
        case .high:
            return .orange
        case .caution:
            return .white
        case .reference:
            return .white.opacity(0.75)
        }
    }

    private var borderWidth: CGFloat {
        switch assessment.grade {
        case .cancelRecommended:
            return 4
        case .high:
            return 3
        case .caution:
            return 2
        case .reference:
            return 1.5
        }
    }

    private var pinSize: CGFloat {
        switch assessment.grade {
        case .cancelRecommended:
            return 36
        case .high:
            return 32
        case .caution:
            return 28
        case .reference:
            return 24
        }
    }

    private var iconSize: CGFloat {
        switch assessment.grade {
        case .cancelRecommended:
            return 16
        case .high:
            return 15
        case .caution:
            return 13
        case .reference:
            return 12
        }
    }
}

private struct MapLegendView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                LegendDot(color: .red, text: "3日")
                LegendDot(color: .orange, text: "7日")
                LegendDot(color: .yellow, text: "30日")
                LegendDot(color: .gray, text: "古い")
            }

            HStack(spacing: 10) {
                LegendIcon(symbol: "eye.fill", text: "目撃")
                LegendIcon(symbol: "camera.fill", text: "カメラ")
                LegendIcon(symbol: "pawprint.fill", text: "痕跡")
                LegendIcon(symbol: "exclamationmark.triangle.fill", text: "被害")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LegendDot: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct LegendIcon: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 12)
            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
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

    private var assessment: SightingMapAssessment {
        SightingMapAssessor.assess(sighting: sighting, target: target)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("地図上の評価") {
                    HStack {
                        Label(assessment.grade.displayName, systemImage: assessment.kind.symbolName)
                            .font(.headline)
                            .foregroundStyle(assessment.grade.tint)

                        Spacer()

                        Text("スコア \(assessment.score)")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text(assessment.detailText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let daysAgoLabel = assessment.daysAgoLabel {
                        Text("経過: \(daysAgoLabel)")
                            .font(.subheadline)
                    }
                }

                Section("日時") {
                    Text(sighting.displayDateTime)
                }

                Section("場所") {
                    Text(sighting.displayLocation)
                    Text(sighting.displayArea)
                        .foregroundStyle(.secondary)

                    if let locationAccuracyText {
                        Text(locationAccuracyText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("内容") {
                    Text(sighting.displayDetail)
                }

                if let sourceName = sighting.sourceName {
                    Section("出典") {
                        Text(sourceName)
                        if let sourceURL = sighting.sourceURL,
                           let url = URL(string: sourceURL) {
                            Link("出典ページを開く", destination: url)
                        }
                    }
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
        guard let latitude = sighting.latitude,
              let longitude = sighting.longitude else {
            return nil
        }

        let from = CLLocation(latitude: target.coordinate.latitude, longitude: target.coordinate.longitude)
        let to = CLLocation(latitude: latitude, longitude: longitude)
        let distanceKm = from.distance(from: to) / 1_000
        return String(format: "%.1fkm", distanceKm)
    }

    private var locationAccuracyText: String? {
        guard let accuracy = sighting.locationAccuracy else {
            return nil
        }
        if let meters = sighting.locationAccuracyMeters {
            return "位置精度: \(accuracy)（目安 \(meters)m）"
        }
        return "位置精度: \(accuracy)"
    }
}

private extension MapRiskGrade {
    var tint: Color {
        switch self {
        case .cancelRecommended:
            return .red
        case .high:
            return .orange
        case .caution:
            return .yellow
        case .reference:
            return Color.secondary
        }
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
