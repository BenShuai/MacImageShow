import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = ViewModel()
    private weak var mainWindow: NSWindow?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 在 Apple Event 层截获“打开文档”（odoc）事件：
        // 否则 SwiftUI 的 WindowGroup 会在每次收到文件时新建一个窗口
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleOpenDocuments(_:replyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEOpenDocuments)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 关闭窗口/URL 状态恢复，避免重启时重放上一次打开的图片
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": false])
        if let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
            let saved = lib.appendingPathComponent("Saved Application State")
                .appendingPathComponent("com.trae.imageshow.savedState")
            try? FileManager.default.removeItem(at: saved)
        }

        NSApplication.shared.activate(ignoringOtherApps: true)

        // 设置初始窗口大小与位置，并标记为唯一主窗口、禁止状态恢复
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let window = NSApp.windows.first(where: { $0.styleMask.contains(.titled) }) else { return }
            self.mainWindow = window
            window.isRestorable = false
            window.identifier = NSUserInterfaceItemIdentifier("ImageShowMainWindow")
            let frame = window.frame
            let target = NSRect(x: frame.midX - 550,
                                y: frame.midY - 390,
                                width: 1100,
                                height: 780)
            window.setFrame(target, display: true, animate: false)
            window.center()
        }

        // 支持直接以二进制 + 文件路径的方式启动（测试 / 命令行）
        for arg in CommandLine.arguments.dropFirst() {
            if FileManager.default.fileExists(atPath: arg) {
                viewModel.open(url: URL(fileURLWithPath: arg))
                break
            }
        }
    }

    /// 处理 Finder 双击 / “打开方式” 发来的 odoc Apple Event
    @objc func handleOpenDocuments(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard let list = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)) else { return }
        var urls: [URL] = []
        for i in 1...list.numberOfItems {
            guard let item = list.atIndex(i) else { continue }
            if let url = Self.url(from: item) {
                urls.append(url)
            }
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let url = urls.first {
            viewModel.open(url: url)
        }
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    /// 从 odoc 条目中解析文件 URL，兼容 file URL 字符串、POSIX 路径、alias 记录
    private static func url(from descriptor: NSAppleEventDescriptor) -> URL? {
        if let str = descriptor.stringValue {
            if let parsed = URL(string: str), parsed.isFileURL {
                return parsed
            }
            if str.hasPrefix("/") {
                return URL(fileURLWithPath: str)
            }
        }
        // 其余形式（alias / fsref 等）强制转成 file URL 描述符
        if let coerced = descriptor.coerce(toDescriptorType: DescType(typeFileURL)),
           let str = coerced.stringValue,
           let parsed = URL(string: str), parsed.isFileURL {
            return parsed
        }
        return nil
    }

    /// Dock 图标点击（应用已运行）时把窗口带到前面
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindow?.makeKeyAndOrderFront(nil)
        return true
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct ImageShowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.viewModel)
                .frame(minWidth: 640, minHeight: 420)
        }
    }
}
