import AppKit
import Combine

final class ViewModel: ObservableObject {
    /// 当前目录下的全部图片
    @Published private(set) var urls: [URL] = []
    /// 当前图片索引
    @Published private(set) var index: Int = 0
    /// 当前图片地址
    @Published private(set) var imageURL: URL?
    /// 当前图片
    @Published private(set) var image: NSImage?
    /// 加载/错误提示
    @Published var toast: String?
    @Published var errorMessage: String?

    private var loadedToken = 0

    var canGoPrev: Bool { index > 0 }
    var canGoNext: Bool { index + 1 < urls.count }

    var positionText: String {
        guard !urls.isEmpty else { return "" }
        return "\(index + 1) / \(urls.count)"
    }

    var titleText: String {
        guard let url = imageURL else { return "ImageShow" }
        return "\(url.lastPathComponent)  ·  \(positionText)"
    }

    /// 打开一张图片，并扫描其所在目录下的所有图片
    func open(url input: URL) {
        // 统一规范化路径，保证与目录枚举结果可比较
        let url = ImageUtility.canonicalURL(input)
        if url == imageURL, image != nil { return }

        let dir = url.deletingLastPathComponent()
        let fm = FileManager.default

        var scanned: [URL] = []
        if let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentTypeKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) {
            scanned = entries.filter { !$0.hasDirectoryPath && ImageUtility.isImage($0) }
                .sorted { lhs, rhs in
                    // 稳定、可预测的文件名顺序（大小写不敏感），保证裁剪结果紧邻原图
                    let r = lhs.lastPathComponent.compare(rhs.lastPathComponent,
                                                          options: [.caseInsensitive, .numeric])
                    if r == .orderedSame { return lhs.path < rhs.path }
                    return r == .orderedAscending
                }
        }

        // 即使目录扫描失败，也至少保证当前图片可以浏览
        if scanned.isEmpty {
            scanned = [url]
        }

        urls = scanned
        // 优先按规范化完整路径匹配；极端情况下按同目录文件名兜底
        index = scanned.firstIndex(of: url)
            ?? scanned.firstIndex { $0.lastPathComponent == url.lastPathComponent }
            ?? 0
        loadImage(at: index)
    }

    func goPrev() {
        guard canGoPrev else { return }
        index -= 1
        loadImage(at: index)
    }

    func goNext() {
        guard canGoNext else { return }
        index += 1
        loadImage(at: index)
    }

    /// 从缩略图栏跳转到指定图片
    func select(_ i: Int) {
        guard urls.indices.contains(i), i != index else { return }
        index = i
        loadImage(at: i)
    }

    private func loadImage(at i: Int) {
        guard urls.indices.contains(i) else {
            image = nil
            imageURL = nil
            return
        }
        let url = urls[i]
        imageURL = url
        image = nil

        loadedToken += 1
        let token = loadedToken
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = NSImage(contentsOfFile: url.path)
            DispatchQueue.main.async { [weak self] in
                guard let self = self, token == self.loadedToken else { return }
                if let loaded = loaded {
                    self.image = loaded
                } else {
                    self.image = nil
                    self.errorMessage = "无法打开图片：\(url.lastPathComponent)"
                }
            }
        }
    }

    /// 执行裁剪并保存为 PNG，保存后自动跳转到裁剪结果
    func saveCrop(rectInImagePoints rect: CGRect) {
        guard let nsImage = image, let url = imageURL else { return }
        do {
            let cropped = try ImageUtility.crop(image: nsImage, toImageRect: rect)
            let dest = ImageUtility.makeCroppedURL(for: url)
            do {
                try ImageUtility.savePNG(cropped, to: dest)
            } catch {
                throw CropError.saveFailed(error)
            }
            showToast("已保存裁剪图片：\(dest.lastPathComponent)")
            open(url: dest)
        } catch let error as CropError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func showToast(_ text: String) {
        toast = text
        let token = UUID()
        toastToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if self?.toastToken == token { self?.toast = nil }
        }
    }

    private var toastToken: UUID?
}
