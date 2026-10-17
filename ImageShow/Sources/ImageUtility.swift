import AppKit
import ImageIO
import UniformTypeIdentifiers
import Darwin

enum ImageUtility {
    /// 用 realpath 规范化路径（可解析 /tmp 等 firmlink/符号链接），
    /// 保证与 FileManager 枚举返回的路径形式一致
    static func canonicalURL(_ url: URL) -> URL {
        let resolved = url.path.withCString { c -> String? in
            guard let p = realpath(c, nil) else { return nil }
            defer { free(p) }
            return String(cString: p)
        }
        return URL(fileURLWithPath: resolved ?? (url.path as NSString).standardizingPath)
    }
    /// 常见图片扩展名（UTI 判断失败时的兜底）
    static let supportedExtensions: Set<String> = [
        "jpg", "jpeg", "jpe", "jfif", "png", "gif",
        "tif", "tiff", "bmp", "webp", "heic", "heics",
        "heif", "heifs", "icns", "tga", "psd", "raw",
        "cr2", "nef", "arw", "dng", "orf", "rw2", "pef", "srw"
    ]

    /// 判断文件是否为受支持的图片（优先用 UTI 类型判断）
    static func isImage(_ url: URL) -> Bool {
        if let typeID = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
            if typeID.conforms(to: .image) { return true }
        }
        return supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// 获取 NSImage 对应的 CGImage
    static func cgImage(of image: NSImage) -> CGImage? {
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    /// 将 view 坐标系（左上角原点）下、以图片点为单位的裁剪框裁剪原图
    static func crop(image nsImage: NSImage, toImageRect rect: CGRect) throws -> CGImage {
        guard let cg = cgImage(of: nsImage) else { throw CropError.invalidImage }

        let imageBounds = CGRect(origin: .zero, size: nsImage.size)
        var cropRect = rect.integral.intersection(imageBounds)
        guard cropRect.width >= 2, cropRect.height >= 2 else { throw CropError.tooSmall }

        // 图片点坐标 -> 像素坐标
        let scaleX = CGFloat(cg.width) / nsImage.size.width
        let scaleY = CGFloat(cg.height) / nsImage.size.height
        cropRect = cropRect.applying(CGAffineTransform(scaleX: scaleX, y: scaleY)).integral

        // 翻转 Y 轴：view 坐标原点在左上，CGImage 坐标原点在左下
        cropRect.origin.y = CGFloat(cg.height) - cropRect.maxY

        guard let result = cg.cropping(to: cropRect) else { throw CropError.cropFailed }
        return result
    }

    /// 以 PNG 格式写入图片
    static func savePNG(_ cgImage: CGImage, to url: URL) throws {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        rep.size = NSSize(width: cgImage.width, height: cgImage.height)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CropError.encodeFailed
        }
        try data.write(to: url, options: .atomic)
    }

    /// 在同目录下生成不冲突的“xxx_cropped.png”路径
    static func makeCroppedURL(for source: URL) -> URL {
        let dir = source.deletingLastPathComponent()
        let base = source.deletingPathExtension().lastPathComponent
        let fm = FileManager.default
        let candidate = dir.appendingPathComponent("\(base)_cropped.png")
        if !fm.fileExists(atPath: candidate.path) { return candidate }
        var i = 1
        while true {
            let url = dir.appendingPathComponent("\(base)_cropped\(i).png")
            if !fm.fileExists(atPath: url.path) { return url }
            i += 1
        }
    }
}

enum CropError: LocalizedError {
    case invalidImage, tooSmall, cropFailed, encodeFailed, saveFailed(Error)

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "无法读取该图片"
        case .tooSmall: return "裁剪区域过小"
        case .cropFailed: return "裁剪失败"
        case .encodeFailed: return "PNG 编码失败"
        case .saveFailed(let e): return "保存失败：\(e.localizedDescription)"
        }
    }
}
