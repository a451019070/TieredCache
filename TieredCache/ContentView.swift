//
//  ContentView.swift
//  TieredCache
//
//  Created by ZX on 2026/10/15.
//

import SwiftUI

/// 自定义分类示例:音频,不进内存,磁盘 200MB,保留 3 天。
extension CacheCategory {
    static let audio = CacheCategory(name: "audio", policy: CachePolicy(
        memoryMaxItemSize: 0,
        memoryTotalCostLimit: 0,
        diskSizeLimit: 200 * 1024 * 1024,
        maxAge: 3 * 24 * 3600))
}

struct ContentView: View {
    private let cache = TieredCache.shared
    private let imageURL = URL(string: "https://picsum.photos/600/400.jpg")!
    private let videoURL = URL(string: "https://www.w3schools.com/html/mov_bbb.mp4")!
    private let jsonURL = URL(string: "https://httpbin.org/json")!

    #if canImport(UIKit)
    @State private var image: UIImage?
    #endif
    @State private var log: String = "点击下方按钮查看缓存示例"

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                #if canImport(UIKit)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                #endif

                Button("1. 加载图片 (内存 -> 磁盘 -> 网络)") { Task { await loadImage() } }
                Button("2. 读取 Data (JSON / SVGA 等小文件)") { Task { await loadData() } }
                Button("3. 获取视频本地文件 URL") { Task { await loadVideo() } }
                Button("4. 仅查询本地是否已缓存") { Task { await checkCached() } }
                Button("5. 手动写入缓存 / 删除单条") { Task { await storeAndRemove() } }
                Button("6. 清理过期并控制容量") { Task { await cache.trimDisk(); log = "trim 完成" } }
                Button("7. 清空图片分类", role: .destructive) {
                    Task { await cache.removeAll(category: .image); log = "image 分类已清空" }
                }

                Text(log)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .padding()
        }
        .onAppear { setup() }
    }

    // MARK: - 使用示例

    /// 初始化:自定义 key 过滤(去掉鉴权/时间戳参数),并注册自定义分类参与定期清理。
    private func setup() {
        cache.keyFilter = { url in
            guard var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return url.absoluteString
            }
            comps.queryItems = comps.queryItems?.filter { !["token", "sign", "t"].contains($0.name) }
            return comps.string ?? url.absoluteString
        }
        cache.register(.audio)
    }

    /// 图片:自动三级查找,解码后的 UIImage 会放入内存。
    private func loadImage() async {
        #if canImport(UIKit)
        do {
            image = try await imageURL.loadImage(category: .small)
            log = "图片加载成功"
        } catch {
            log = "图片加载失败: \(error)"
        }
        #else
        log = "当前平台不支持 UIImage"
        #endif
    }

    /// 小文件 Data:小于 memoryMaxItemSize 的会进内存,否则从磁盘读取。
    private func loadData() async {
        do {
            let data = try await cache.data(forKey: jsonURL, category: .tiny)
            log = "Data 大小: \(data.count) 字节"
        } catch {
            log = "Data 加载失败: \(error)"
        }
    }

    /// 视频:不进内存,下载落盘后返回文件 URL,可直接交给 AVPlayer。
    private func loadVideo() async {
        do {
            let fileURL = try await cache.url(forKey: videoURL, category: .large)
            log = "视频本地路径:\n\(fileURL.path)"
            // let player = AVPlayer(url: fileURL)
        } catch {
            log = "视频获取失败: \(error)"
        }
    }

    /// 仅查本地,不触发下载,可用于决定是否展示"已缓存"标识。
    private func checkCached() async {
        if let url = await cache.cachedURL(forKey: videoURL, category: .large) {
            log = "视频已缓存:\n\(url.path)"
        } else {
            log = "视频未缓存"
        }
    }

    /// 手动写入 / 删除单条缓存。
    private func storeAndRemove() async {
        let url = URL(string: "https://example.com/hello.txt")!
        do {
            try await cache.store(Data("hello".utf8), for: url, category: .audio)
            let data = try await cache.data(forKey: url, category: .audio)
            log = "已写入并读取: \(String(decoding: data, as: UTF8.self))"
            await cache.remove(for: url, category: .audio)
        } catch {
            log = "操作失败: \(error)"
        }
    }
}

#Preview {
    ContentView()
}
