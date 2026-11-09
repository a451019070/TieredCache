import Foundation

public enum TieredCacheError: Error {
    case badStatus(Int)
    case notHTTPResponse
    case decodeFailed
}

// MARK: - Promise

/// 单次下载的完成状态。
/// delegate 回调可能早于等待者建立,所以做成 promise:先到的一方存下结果,后到的一方直接取用。
private final class DownloadPromise: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<URL, Error>?
    private var continuation: CheckedContinuation<URL, Error>?
    private var staged: URL?

    var stagedURL: URL? {
        lock.lock(); defer { lock.unlock() }
        return staged
    }

    func value() async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            lock.lock()
            if let result {
                lock.unlock()
                cont.resume(with: result)
            } else {
                continuation = cont
                lock.unlock()
            }
        }
    }

    func markStaged(_ url: URL) {
        lock.lock(); staged = url; lock.unlock()
    }

    func succeed(_ url: URL) { settle(.success(url)) }
    func fail(_ error: Error) { settle(.failure(error)) }

    private func settle(_ outcome: Result<URL, Error>) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = outcome
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(with: outcome)
    }
}

// MARK: - Bridge

/// 把 delegate 式的 `URLSessionDownloadTask` 桥接成 async。
/// 不用 `download(from:)` 是因为只有 `URLSessionDownloadTask` 能通过
/// `cancel(byProducingResumeData:)` 拿到断点续传数据。
private final class DownloadBridge: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var promises: [Int: DownloadPromise] = [:]
    private let staging: URL

    init(staging: URL) {
        self.staging = staging
        super.init()
        // 上次进程遗留的暂存文件直接丢弃。
        try? FileManager.default.removeItem(at: staging)
        try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    }

    func register(_ identifier: Int, _ promise: DownloadPromise) {
        lock.lock(); promises[identifier] = promise; lock.unlock()
    }

    private func peek(_ identifier: Int) -> DownloadPromise? {
        lock.lock(); defer { lock.unlock() }
        return promises[identifier]
    }

    private func take(_ identifier: Int) -> DownloadPromise? {
        lock.lock(); defer { lock.unlock() }
        return promises.removeValue(forKey: identifier)
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let promise = peek(downloadTask.taskIdentifier) else { return }
        guard let http = downloadTask.response as? HTTPURLResponse else {
            promise.fail(TieredCacheError.notHTTPResponse)
            return
        }
        guard (200..<300).contains(http.statusCode) else {
            promise.fail(TieredCacheError.badStatus(http.statusCode))
            return
        }
        // 本方法返回后系统会删除 location,必须同步搬走。
        do {
            let dest = staging.appendingPathComponent(UUID().uuidString)
            try FileManager.default.moveItem(at: location, to: dest)
            promise.markStaged(dest)
        } catch {
            promise.fail(error)
        }
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let promise = take(task.taskIdentifier) else { return }
        if let error {
            promise.fail(error)
        } else if let staged = promise.stagedURL {
            promise.succeed(staged)
        } else {
            promise.fail(TieredCacheError.notHTTPResponse)
        }
    }
}

// MARK: - ResumeGate

/// 取消回调是异步的,可能在任务已结束、甚至同资源重新下载之后才回来。
/// 闸门在任务结束(成功或失败)时关闭,回调发现已关闭就丢弃断点数据。
private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var closed = false

    var isClosed: Bool {
        lock.lock(); defer { lock.unlock() }
        return closed
    }

    func close() {
        lock.lock(); closed = true; lock.unlock()
    }
}

// MARK: - ActiveDownload

/// 一个逻辑下载当前对应的 `URLSessionDownloadTask`。
/// 断点数据失效会重建底层 task,取消时要找到最新那个。
private final class ActiveDownload: @unchecked Sendable {
    private let lock = NSLock()
    private var current: URLSessionDownloadTask?

    func set(_ task: URLSessionDownloadTask) {
        lock.lock(); current = task; lock.unlock()
    }

    func cancel(byProducingResumeData handler: @escaping @Sendable (Data?) -> Void) {
        lock.lock()
        let task = current
        lock.unlock()
        task?.cancel(byProducingResumeData: handler)
    }
}

// MARK: - Downloader

