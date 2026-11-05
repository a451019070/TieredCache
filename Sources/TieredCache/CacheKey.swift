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
        self.init(filter?(url) ?? url.absoluteString, fileExtension: url.pathExtension)
    }

    var fileName: String { fileExtension.isEmpty ? hash : "\(hash).\(fileExtension)" }
    /// 两级目录打散,避免单目录文件过多。
    var shard: String { String(hash.prefix(2)) }
}
