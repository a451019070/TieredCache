import Foundation

/// L1 内存层。每个分类一个 NSCache,按 cost 限制容量,系统内存紧张时由 NSCache 自动淘汰。
final class MemoryCache: @unchecked Sendable {
    private let lock = NSLock()
    private var caches: [String: NSCache<NSString, AnyObject>] = [:]

    private func cache(for category: CacheCategory) -> NSCache<NSString, AnyObject> {
        if let c = caches[category.name] { return c }
        let c = NSCache<NSString, AnyObject>()
        c.totalCostLimit = category.policy.memoryTotalCostLimit
        caches[category.name] = c
        return c
    }

    private func fullKey(_ key: String, _ category: CacheCategory) -> NSString {
        "\(category.name)/\(key)" as NSString
    }

    func object(forKey key: String, category: CacheCategory) -> AnyObject? {
        guard category.policy.memoryTotalCostLimit > 0 else { return nil }
        lock.lock(); defer { lock.unlock() }
        return cache(for: category).object(forKey: fullKey(key, category))
    }

    func set(_ object: AnyObject, cost: Int, forKey key: String, category: CacheCategory) {
        let limit = category.policy.memoryTotalCostLimit
        guard limit > 0, cost <= limit else { return }
        lock.lock(); defer { lock.unlock() }
        cache(for: category).setObject(object, forKey: fullKey(key, category), cost: cost)
    }

    func remove(forKey key: String, category: CacheCategory) {
        lock.lock(); defer { lock.unlock() }
        cache(for: category).removeObject(forKey: fullKey(key, category))
    }

    func removeAll(category: CacheCategory) {
        lock.lock(); defer { lock.unlock() }
        cache(for: category).removeAllObjects()
    }

    /// 内存警告:清空所有分类的缓存。
    func removeAll() {
        lock.lock(); defer { lock.unlock() }
        caches.values.forEach { $0.removeAllObjects() }
    }
}