/// L3 网络层:下载直接落盘(不经过内存),同一资源的并发请求合并为一次下载。
/// - 合并:同一 `id` 只有一个进行中的任务,后到者复用同一个 Task。
/// - 取消:等待者计数归零才真正取消下载,单个调用者取消不影响其他人。
/// - 注销:任务结束立即从表里移除,后到者不会拿到已完成的失败任务。
/// - 续传:取消时保存 `resumeData` 到磁盘,同一资源下次下载接着传;
///   断点失效(服务器换文件、暂存被系统清理)时自动回落到全量下载。
actor Downloader {
    private struct Job: Sendable {
        let token: UUID
        let task: Task<URL, Error>
        var waiters: Int
        /// 取消并产出 resumeData。等待者计数归零时调用。
        let cancelWithResume: @Sendable () -> Void
    }

    private let session: URLSession
    private let bridge: DownloadBridge
    private var inflight: [String: Job] = [:]

    /// - Parameter session: 只取其 `configuration`(超时、header、`protocolClasses` 等)。
    ///   内部需要自己建一个带 delegate 的 session,否则拿不到 `resumeData`。
    init(session: URLSession = .shared) {
        let bridge = DownloadBridge(staging: FileManager.default.temporaryDirectory
            .appendingPathComponent("TieredCacheDownload", isDirectory: true))
        self.bridge = bridge
        let config = (session.configuration.copy() as? URLSessionConfiguration)
            ?? URLSessionConfiguration.default
        self.session = URLSession(configuration: config, delegate: bridge, delegateQueue: nil)
    }

    deinit {
        session.invalidateAndCancel()
    }

    func download(_ url: URL, key: CacheKey, category: CacheCategory, disk: DiskCache) async throws -> URL {
        let id = "\(category.name)/\(key.fileName)"
        let job = makeJob(id, url: url, key: key, category: category, disk: disk)

        let stored = try await withTaskCancellationHandler {
            try await job.task.value
        } onCancel: {
            Task { await self.removeWaiter(id: id, token: job.token) }
        }
        // 下载由别人续命完成时,已取消的调用者仍不应拿到成功结果。
        try Task.checkCancellation()
        return stored
    }

    /// 命中则复用并增加等待者计数,否则新建任务。
    /// 全程无挂起点,保证登记完成前任务体不会回头调用 `finish`。
    private func makeJob(_ id: String,
                         url: URL,
                         key: CacheKey,
                         category: CacheCategory,
                         disk: DiskCache) -> Job {
        if var existing = inflight[id] {
            existing.waiters += 1
            inflight[id] = existing
            return existing
        }

        let token = UUID()
        let box = ActiveDownload()
        let gate = ResumeGate()
        let resumeData = disk.resumeData(for: key, category: category)

        let task = Task<URL, Error> { [weak self] in
            guard let self else { throw CancellationError() }
            defer { gate.close() }
            return try await self.perform(url: url, resumeData: resumeData, key: key,
                                          category: category, disk: disk, box: box,
                                          id: id, token: token)
        }

        let cancelWithResume: @Sendable () -> Void = {
            box.cancel { data in
                guard let data, !gate.isClosed else {
                    disk.removeResumeData(for: key, category: category)
                    return
                }
                // 任务已彻底结束才留下断点,此时不会与新的下载重叠。
                disk.storeResumeData(data, for: key, category: category)
            }
        }

        let job = Job(token: token, task: task, waiters: 1, cancelWithResume: cancelWithResume)
        inflight[id] = job
        return job
    }

    /// 下载并落盘。断点数据失效时清掉断点、全量重下一次。
    private func perform(url: URL,
                         resumeData: Data?,
                         key: CacheKey,
                         category: CacheCategory,
                         disk: DiskCache,
                         box: ActiveDownload,
                         id: String,
                         token: UUID) async throws -> URL {
        do {
            let staged: URL
            do {
                staged = try await fetch(url, resumeData: resumeData, box: box)
            } catch {
                guard resumeData != nil, !Self.isCancellation(error) else { throw error }
                // 断点数据不可用(文件已变、暂存被清理):丢掉后从头下。
                disk.removeResumeData(for: key, category: category)
                staged = try await fetch(url, resumeData: nil, box: box)
            }
            let stored = try await disk.store(fileAt: staged, for: key, category: category)
            try? FileManager.default.removeItem(at: staged)
            // 下完即作废断点,避免下次从一个已完整的断点继续。
            disk.removeResumeData(for: key, category: category)
            finish(id: id, token: token)
            return stored
        } catch {
            // 取消时保留刚产出的 resumeData(由 cancelWithResume 写入),其余错误一律清掉。
            if !Self.isCancellation(error) {
                disk.removeResumeData(for: key, category: category)
            }
            finish(id: id, token: token)
            throw error
        }
    }

    /// 起一个底层 task 并等待其完成。
    private func fetch(_ url: URL, resumeData: Data?, box: ActiveDownload) async throws -> URL {
        let promise = DownloadPromise()
        let urlTask: URLSessionDownloadTask
        if let resumeData {
            urlTask = session.downloadTask(withResumeData: resumeData)
        } else {
            urlTask = session.downloadTask(with: url)
        }
        bridge.register(urlTask.taskIdentifier, promise)
        box.set(urlTask)
        urlTask.resume()
        return try await promise.value()
    }

    /// 任务成功或失败都立即注销;token 校验避免误删同 id 的新任务。
    private func finish(id: String, token: UUID) {
        guard inflight[id]?.token == token else { return }
        inflight[id] = nil
    }

    /// 等待者取消:计数归零才取消真正的下载,并尝试留下断点。
    private func removeWaiter(id: String, token: UUID) {
        guard var job = inflight[id], job.token == token else { return }
        job.waiters -= 1
        if job.waiters > 0 {
            inflight[id] = job
        } else {
            inflight[id] = nil
            job.cancelWithResume()
        }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }
}
