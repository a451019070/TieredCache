//
//  TieredCacheTests.swift
//  TieredCacheTests
//
//  Created by ZX on 2026/10/15.
//

import Foundation
import Testing
@testable import TieredCache

// MARK: - 默认 key:远程 URL

struct CacheKeyRemoteURLTests {

    @Test func `远程 URL 使用 absoluteString`() {
        let url = URL(string: "https://cdn.com/a/b.png?x=1&sign=abc#frag")!
        #expect(url.defaultCacheKey == url.absoluteString)
        #expect(CacheKey(url: url) == CacheKey(url.absoluteString, fileExtension: "png"))
    }

    @Test func `远程 URL 不同则 key 不同`() {
        let a = URL(string: "https://cdn.com/a.png")!
        let b = URL(string: "https://cdn.com/b.png")!
        #expect(CacheKey(url: a) != CacheKey(url: b))
    }

    @Test func `远程 URL 的 fileExtension 取自 path`() {
        #expect(CacheKey(url: URL(string: "https://cdn.com/x.JPG")!).fileExtension == "jpg")
        #expect(CacheKey(url: URL(string: "https://cdn.com/x")!).fileExtension == "")
    }
}

// MARK: - 默认 key:本地文件

struct LocalFileCacheKeyTests {

    private func fileURL(_ path: String, query: String? = nil) -> URL {
        var c = URLComponents()
        c.scheme = "file"
        c.path = path
        c.query = query
        return c.url!
    }

    @Test func `bundle 内文件剥掉容器目录`() {
        let u = fileURL("/var/containers/Bundle/Application/1111-AAAA/MyApp.app/Assets.xcassets/a.png")
        #expect(u.localFileCacheKey == "tieredcache.local.cacheKey/MyApp.app/Assets.xcassets/a.png")
    }

    @Test func `容器 UUID 变化后 key 不变`() {
        let a = fileURL("/var/containers/Bundle/Application/1111-AAAA/MyApp.app/img/a.png")
        let b = fileURL("/var/containers/Bundle/Application/2222-BBBB/MyApp.app/img/a.png")
        #expect(a.localFileCacheKey == b.localFileCacheKey)
        #expect(CacheKey(url: a) == CacheKey(url: b))
    }

    @Test func `扩展 appex 同样剥掉容器目录`() {
        let a = fileURL("/var/containers/Bundle/Application/1111/MyApp.app/PlugIns/Share.appex/icon.png")
        let b = fileURL("/var/containers/Bundle/Application/2222/MyApp.app/PlugIns/Share.appex/icon.png")
        #expect(a.localFileCacheKey == "tieredcache.local.cacheKey/Share.appex/icon.png")
        #expect(CacheKey(url: a) == CacheKey(url: b))
    }

    @Test func `不同 App 不会撞 key`() {
        let a = fileURL("/var/containers/Bundle/Application/1111/MyApp.app/img/a.png")
        let b = fileURL("/var/containers/Bundle/Application/1111/OtherApp.app/img/a.png")
        #expect(CacheKey(url: a) != CacheKey(url: b))
    }

    @Test func `同一 bundle 内不同文件 key 不同`() {
        let a = fileURL("/var/containers/Bundle/Application/1111/MyApp.app/img/a.png")
        let b = fileURL("/var/containers/Bundle/Application/1111/MyApp.app/img/b.png")
        #expect(CacheKey(url: a) != CacheKey(url: b))
    }

    @Test func `路径不含 app 时保留完整路径且无多余根分隔符`() {
        let u = fileURL("/var/mobile/Containers/Data/Application/9999/Documents/a.json")
        #expect(u.localFileCacheKey == "tieredcache.local.cacheKey/var/mobile/Containers/Data/Application/9999/Documents/a.json")
        #expect(!u.localFileCacheKey.contains("//"))
    }

    @Test func `query 参与本地文件 key`() {
        let a = fileURL("/var/containers/Bundle/Application/1/MyApp.app/a.png", query: "v=1")
        let b = fileURL("/var/containers/Bundle/Application/1/MyApp.app/a.png", query: "v=2")
        #expect(a.localFileCacheKey.hasSuffix("?v=1"))
        #expect(CacheKey(url: a) != CacheKey(url: b))
    }

    @Test func `本地文件的 fileExtension 取自 path`() {
        let u = fileURL("/var/containers/Bundle/Application/1/MyApp.app/a.png")
        #expect(CacheKey(url: u).fileExtension == "png")
    }
}

// MARK: - filter 优先级

struct CacheKeyFilterTests {

    @Test func `filter 覆盖默认规则`() {
        let u = URL(string: "https://cdn.com/a.png?Expires=1&Signature=abc")!
        let key = CacheKey(url: u) { _ in "fixed" }
        #expect(key == CacheKey("fixed", fileExtension: "png"))
    }

    @Test func `filter 对本地文件同样生效`() {
        var c = URLComponents()
        c.scheme = "file"
        c.path = "/var/containers/Bundle/Application/1111/MyApp.app/a.png"
        let u = c.url!
        #expect(CacheKey(url: u) { _ in "custom" } == CacheKey("custom", fileExtension: "png"))
    }
}

// MARK: - 端到端:不同容器路径落到同一个磁盘文件

struct ContainerMigrationDiskTests {

    @Test func `重装前后写入与读取共享同一份磁盘文件`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TieredCacheTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let disk = DiskCache(rootURL: root)
        let payload = Data("hello".utf8)

        var before = URLComponents()
        before.scheme = "file"
        before.path = "/var/containers/Bundle/Application/1111-OLD/MyApp.app/img/a.png"

        var after = URLComponents()
        after.scheme = "file"
        after.path = "/var/containers/Bundle/Application/2222-NEW/MyApp.app/img/a.png"

        try await disk.store(payload, for: CacheKey(url: before.url!), category: .tiny)

        let hit = await disk.fileURL(for: CacheKey(url: after.url!), category: .tiny)
        #expect(hit != nil)

        let data = await disk.data(for: CacheKey(url: after.url!), category: .tiny)
        #expect(data == payload)
    }
}
