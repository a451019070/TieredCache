import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// URL 的便捷写法,固定使用 `TieredCache.shared`。
/// 需要自定义实例时,直接调用 `TieredCache` 本身。
public extension URL {
    // MARK: 获取(本地没有则下载)

    func loadData(category: CacheCategory) async throws -> Data {
        try await TieredCache.shared.data(forKey: self, category: category)
    }

    func loadFileURL(category: CacheCategory) async throws -> URL {
        try await TieredCache.shared.url(forKey: self, category: category)
    }

    #if canImport(UIKit)
    func loadImage(category: CacheCategory = .small) async throws -> UIImage {
        try await TieredCache.shared.image(forKey: self, category: category)
    }
    #endif

    // MARK: 查询(仅查本地,不触发下载)

    func cachedData(category: CacheCategory) async -> Data? {
        await TieredCache.shared.cachedData(forKey: self, category: category)
    }

    func cachedFileURL(category: CacheCategory) async -> URL? {
        await TieredCache.shared.cachedURL(forKey: self, category: category)
    }

    #if canImport(UIKit)
    func cachedImage(category: CacheCategory = .small) async -> UIImage? {
        await TieredCache.shared.cachedImage(forKey: self, category: category)
    }
    #endif
}
