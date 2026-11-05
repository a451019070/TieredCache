import Foundation

public enum TieredCacheError: Error {
    case badStatus(Int)
    case notHTTPResponse
    case decodeFailed
}

/// L3 网络层:下载直接落盘(不经过内存),同一资源的并发请求合并为一次下载。
actor Downloader {
    private let session: URLSession
    private var inflight: [String: Task<URL, Error>] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    func download(_ url: URL, key: CacheKey, category: CacheCategory, disk: DiskCache) async throws -> URL {
        let id = "\(category.name)/\(key.fileName)"
        if let running = inflight[id] {
            return try await running.value
        }
        let session = self.session
        let task = Task<URL, Error> {
            let (tmp, response) = try await session.download(from: url)
            guard let http = response as? HTTPURLResponse else { throw TieredCacheError.notHTTPResponse }
            guard (200..<300).contains(http.statusCode) else { throw TieredCacheError.badStatus(http.statusCode) }
            return try await disk.store(fileAt: tmp, for: key, category: category)
        }
        inflight[id] = task
        defer { inflight[id] = nil }
        return try await task.value
    }
}
