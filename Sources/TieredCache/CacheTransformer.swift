import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// 把磁盘上的原始 Data 转成可复用的对象(解码后的图片、解析后的动画实体等),对象放入 L1。
/// 扩展新类型只需实现该协议,例如 SVGA、Lottie 的解析器。
public protocol CacheTransformer {
    associatedtype Object: AnyObject
    /// 区分不同转换结果,参与内存 key。
    var identifier: String { get }
    func decode(_ data: Data) throws -> Object
    /// 解码后占用的字节数,作为 NSCache 的 cost。
    func cost(of object: Object) -> Int
}

#if canImport(UIKit)
public struct ImageTransformer: CacheTransformer {
    public var identifier: String { "uiimage" }
    public init() {}

    public func decode(_ data: Data) throws -> UIImage {
        guard let image = UIImage(data: data) else { throw TieredCacheError.decodeFailed }
        // 提前解码,避免首次显示时在主线程解码。
        return image.preparingForDisplay() ?? image
    }

    public func cost(of image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 0 }
        return cg.bytesPerRow * cg.height
    }
}
#endif
