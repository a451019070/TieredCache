import Foundation

/// L2 磁盘层。
/// - 目录:root/<category>/<hash前2位>/<hash>.<ext>
/// - 元数据直接用文件属性:创建时间判断过期,修改时间当作最近访问时间做 LRU。
/// - 写入一律"临时文件 + 原子替换",不原地修改,保证内存映射中的文件安全。
public actor DiskCache {
    public let rootURL: URL
    private let fm = FileManager.default

    public init(rootURL: URL? = nil) {
        if let rootURL {
            self.rootURL = rootURL
        } else {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            self.rootURL = caches.appendingPathComponent("TieredCache", isDirectory: true)
        }
    }

    // MARK: - Path

    private func categoryDirectory(_ category: CacheCategory) -> URL {
        rootURL.appendingPathComponent(category.name, isDirectory: true)
    }

    private func path(_ key: CacheKey, _ category: CacheCategory) -> URL {
        categoryDirectory(category)
            .appendingPathComponent(key.shard, isDirectory: true)
            .appendingPathComponent(key.fileName, isDirectory: false)
    }

    // MARK: - Query

    /// 返回有效(存在且未过期)的文件 URL,并刷新访问时间。
    public func fileURL(for key: CacheKey, category: CacheCategory) -> URL? {
        let url = path(key, category)
        guard let values = try? url.resourceValues(forKeys: [.creationDateKey]),
              values.creationDate != nil else { return nil }
        if isExpired(values.creationDate, policy: category.policy) {
            try? fm.removeItem(at: url)
            return nil
        }
        try? fm.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return url
    }

    /// 读取数据。使用内存映射,大文件不会常驻内存。
    public func data(for key: CacheKey, category: CacheCategory) -> Data? {
        guard let url = fileURL(for: key, category: category) else { return nil }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    // MARK: - Write

    @discardableResult
    public func store(_ data: Data, for key: CacheKey, category: CacheCategory) throws -> URL {
        let url = path(key, category)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// 把已下载好的临时文件移入缓存(大文件不经过内存)。
    @discardableResult
    public func store(fileAt source: URL, for key: CacheKey, category: CacheCategory) throws -> URL {
        let url = path(key, category)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: url.path) {
            _ = try fm.replaceItemAt(url, withItemAt: source)
        } else {
            try fm.moveItem(at: source, to: url)
        }
        return url
    }

    // MARK: - Remove

    public func remove(_ key: CacheKey, category: CacheCategory) {
        try? fm.removeItem(at: path(key, category))
    }

    public func removeAll(category: CacheCategory) {
        try? fm.removeItem(at: categoryDirectory(category))
    }

    public func removeAll() {
        try? fm.removeItem(at: rootURL)
    }

    // MARK: - Trim

    /// 先删过期文件;仍超容量则按最近访问时间从旧到新删,直到降到上限的一半。
    public func trim(category: CacheCategory) {
        let policy = category.policy
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey,
                                      .creationDateKey, .contentModificationDateKey]
        guard let enumerator = fm.enumerator(at: categoryDirectory(category),
                                             includingPropertiesForKeys: keys,
                                             options: [.skipsHiddenFiles]) else { return }

        struct Entry { let url: URL; let size: Int; let accessed: Date }
        var entries: [Entry] = []
        var total = 0

        for case let url as URL in enumerator {
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  v.isRegularFile == true else { continue }
            if isExpired(v.creationDate, policy: policy) {
                try? fm.removeItem(at: url)
                continue
            }
            let size = v.fileSize ?? 0
            total += size
            entries.append(Entry(url: url, size: size, accessed: v.contentModificationDate ?? .distantPast))
        }

        guard policy.diskSizeLimit > 0, total > policy.diskSizeLimit else { return }
        let target = policy.diskSizeLimit / 2
        for entry in entries.sorted(by: { $0.accessed < $1.accessed }) {
            if total <= target { break }
            try? fm.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    /// 当前分类磁盘占用(字节)。
    public func size(category: CacheCategory) -> Int {
        guard let enumerator = fm.enumerator(at: categoryDirectory(category),
                                             includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total = 0
        for case let url as URL in enumerator {
            total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
    }

    private func isExpired(_ created: Date?, policy: CachePolicy) -> Bool {
        guard policy.maxAge > 0, let created else { return false }
        return Date().timeIntervalSince(created) > policy.maxAge
    }
}
