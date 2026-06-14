import Foundation

struct RemoteSightingClient {
    enum ClientError: Error {
        case missingURL
        case invalidResponse
    }

    let urlSession: URLSession
    let remoteURL: URL?

    init(
        urlSession: URLSession = .shared,
        remoteURL: URL? = RemoteSightingClient.defaultRemoteURL
    ) {
        self.urlSession = urlSession
        self.remoteURL = remoteURL
    }

    func fetchSightings() async throws -> [BearSighting] {
        guard let remoteURL else {
            throw ClientError.missingURL
        }

        let (data, response) = try await urlSession.data(from: remoteURL)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw ClientError.invalidResponse
        }

        return try JSONDecoder().decode([BearSighting].self, from: data)
    }

    private static var defaultRemoteURL: URL? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "KumaSightingsJSONURL") as? String else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("https://"),
              !trimmed.contains("YOUR_GITHUB_USERNAME"),
              !trimmed.contains("YOUR_REPOSITORY") else {
            return nil
        }

        return URL(string: trimmed)
    }
}

