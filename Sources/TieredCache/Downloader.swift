import Foundation

public enum TieredCacheError: Error {
    case badStatus(Int)
    case notHTTPResponse
    case decodeFailed
}

/// L3 网络层:下载直接落盘(不经过内存),同一资源的并发请求合并为一次下载。
actor Downloader {
    private let session: URLSession
    private var inflight: [String: Entry] = [:]

    /// 类似 SD 的 callbackTokens:每个调用者一个 waiter,全部取消时才取消真实下载。
    private struct Entry {
        let task: Task<URL, Error>
        let token = UUID()
        var waiters: Set<UUID> = []
    }

    init(session: URLSession = .shared) {
        self.session = session
    }

    func download(_ url: URL, key: CacheKey, category: CacheCategory, disk: DiskCache) async throws -> URL {
        let id = "\(category.name)/\(key.fileName)"
        let waiter = UUID()

        let task: Task<URL, Error>
        let token: UUID
        if var entry = inflight[id] {
            entry.waiters.insert(waiter)
            inflight[id] = entry
            task = entry.task
            token = entry.token
        } else {
            let session = self.session
            task = Task<URL, Error> {
                let (tmp, response) = try await session.download(from: url)
                guard let http = response as? HTTPURLResponse else { throw TieredCacheError.notHTTPResponse }
                guard (200..<300).contains(http.statusCode) else { throw TieredCacheError.badStatus(http.statusCode) }
                return try await disk.store(fileAt: tmp, for: key, category: category)
            }
            var entry = Entry(task: task)
            entry.waiters.insert(waiter)
            inflight[id] = entry
            token = entry.token
        }

        do {
            let result = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                Task { await self.release(id: id, token: token, waiter: waiter) }
            }
            release(id: id, token: token, waiter: waiter)
            // 自己已被取消时不再返回结果(其他等待者不受影响)
            try Task.checkCancellation()
            return result
        } catch {
            release(id: id, token: token, waiter: waiter)
            throw error
        }
    }

    /// 幂等。移除 waiter;若已无人等待,取消下载并清理。token 防止误删后来新建的同 id 任务。
    private func release(id: String, token: UUID, waiter: UUID) {
        guard var entry = inflight[id], entry.token == token else { return }
        entry.waiters.remove(waiter)
        if entry.waiters.isEmpty {
            entry.task.cancel()
            inflight[id] = nil
        } else {
            inflight[id] = entry
        }
    }
}
