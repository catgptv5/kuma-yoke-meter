import Combine
import Foundation

enum SightingDataSource {
    case bundled
    case cache
    case remote

    var displayName: String {
        switch self {
        case .bundled:
            return "同梱JSON"
        case .cache:
            return "キャッシュ"
        case .remote:
            return "GitHub Pages"
        }
    }
}

@MainActor
final class SightingStore: ObservableObject {
    @Published private(set) var sightings: [BearSighting] = []
    @Published private(set) var loadError: String?
    @Published private(set) var dataSource: SightingDataSource = .bundled
    @Published private(set) var isRefreshing = false

    private let remoteClient: RemoteSightingClient
    private let cacheURL: URL

    init(
        loadImmediately: Bool = true,
        remoteClient: RemoteSightingClient = RemoteSightingClient()
    ) {
        self.remoteClient = remoteClient
        cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("bear_sightings_cache.json")

        if loadImmediately {
            loadBestLocalData()
        }
    }

    func loadBestLocalData() {
        if loadCachedData() {
            return
        }

        loadBundledData()
    }

    func refreshFromRemote() async {
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let remoteSightings = try await remoteClient.fetchSightings()
            try saveCache(remoteSightings)
            sightings = remoteSightings
            dataSource = .remote
            loadError = nil
        } catch {
            if sightings.isEmpty {
                loadBestLocalData()
            }
            loadError = "最新データを取得できませんでした。\(dataSource.displayName)を表示しています。"
        }
    }

    private func loadBundledData() {
        guard let url = Bundle.main.url(forResource: "bear_sightings", withExtension: "json") else {
            loadError = "bear_sightings.json がアプリ内に見つかりません。"
            sightings = []
            return
        }

        do {
            let data = try Data(contentsOf: url)
            sightings = try JSONDecoder().decode([BearSighting].self, from: data)
            dataSource = .bundled
            loadError = nil
        } catch {
            sightings = []
            loadError = "ヒグマ出没データを読み込めませんでした: \(error.localizedDescription)"
        }
    }

    private func loadCachedData() -> Bool {
        do {
            let data = try Data(contentsOf: cacheURL)
            sightings = try JSONDecoder().decode([BearSighting].self, from: data)
            dataSource = .cache
            loadError = nil
            return true
        } catch {
            return false
        }
    }

    private func saveCache(_ sightings: [BearSighting]) throws {
        let data = try JSONEncoder().encode(sightings)
        try data.write(to: cacheURL, options: [.atomic])
    }
}

extension SightingStore {
    static var preview: SightingStore {
        let store = SightingStore(loadImmediately: false)
        store.sightings = [
            BearSighting(
                id: "preview-1",
                date: "2026-06-10",
                time: "16:05",
                ward: "中央区",
                place: "中央区盤渓付近",
                latitude: 43.0471,
                longitude: 141.2776,
                detail: "ヒグマを目撃",
                sourceYear: 2026
            ),
            BearSighting(
                id: "preview-2",
                date: "2026-06-03",
                time: "05:20",
                ward: "南区",
                place: "南区定山渓付近",
                latitude: 42.9669,
                longitude: 141.1668,
                detail: "足跡を確認",
                sourceYear: 2026
            )
        ]
        return store
    }
}
