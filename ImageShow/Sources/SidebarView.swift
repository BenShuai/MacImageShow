import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// 左侧缩略图栏：列出当前目录扫描到的所有图片
struct SidebarView: View {
    @EnvironmentObject var vm: ViewModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("目录图片")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(vm.urls.count)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(Array(vm.urls.enumerated()), id: \.element) { i, url in
                            ThumbnailRow(
                                url: url,
                                isSelected: i == vm.index,
                                position: i + 1
                            )
                            .id(i)
                            .onTapGesture { vm.select(i) }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                    // 数据集变化（如裁剪后新增文件）时重建，规避 LazyVStack
                    // 在顶部插入数据时行视图错位的问题
                    .id(vm.urls.map(\.path).joined(separator: "\n"))
                }
                .onChange(of: vm.index) { newValue in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
                .onChange(of: vm.urls.count) { _ in
                    proxy.scrollTo(vm.index, anchor: .center)
                }
                .onAppear {
                    proxy.scrollTo(vm.index, anchor: .center)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct ThumbnailRow: View {
    let url: URL
    let isSelected: Bool
    let position: Int

    @State private var thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .windowBackgroundColor))
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .interpolation(.medium)
                        .aspectRatio(contentMode: .fit)
                        .padding(2)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 22))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            .frame(width: 120, height: 84)
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.25),
                            lineWidth: isSelected ? 2.5 : 1)
            )
            .overlay(alignment: .topLeading) {
                Text("\(position)")
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Capsule().fill(Color.black.opacity(0.55)))
                    .foregroundColor(.white)
                    .padding(4)
            }

            Text(url.lastPathComponent)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(isSelected ? .accentColor : .secondary)
                .frame(maxWidth: 124)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
        .task(id: url) {
            if thumbnail == nil {
                let loaded = await ThumbnailLoader.thumbnail(for: url, maxPixelSize: 240)
                if !Task.isCancelled { thumbnail = loaded }
            }
        }
    }
}

/// 用 ImageIO 降采样生成缩略图，避免一次性把大图全部解码进内存
enum ThumbnailLoader {
    static func thumbnail(for url: URL, maxPixelSize: CGFloat) async -> NSImage? {
        await Task.detached(priority: .utility) {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
            ]
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else { return nil }
            return NSImage(cgImage: cgImage,
                           size: NSSize(width: cgImage.width, height: cgImage.height))
        }.value
    }
}
