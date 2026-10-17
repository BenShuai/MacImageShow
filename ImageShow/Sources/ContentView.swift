import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var vm: ViewModel

    // zoom 是相对于“适应窗口”的倍数，displayScale = fitScale * zoom
    @State private var zoom: CGFloat = 1
    @State private var fitScale: CGFloat = 1
    @State private var pinchStartScale: CGFloat?

    @State private var cropping = false
    @State private var cropRect: CGRect = .zero

    @State private var showSidebar = true
    @State private var isDropTargeted = false

    @State private var keyMonitor: Any?
    @State private var wheelMonitor: Any?

    private let minDisplayScale: CGFloat = 0.02
    private let maxDisplayScale: CGFloat = 25

    private var displayScale: CGFloat { fitScale * zoom }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HStack(spacing: 0) {
                if showSidebar && !vm.urls.isEmpty {
                    SidebarView()
                        .frame(width: 150)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    Divider()
                }
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                    if let image = vm.image {
                        imageArea(image)
                    } else {
                        emptyState
                    }
                    if let toast = vm.toast {
                        Text(toast)
                            .font(.system(size: 13))
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(Capsule().fill(Color.black.opacity(0.72)))
                            .foregroundColor(.white)
                            .padding(.bottom, 24)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                            .transition(.opacity)
                    }
                }
                .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                    handleDrop(providers)
                }
                .overlay {
                    if isDropTargeted {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.accentColor, lineWidth: 3)
                            .background(RoundedRectangle(cornerRadius: 10)
                                .fill(Color.accentColor.opacity(0.08)))
                            .padding(6)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .onAppear { installMonitors() }
        .onDisappear { removeMonitors() }
        .onChange(of: vm.imageURL) { _ in
            cropping = false
            zoom = 1
        }
        .alert(isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Alert(
                title: Text("提示"),
                message: Text(vm.errorMessage ?? ""),
                dismissButton: .default(Text("好"))
            )
        }
    }

    // MARK: - 顶部工具栏

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { showSidebar.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
            }
            .help("显示/隐藏缩略图栏")
            .disabled(vm.urls.isEmpty)
            .frame(width: 34)

            HStack(spacing: 6) {
                Button(action: vm.goPrev) {
                    Image(systemName: "arrow.up")
                }
                .help("上一张（↑）")
                .disabled(!vm.canGoPrev || cropping)
                .frame(width: 34)

                Button(action: vm.goNext) {
                    Image(systemName: "arrow.down")
                }
                .help("下一张（↓）")
                .disabled(!vm.canGoNext || cropping)
                .frame(width: 34)
            }

            Text(vm.titleText)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 280)

            Divider().frame(height: 22)

            HStack(spacing: 6) {
                Button { stepZoom(1.0 / 1.2) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .help("缩小")
                .disabled(cropping || vm.image == nil)
                .frame(width: 34)

                Slider(value: Binding(
                    get: { Double(zoom) },
                    set: { setZoomFactor(CGFloat($0)) }
                ), in: 0.1...12)
                    .frame(width: 130)
                    .disabled(cropping || vm.image == nil)
                    .help("缩放")

                Button { stepZoom(1.2) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .help("放大")
                .disabled(cropping || vm.image == nil)
                .frame(width: 34)

                Button { setDisplayScale(1) } label: {
                    Text("\(Int((displayScale * 100).rounded()))%")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .frame(minWidth: 52)
                }
                .help("实际大小（100%）")
                .disabled(cropping || vm.image == nil)

                Button { zoom = 1 } label: {
                    Text("适应")
                        .font(.system(size: 12))
                        .frame(minWidth: 40)
                }
                .help("适应窗口（0）")
                .disabled(cropping || vm.image == nil)
            }

            Divider().frame(height: 22)

            if cropping {
                Button { cancelCrop() } label: {
                    Text("取消裁剪")
                }
                .help("取消（esc）")

                Button { commitCrop() } label: {
                    Text("裁剪并保存")
                }
                .buttonStyle(.borderedProminent)
                .help("保存裁剪结果（enter）")
            } else {
                Button { enterCrop() } label: {
                    Label("裁剪", systemImage: "crop")
                }
                .help("进入裁剪模式")
                .disabled(vm.image == nil)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            Text("把图片拖到窗口，或在 Finder 中双击图片用本软件打开")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 图片区域

    private func imageArea(_ image: NSImage) -> some View {
        GeometryReader { geo in
            let imgW = image.size.width
            let imgH = image.size.height
            let fit = min((geo.size.width - 32) / imgW,
                          (geo.size.height - 32) / imgH,
                          maxDisplayScale)
            let scale = max(minDisplayScale, fit * zoom)
            let viewW = imgW * scale
            let viewH = imgH * scale

            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                ZStack {
                    Color.clear
                        .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: viewW, height: viewH)
                        .overlay {
                            if cropping {
                                CropOverlay(imageSize: image.size,
                                            displayScale: scale,
                                            rect: $cropRect)
                            }
                        }
                        .gesture(zoomGesture())
                        .onTapGesture(count: 2) {
                            guard !cropping else { return }
                            withAnimation(.easeInOut(duration: 0.15)) {
                                if abs(zoom - 1) < 0.02 { zoom = 2 / fit }
                                else { zoom = 1 }
                            }
                        }
                }
                .frame(width: max(viewW, geo.size.width),
                       height: max(viewH, geo.size.height))
            }
            .onChange(of: fit) { newValue in fitScale = newValue }
            .onAppear { fitScale = fit }
        }
    }

    private func zoomGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                guard !cropping else { return }
                if pinchStartScale == nil { pinchStartScale = displayScale }
                let target = (pinchStartScale ?? displayScale) * value
                setDisplayScale(target)
            }
            .onEnded { _ in pinchStartScale = nil }
    }

    // MARK: - 缩放控制

    private func setZoomFactor(_ factor: CGFloat) {
        zoom = min(max(factor, 0.1), 12)
    }

    private func setDisplayScale(_ target: CGFloat) {
        guard fitScale > 0 else { return }
        let clamped = min(max(target, minDisplayScale), maxDisplayScale)
        zoom = clamped / fitScale
    }

    private func stepZoom(_ factor: CGFloat) {
        withAnimation(.easeOut(duration: 0.12)) {
            setDisplayScale(displayScale * factor)
        }
    }

    // MARK: - 裁剪

    private func enterCrop() {
        guard let image = vm.image else { return }
        zoom = 1
        let insetX = image.size.width * 0.1
        let insetY = image.size.height * 0.1
        cropRect = CGRect(x: insetX, y: insetY,
                          width: image.size.width - insetX * 2,
                          height: image.size.height - insetY * 2)
        cropping = true
    }

    private func cancelCrop() {
        cropping = false
    }

    private func commitCrop() {
        let r = cropRect
        cropping = false
        vm.saveCrop(rectInImagePoints: r)
    }

    // MARK: - 拖放打开

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier("public.file-url")
        }) else { return false }

        provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url = url else { return }
            DispatchQueue.main.async { vm.open(url: url) }
        }
        return true
    }

    // MARK: - 键盘 / 滚轮事件

    private func installMonitors() {
        let model = vm
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            // 保留 Cmd 系列系统快捷键
            if event.modifierFlags.contains(.command) { return event }
            return handleKey(event, model: model)
        }
        wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [self] event in
            return handleWheel(event)
        }
    }

    private func removeMonitors() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = wheelMonitor { NSEvent.removeMonitor(m); wheelMonitor = nil }
    }

    private func handleKey(_ event: NSEvent, model: ViewModel) -> NSEvent? {
        switch event.keyCode {
        case 126, 123: // ↑ / ← 上一张
            if !cropping { model.goPrev(); return nil }
        case 125, 124: // ↓ / → 下一张
            if !cropping { model.goNext(); return nil }
        case 53: // esc 取消裁剪
            if cropping { cancelCrop(); return nil }
        case 36: // enter 确认裁剪
            if cropping { commitCrop(); return nil }
        case 24: // +/= 放大
            if !cropping { stepZoom(1.2); return nil }
        case 27: // - 缩小
            if !cropping { stepZoom(1.0 / 1.2); return nil }
        case 29: // 0 适应窗口
            if !cropping { withAnimation { zoom = 1 }; return nil }
        default:
            break
        }
        return event
    }

    private func handleWheel(_ event: NSEvent) -> NSEvent? {
        guard !cropping, vm.image != nil else { return event }

        // 触控板双指捏合缩放
        if event.type == .magnify {
            setDisplayScale(displayScale * (1 + event.magnification))
            return nil
        }

        guard event.type == .scrollWheel else { return event }

        // Ctrl + 滚轮（含触控板双指按住 Control）缩放
        if event.modifierFlags.contains(.control) {
            wheelZoom(by: event.deltaY, sensitive: event.hasPreciseScrollingDeltas)
            return nil
        }

        // 触控板两指滑动（有 phase / 精确增量）交给 ScrollView 平移图片
        let isTrackpad = !event.phase.isEmpty || !event.momentumPhase.isEmpty
            || event.hasPreciseScrollingDeltas
        if isTrackpad { return event }

        // 物理鼠标滚轮：垂直滚动 = 缩放；横向滚轮（左右拨动）= 平移
        if abs(event.deltaY) >= abs(event.deltaX) {
            wheelZoom(by: event.deltaY, sensitive: false)
            return nil
        }
        return event
    }

    private func wheelZoom(by deltaY: CGFloat, sensitive: Bool) {
        // 鼠标滚轮一格约 1 个单位 → 缩放 12%；触控板精确增量做平滑缩放
        let step = sensitive ? 0.02 : 0.12
        let factor = 1 + deltaY * step
        setDisplayScale(displayScale * factor)
    }
}
