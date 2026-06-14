import SwiftUI

struct RiskDashboardView: View {
    @EnvironmentObject private var sightingStore: SightingStore
    @EnvironmentObject private var locationManager: UserLocationManager
    @EnvironmentObject private var tripPlanner: TripPlanner

    private var target: TripTarget? {
        tripPlanner.target(using: locationManager)
    }

    private var summary: RiskSummary? {
        target.map {
            RiskEvaluator.evaluate(sightings: sightingStore.sightings, target: $0)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TargetSelectionPanel()

                if let summary {
                    RiskHero(summary: summary)
                    RiskCountGrid(counts: summary.counts)
                    NearbySightingsList(sightings: summary.nearbyWithin30Days)
                    DataFreshnessNote(
                        summary: summary,
                        totalCount: sightingStore.sightings.count,
                        dataSource: sightingStore.dataSource,
                        isRefreshing: sightingStore.isRefreshing,
                        feed: sightingStore.feed
                    )
                } else {
                    MissingLocationPanel()
                }

                if let loadError = sightingStore.loadError {
                    Label(loadError, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(12)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("今日の危険度")
    }
}

private struct TargetSelectionPanel: View {
    @EnvironmentObject private var locationManager: UserLocationManager
    @EnvironmentObject private var tripPlanner: TripPlanner

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("判定地点", selection: $tripPlanner.useCurrentLocation) {
                Text("目的地").tag(false)
                Text("現在地").tag(true)
            }
            .pickerStyle(.segmented)

            if tripPlanner.useCurrentLocation {
                HStack(spacing: 12) {
                    Label(locationText, systemImage: "location")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 8)

                    Button {
                        locationManager.requestCurrentLocation()
                    } label: {
                        Label("取得", systemImage: "location.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let error = locationManager.locationError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } else {
                Picker("目的地", selection: $tripPlanner.selectedDestination) {
                    ForEach(TripDestination.presets) { destination in
                        Text(destination.name).tag(destination)
                    }
                }
                .pickerStyle(.menu)

                Text(tripPlanner.selectedDestination.note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }

    private var locationText: String {
        if let coordinate = locationManager.coordinate {
            return String(format: "現在地 %.4f, %.4f", coordinate.latitude, coordinate.longitude)
        }
        return "現在地は未取得"
    }
}

private struct MissingLocationPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("現在地が必要です", systemImage: "location.slash")
                .font(.headline)
            Text("現在地で判定する場合は、位置情報の取得を許可してください。目的地判定に戻すこともできます。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct RiskHero: View {
    let summary: RiskSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(summary.level.displayName, systemImage: summary.level.symbolName)
                    .font(.title2.bold())
                    .foregroundStyle(summary.level.tint)

                Spacer()

                Text(summary.targetName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(summary.level.guidance)
                .font(.body)
                .foregroundStyle(.primary)

            Label("安全保証なし。情報がなくても通常警戒。", systemImage: "shield.lefthalf.filled")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(summary.level.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct RiskCountGrid: View {
    let counts: [RiskBandCount]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("近くの出没件数", systemImage: "scope")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow {
                    Text("半径")
                    Text("7日")
                    Text("30日")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

                ForEach(counts) { count in
                    GridRow {
                        Text("\(Int(count.radiusKm))km")
                            .font(.subheadline.weight(.semibold))
                        CountBadge(value: count.sevenDayCount, urgent: count.radiusKm <= 3 && count.sevenDayCount > 0)
                        CountBadge(value: count.thirtyDayCount, urgent: false)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct CountBadge: View {
    let value: Int
    let urgent: Bool

    var body: some View {
        Text("\(value)件")
            .font(.subheadline.monospacedDigit().weight(.semibold))
            .foregroundStyle(urgent ? .white : .primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(urgent ? Color.red : Color(.secondarySystemGroupedBackground), in: Capsule())
    }
}

private struct NearbySightingsList: View {
    let sightings: [NearbySighting]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("直近30日・5km以内", systemImage: "mappin.and.ellipse")
                .font(.headline)

            if sightings.isEmpty {
                Text("該当する表示データはありません。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sightings.prefix(5)) { nearby in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(nearby.sighting.displayDateTime)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(String(format: "%.1fkm", nearby.distanceKm))
                                .font(.caption.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        Text(nearby.sighting.place)
                            .font(.subheadline)
                            .lineLimit(2)

                        Text(nearby.sighting.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if nearby.id != sightings.prefix(5).last?.id {
                        Divider()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct DataFreshnessNote: View {
    let summary: RiskSummary
    let totalCount: Int
    let dataSource: SightingDataSource
    let isRefreshing: Bool
    let feed: SightingFeed?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("データ: 札幌市オープンデータ \(totalCount)件", systemImage: "doc.text")
                .font(.footnote.weight(.semibold))

            Text("表示元: \(dataSource.displayName)\(isRefreshing ? "・更新確認中" : "")")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let generatedAtText {
                Text("データ生成日時: \(generatedAtText)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let latestText {
                Text("データ最終出没日: \(latestText)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(feed?.sources ?? []) { source in
                Text("\(source.name): \(source.recordCount)件 / 最新 \(source.latestSightingDate ?? "不明")")
                    .font(.caption)
                    .foregroundStyle(source.status == "ok" ? Color.secondary : Color.orange)
            }

            if let staleWarningText {
                VStack(alignment: .leading, spacing: 6) {
                    Label(staleWarningText, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)

                    Link("札幌市公式情報を確認", destination: URL(string: "https://www.city.sapporo.jp/kurashi/animal/choju/kuma/syutsubotsu/")!)
                        .font(.footnote.weight(.semibold))
                }
                .padding(.top, 4)
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
    }

    private var latestText: String? {
        if let latestSightingDate = feed?.latestSightingDate {
            return latestSightingDate
        }

        return summary.latestSightingDate.map {
            $0.formatted(date: .numeric, time: .omitted)
        }
    }

    private var generatedAtText: String? {
        guard let generatedAt = feed?.generatedAt else {
            return nil
        }

        if let date = DateParser.iso8601Date(from: generatedAt) {
            return date.formatted(date: .numeric, time: .shortened)
        }

        return generatedAt
    }

    private var staleWarningText: String? {
        guard let latestSightingDate = feed?.latestSightingDate,
              let latestDate = SightingDateParser.date(dateString: latestSightingDate, timeString: "") else {
            return nil
        }

        let staleDate = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        guard latestDate < staleDate else {
            return nil
        }

        return "注意: データ最終出没日が古いです。この日以降の情報が札幌市公式ページに掲載されている可能性があります。"
    }
}

private enum DateParser {
    static func iso8601Date(from text: String) -> Date? {
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractionalFormatter.date(from: text) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

private extension RiskLevel {
    var tint: Color {
        switch self {
        case .cancelRecommended:
            return .red
        case .highRisk:
            return .orange
        case .caution:
            return .yellow
        case .normalCaution:
            return .blue
        case .noRecentInformation:
            return .gray
        }
    }

    var symbolName: String {
        switch self {
        case .cancelRecommended:
            return "xmark.octagon.fill"
        case .highRisk:
            return "exclamationmark.triangle.fill"
        case .caution:
            return "exclamationmark.circle.fill"
        case .normalCaution:
            return "figure.walk.circle"
        case .noRecentInformation:
            return "shield.lefthalf.filled"
        }
    }
}

#Preview {
    NavigationStack {
        RiskDashboardView()
    }
    .environmentObject(SightingStore.preview)
    .environmentObject(UserLocationManager.preview)
    .environmentObject(TripPlanner())
}
