import Foundation

/// 每个分类的独立策略。分类之间容量、过期互不影响。
public struct CachePolicy: Sendable {
    /// 允许进入内存层的单条原始 Data 上限(字节)。0 表示该分类永不进内存。
    public var memoryMaxItemSize: Int
    /// 该分类内存层总 cost 上限(字节)。
    public var memoryTotalCostLimit: Int
    /// 磁盘容量上限(字节)。0 表示不限制。
    public var diskSizeLimit: Int
    /// 磁盘最长保留时间(秒)。0 表示不过期。
    public var maxAge: TimeInterval

    public init(memoryMaxItemSize: Int,
                memoryTotalCostLimit: Int,
                diskSizeLimit: Int,
                maxAge: TimeInterval) {
        self.memoryMaxItemSize = memoryMaxItemSize
        self.memoryTotalCostLimit = memoryTotalCostLimit
        self.diskSizeLimit = diskSizeLimit
        self.maxAge = maxAge
    }
}

/// 缓存分类。扩展新类型(音频、zip、json...)只需再定义一个 `CacheCategory`。
public struct CacheCategory: Hashable, Sendable {
    public let name: String
    public let policy: CachePolicy

    public init(name: String, policy: CachePolicy) {
        self.name = name
        self.policy = policy
    }

    public static func == (lhs: CacheCategory, rhs: CacheCategory) -> Bool { lhs.name == rhs.name }
    public func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

public extension CacheCategory {
    private nonisolated static let kb = 1024
    private nonisolated static let mb = 1024 * 1024
    private nonisolated static let day: TimeInterval = 24 * 3600

    // MARK: - 按体积分档

    /// 极小(图标、小 JSON、配置):单条 ≤ 64KB 进内存,内存 10MB,磁盘 50MB,保留 30 天。
    nonisolated static let tiny = CacheCategory(name: "tiny", policy: CachePolicy(
        memoryMaxItemSize: 64 * kb,
        memoryTotalCostLimit: 10 * mb,
        diskSizeLimit: 50 * mb,
        maxAge: 30 * day))

    /// 小(头像、缩略图、小 SVGA):单条 ≤ 512KB 进内存,内存 40MB,磁盘 200MB,保留 14 天。
    nonisolated static let small = CacheCategory(name: "small", policy: CachePolicy(
        memoryMaxItemSize: 512 * kb,
        memoryTotalCostLimit: 40 * mb,
        diskSizeLimit: 200 * mb,
        maxAge: 14 * day))

    /// 中(大图、普通 SVGA、音频、短视频):不进内存,磁盘 500MB,保留 7 天。
    nonisolated static let medium = CacheCategory(name: "medium", policy: CachePolicy(
        memoryMaxItemSize: 0,
        memoryTotalCostLimit: 0,
        diskSizeLimit: 500 * mb,
        maxAge: 7 * day))

    /// 大(长视频、大文件):不进内存,磁盘 1GB,保留 7 天。
    nonisolated static let large = CacheCategory(name: "large", policy: CachePolicy(
        memoryMaxItemSize: 0,
        memoryTotalCostLimit: 0,
        diskSizeLimit: 1024 * mb,
        maxAge: 7 * day))

    // MARK: - 旧名称别名(兼容旧代码)

    /// 等同于 `.small`。
    nonisolated static var image: CacheCategory { .small }
    /// 等同于 `.small`。
    nonisolated static var animation: CacheCategory { .small }
    /// 等同于 `.large`。
    nonisolated static var video: CacheCategory { .large }
}
