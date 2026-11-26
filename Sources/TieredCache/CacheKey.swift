import Foundation
import CryptoKit

/// 缓存 key:SHA256 哈希 + 保留的文件扩展名(AVPlayer 等对扩展名敏感)。
public nonisolated struct CacheKey: Hashable, Sendable {
    public let hash: String
    public let fileExtension: String

    public init(_ string: String, fileExtension: String = "") {
        let digest = SHA256.hash(data: Data(string.utf8))
        self.hash = digest.map { String(format: "%02x", $0) }.joined()
        let ext = fileExtension.lowercased().filter { $0.isLetter || $0.isNumber }
        self.fileExtension = String(ext.prefix(8))
    }

    /// - Parameter filter: 自定义 key 生成,用于去掉鉴权、时间戳等易变参数。
    public init(url: URL, filter: ((URL) -> String)? = nil) {
        self.init(filter?(url) ?? url.defaultCacheKey, fileExtension: url.pathExtension)
    }

    var fileName: String { fileExtension.isEmpty ? hash : "\(hash).\(fileExtension)" }
    /// 两级目录打散,避免单目录文件过多。
    var shard: String { String(hash.prefix(2)) }
}

// MARK: - 默认 key

extension URL {
    /// 默认缓存 key。远程 URL 用 `absoluteString`;本地文件用去掉容器目录的稳定后缀。
    var defaultCacheKey: String {
        isFileURL ? localFileCacheKey : absoluteString
    }

    static let localFileCacheKeyPrefix = "tieredcache.local.cacheKey"

    /// 本地文件的稳定缓存 key(照抄 Kingfisher 的 `URL.localFileCacheKey`)。
    ///
    /// App 每次重装,系统都会给它分配新的沙盒容器目录
    /// (`/var/containers/Bundle/Application/<UUID>/`),同一个 bundle 内文件的绝对路径会整体变化。
    /// 这里只拼到 `.app` / `.appex` 目录为止的固定部分,让同一路径下的资源重装后仍命中同一份缓存。
    ///
    /// - Note: 与 Kingfisher 的差异:路径里不含 `.app` / `.appex` 时(如 Documents 下的文件),
    ///   Kingfisher 会把根分隔符 `/` 也拼进去产生 `//` 开头的字符串,这里直接丢弃根分隔符。
    ///   两者都保持了 key 的唯一性,只是后者更干净。
    var localFileCacheKey: String {
        var validComponents: [String] = []
        for part in pathComponents.reversed() {
            if part == "/" { break }
            validComponents.append(part)
            if part.hasSuffix(".app") || part.hasSuffix(".appex") { break }
        }
        let fixedPath = "\(Self.localFileCacheKeyPrefix)/\(validComponents.reversed().joined(separator: "/"))"
        if let q = query {
            return "\(fixedPath)?\(q)"
        }
        return fixedPath
    }
}
