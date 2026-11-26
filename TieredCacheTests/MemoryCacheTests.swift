//
//  MemoryCacheTests.swift
//  TieredCacheTests
//
//  Created by ZX on 2026/11/25.
//

import Foundation
import Testing
@testable import TieredCache

struct MemoryCacheTests {
    @Test func removeAllClearsObjectsOfEveryCategory() {
        let memoryCache = MemoryCache()
        memoryCache.set("a" as NSString, cost: 1, forKey: "key", category: .tiny)
        memoryCache.set("b" as NSString, cost: 1, forKey: "key", category: .small)

        memoryCache.removeAll()

        #expect(memoryCache.object(forKey: "key", category: .tiny) == nil)
        #expect(memoryCache.object(forKey: "key", category: .small) == nil)
    }

    @Test func removeAllInOneCategoryKeepsOtherCategories() {
        let memoryCache = MemoryCache()
        memoryCache.set("a" as NSString, cost: 1, forKey: "key", category: .tiny)
        memoryCache.set("b" as NSString, cost: 1, forKey: "key", category: .small)

        memoryCache.removeAll(category: .tiny)

        #expect(memoryCache.object(forKey: "key", category: .tiny) == nil)
        #expect(memoryCache.object(forKey: "key", category: .small) != nil)
    }

    @Test func categoryWithoutMemoryLimitNeverStores() {
        let memoryCache = MemoryCache()

        memoryCache.set("a" as NSString, cost: 1, forKey: "key", category: .medium)

        #expect(memoryCache.object(forKey: "key", category: .medium) == nil)
    }

    @Test func itemLargerThanCategoryLimitIsRejected() {
        let memoryCache = MemoryCache()

        memoryCache.set("a" as NSString, cost: CacheCategory.tiny.policy.memoryTotalCostLimit + 1,
                        forKey: "key", category: .tiny)

        #expect(memoryCache.object(forKey: "key", category: .tiny) == nil)
    }
}
