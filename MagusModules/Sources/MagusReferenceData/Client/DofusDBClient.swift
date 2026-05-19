import Foundation
import MagusCommon
import os

public enum DofusDBError: Error, Sendable {
    case invalidURL
    case httpError(status: Int)
    case decoding(underlying: String)
    case network(underlying: String)
}

/// Client HTTP pour api.dofusdb.fr.
/// Gère la pagination (`$limit`, `$skip`) et les retries.
public actor DofusDBClient {

    public static let defaultBaseURL = URL(string: "https://api.dofusdb.fr")!
    public static let defaultPageSize = 50

    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let logger = MagusLogger.persistence

    public init(baseURL: URL = DofusDBClient.defaultBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    // MARK: - Version

    public func fetchVersion() async throws -> String {
        let url = baseURL.appendingPathComponent("version")
        let data = try await fetchData(from: url)
        // L'API retourne du JSON-string brut : `"3.5.16.20"`
        if let s = try? decoder.decode(String.self, from: data) {
            return s
        }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? ""
    }

    // MARK: - Collections paginées

    public func fetchAllCharacteristics(
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [DofusDBCharacteristic] {
        try await fetchAll(path: "characteristics", query: [:], progress: progress)
    }

    public func fetchAllItemTypes(
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [DofusDBItemType] {
        try await fetchAll(path: "item-types", query: [:], progress: progress)
    }

    public func fetchAllEffects(
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [DofusDBEffect] {
        try await fetchAll(path: "effects", query: [:], progress: progress)
    }

    /// Récupère uniquement les items dont le typeId est dans `typeIds` (utile pour
    /// limiter aux types mageables : anneau, amulette, ceinture, etc.).
    public func fetchItems(
        typeIds: [Int],
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [DofusDBItem] {
        var query: [String: String] = [:]
        // Feathers.js : `?typeId[$in][]=1&typeId[$in][]=9...`
        for (i, id) in typeIds.enumerated() {
            query["typeId[$in][\(i)]"] = String(id)
        }
        return try await fetchAll(path: "items", query: query, progress: progress)
    }

    public func fetchAllItems(
        progress: (@Sendable (Int, Int) -> Void)? = nil
    ) async throws -> [DofusDBItem] {
        try await fetchAll(path: "items", query: [:], progress: progress)
    }

    // MARK: - Pagination générique

    private func fetchAll<T: Decodable & Sendable>(
        path: String,
        query: [String: String],
        pageSize: Int = DofusDBClient.defaultPageSize,
        progress: (@Sendable (Int, Int) -> Void)?
    ) async throws -> [T] {
        var collected: [T] = []
        var skip = 0

        // Premier appel pour récupérer le total
        let first: DofusDBPaginated<T> = try await fetchPage(path: path, query: query, limit: pageSize, skip: 0)
        collected.append(contentsOf: first.data)
        let total = first.total
        progress?(collected.count, total)
        skip += pageSize

        while skip < total {
            try Task.checkCancellation()
            let page: DofusDBPaginated<T> = try await fetchPage(path: path, query: query, limit: pageSize, skip: skip)
            collected.append(contentsOf: page.data)
            progress?(collected.count, total)
            skip += pageSize
        }

        logger.info("DofusDB \(path, privacy: .public): fetched \(collected.count)/\(total)")
        return collected
    }

    private func fetchPage<T: Decodable & Sendable>(
        path: String,
        query: [String: String],
        limit: Int,
        skip: Int
    ) async throws -> DofusDBPaginated<T> {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        var items: [URLQueryItem] = [
            URLQueryItem(name: "$limit", value: String(limit)),
            URLQueryItem(name: "$skip", value: String(skip)),
        ]
        for (k, v) in query.sorted(by: { $0.key < $1.key }) {
            items.append(URLQueryItem(name: k, value: v))
        }
        components?.queryItems = items
        guard let url = components?.url else { throw DofusDBError.invalidURL }

        let data = try await fetchData(from: url)
        do {
            return try decoder.decode(DofusDBPaginated<T>.self, from: data)
        } catch {
            throw DofusDBError.decoding(underlying: error.localizedDescription)
        }
    }

    private func fetchData(from url: URL) async throws -> Data {
        var attempt = 0
        let maxAttempts = 3
        while true {
            attempt += 1
            do {
                let (data, response) = try await session.data(from: url)
                guard let http = response as? HTTPURLResponse else {
                    throw DofusDBError.network(underlying: "Réponse non-HTTP")
                }
                guard (200..<300).contains(http.statusCode) else {
                    if http.statusCode >= 500, attempt < maxAttempts {
                        try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 200_000_000))
                        continue
                    }
                    throw DofusDBError.httpError(status: http.statusCode)
                }
                return data
            } catch let error as DofusDBError {
                throw error
            } catch {
                if attempt < maxAttempts {
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 200_000_000))
                    continue
                }
                throw DofusDBError.network(underlying: error.localizedDescription)
            }
        }
    }
}
