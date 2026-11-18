import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 缓存入口:内存(L1) -> 磁盘(L2) -> 网络(L3),命中后向上回填。
/// 取值接口:`url(forKey:)` 返回本地文件路径,`data(forKey:)` 返回 Data。
public final class TieredCache: @unchecked Sendable {
    public nonisolated static let shared = TieredCache()

    /// 自定义 key 生成,用于去掉 URL 中的鉴权、时间戳等易变参数。
    public var keyFilter: ((URL) -> String)?

    let memory = MemoryCache()
    public let disk: DiskCache
    private let downloader: Downloader

    private let lock = NSLock()
    private var categories: [CacheCategory] = [.tiny, .small, .medium, .large]

    public init(disk: DiskCache = DiskCache(), session: URLSession = .shared) {
        self.disk = disk
        self.downloader = Downloader(session: session)
        observeSystemEvents()
    }

    /// 注册自定义分类,使其参与定期清理。
    public func register(_ category: CacheCategory) {
        lock.lock(); defer { lock.unlock() }
        if !categories.contains(category) { categories.append(category) }
    }

    private func allCategories() -> [CacheCategory] {
        lock.lock(); defer { lock.unlock() }
        return categories
    }

    private func key(for url: URL) -> CacheKey {
        CacheKey(url: url, filter: keyFilter)
    }
}

// MARK: - 获取(本地没有则下载)

public extension TieredCache {
    /// 取 Data。内存 -> 磁盘 -> 网络,命中后向上回填。
    func data(forKey url: URL, category: CacheCategory) async throws -> Data {
        let key = key(for: url)
        let memKey = "data/\(key.fileName)"

        if let cached = memory.object(forKey: memKey, category: category) as? NSData {
            return cached as Data
        }
        if let data = await disk.data(for: key, category: category) {
            fillMemory(data, memKey: memKey, category: category)
            return data
        }
        let fileURL = try await downloader.download(url, key: key, category: category, disk: disk)
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        fillMemory(data, memKey: memKey, category: category)
        return data
    }

    /// 本地文件 URL。已缓存直接返回,否则下载到磁盘后返回。
    func url(forKey url: URL, category: CacheCategory) async throws -> URL {
        let key = key(for: url)
        if let cached = await disk.fileURL(for: key, category: category) { return cached }
        return try await downloader.download(url, key: key, category: category, disk: disk)
    }
}

// MARK: - 查询(仅查本地,不触发下载)

public extension TieredCache {
    func cachedData(forKey url: URL, category: CacheCategory) async -> Data? {
        let key = key(for: url)
        let memKey = "data/\(key.fileName)"
        if let cached = memory.object(forKey: memKey, category: category) as? NSData {
            return cached as Data
        }
        return await disk.data(for: key, category: category)
    }

    func cachedURL(forKey url: URL, category: CacheCategory) async -> URL? {
        await disk.fileURL(for: key(for: url), category: category)
    }
}

// MARK: - Store / Remove

public extension TieredCache {
    func store(_ data: Data, for url: URL, category: CacheCategory) async throws {
        let key = key(for: url)
        try await disk.store(data, for: key, category: category)
        fillMemory(data, memKey: "data/\(key.fileName)", category: category)
    }

    func remove(for url: URL, category: CacheCategory) async {
        let key = key(for: url)
        memory.remove(forKey: "data/\(key.fileName)", category: category)
        await disk.remove(key, category: category)
    }

    func removeAll(category: CacheCategory) async {
        memory.removeAll(category: category)
        await disk.removeAll(category: category)
    }

    func removeAll() async {
        memory.removeAll()
        await disk.removeAll()
    }
}

// MARK: - Maintenance

public extension TieredCache {
    /// 清理过期文件并按 LRU 控制容量。
    func trimDisk() async {
        for category in allCategories() { await disk.trim(category: category) }
    }
}

// MARK: - Internal

private extension TieredCache {
    func fillMemory(_ data: Data, memKey: String, category: CacheCategory) {
        let max = category.policy.memoryMaxItemSize
        guard max > 0, data.count <= max else { return }
        memory.set(NSData(data: data), cost: data.count, forKey: memKey, category: category)
    }

    func observeSystemEvents() {
        #if canImport(UIKit) && !os(watchOS)
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                           object: nil, queue: nil) { [weak self] _ in
            self?.memory.removeAll()
        }
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                           object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            Task.detached { await self.trimDisk() }
        }
        #endif
    }
}
