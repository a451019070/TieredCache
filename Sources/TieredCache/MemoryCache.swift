import Foundation

/// L1 内存层。每个分类一个 NSCache,并带弱引用表兜底:
/// 对象被 NSCache 逐出后,只要外部(如 UIImageView)还持有,仍可命中,避免重复解码。
final class MemoryCache: @unchecked Sendable {
    private let lock = NSLock()
    private var caches: [String: NSCache<NSString, AnyObject>] = [:]
    private let weakTable = NSMapTable<NSString, AnyObject>(keyOptions: .strongMemory,
                                                            valueOptions: .weakMemory)

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
        let k = fullKey(key, category)
        let c = cache(for: category)
        if let obj = c.object(forKey: k) { return obj }
        if let obj = weakTable.object(forKey: k) {
            c.setObject(obj, forKey: k)
            return obj
        }
        return nil
    }

    func set(_ object: AnyObject, cost: Int, forKey key: String, category: CacheCategory) {
        let limit = category.policy.memoryTotalCostLimit
        guard limit > 0, cost <= limit else { return }
        lock.lock(); defer { lock.unlock() }
        let k = fullKey(key, category)
        cache(for: category).setObject(object, forKey: k, cost: cost)
        weakTable.setObject(object, forKey: k)
    }

    func remove(forKey key: String, category: CacheCategory) {
        lock.lock(); defer { lock.unlock() }
        let k = fullKey(key, category)
        cache(for: category).removeObject(forKey: k)
        weakTable.removeObject(forKey: k)
    }

    func removeAll(category: CacheCategory) {
        lock.lock(); defer { lock.unlock() }
        cache(for: category).removeAllObjects()
    }

    /// 内存警告:清空强引用缓存(弱引用表自然随对象释放而清空)。
    func removeAll() {
        lock.lock(); defer { lock.unlock() }
        caches.values.forEach { $0.removeAllObjects() }
    }
}
