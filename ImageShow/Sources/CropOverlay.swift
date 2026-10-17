import SwiftUI

/// 裁剪选框覆盖层。
/// rect 使用“图片点”坐标系（原点在图片左上），displayScale 为图片当前显示缩放比例。
struct CropOverlay: View {
    let imageSize: CGSize
    let displayScale: CGFloat
    @Binding var rect: CGRect

    private enum Handle { case nw, ne, sw, se }
    private enum DragMode {
        case creating(start: CGPoint)
        case moving(startOrigin: CGPoint)
        case resizing(handle: Handle, startRect: CGRect)
    }

    @State private var mode: DragMode?

    private let handleHitSize: CGFloat = 26
    private let minSize: CGFloat = 8

    private var dRect: CGRect {
        rect.applying(CGAffineTransform(scaleX: displayScale, y: displayScale))
    }

    private var displaySize: CGSize {
        CGSize(width: imageSize.width * displayScale,
               height: imageSize.height * displayScale)
    }

    private func toImage(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x / displayScale, y: p.y / displayScale)
    }

    private func handleAt(_ p: CGPoint) -> Handle? {
        let r = dRect
        let hit: CGFloat = handleHitSize / 2
        let corners: [(Handle, CGPoint)] = [
            (.nw, CGPoint(x: r.minX, y: r.minY)),
            (.ne, CGPoint(x: r.maxX, y: r.minY)),
            (.sw, CGPoint(x: r.minX, y: r.maxY)),
            (.se, CGPoint(x: r.maxX, y: r.maxY))
        ]
        for (h, c) in corners where abs(p.x - c.x) <= hit && abs(p.y - c.y) <= hit {
            return h
        }
        return nil
    }

    private func clampRect(_ r: CGRect) -> CGRect {
        let bounds = CGRect(origin: .zero, size: imageSize)
        var x = max(0, min(r.origin.x, imageSize.width - r.width))
        var y = max(0, min(r.origin.y, imageSize.height - r.height))
        var w = min(r.width, bounds.width)
        var h = min(r.height, bounds.height)
        if r.width >= imageSize.width { x = 0 }
        if r.height >= imageSize.height { y = 0 }
        w = min(w, imageSize.width - x)
        h = min(h, imageSize.height - y)
        return CGRect(x: x, y: y, width: max(1, w), height: max(1, h))
    }

    var body: some View {
        ZStack {
            // 半透明遮罩，选框处镂空
            HoleShape(hole: dRect)
                .fill(Color.black, style: FillStyle(eoFill: true))
                .opacity(0.45)
                .allowsHitTesting(false)

            // 选框边框
            ZStack {
                Rectangle()
                    .stroke(Color.white, lineWidth: 1.5)
                Rectangle()
                    .stroke(Color.black.opacity(0.6), lineWidth: 0.5)
                    .padding(0.75)
                // 三分线
                Path { path in
                    for i in 1...2 {
                        let x = dRect.width * CGFloat(i) / 3
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: dRect.height))
                        let y = dRect.height * CGFloat(i) / 3
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: dRect.width, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.6), lineWidth: 0.5)
            }
            .frame(width: dRect.width, height: dRect.height)
            .position(x: dRect.midX, y: dRect.midY)
            .allowsHitTesting(false)

            // 四角手柄
            ForEach(0..<4, id: \.self) { i in
                let h = [Handle.nw, .ne, .sw, .se][i]
                let pos = cornerPosition(h)
                CornerHandle()
                    .position(x: pos.x, y: pos.y)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
        .coordinateSpace(name: "crop")
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("crop"))
                .onChanged(handleDragChanged)
                .onEnded { _ in mode = nil }
        )
        .onChange(of: displayScale) { _ in
            rect = clampRect(rect)
        }
    }

    private func cornerPosition(_ h: Handle) -> CGPoint {
        switch h {
        case .nw: return CGPoint(x: dRect.minX, y: dRect.minY)
        case .ne: return CGPoint(x: dRect.maxX, y: dRect.minY)
        case .sw: return CGPoint(x: dRect.minX, y: dRect.maxY)
        case .se: return CGPoint(x: dRect.maxX, y: dRect.maxY)
        }
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        let location = toImage(value.location)
        let start = toImage(value.startLocation)

        if mode == nil {
            if let h = handleAt(value.startLocation) {
                mode = .resizing(handle: h, startRect: rect)
            } else if rect.contains(start) {
                mode = .moving(startOrigin: rect.origin)
            } else {
                mode = .creating(start: start)
            }
        }

        guard let mode = mode else { return }
        switch mode {
        case .creating(let s):
            let x = min(max(0, s.x), imageSize.width)
            let y = min(max(0, s.y), imageSize.height)
            let cx = min(max(0, location.x), imageSize.width)
            let cy = min(max(0, location.y), imageSize.height)
            let r = CGRect(x: min(x, cx), y: min(y, cy),
                           width: abs(cx - x), height: abs(cy - y))
            rect = r.width >= 2 && r.height >= 2 ? r : CGRect(origin: CGPoint(x: x, y: y), size: .zero)

        case .moving(let origin):
            let dx = location.x - start.x
            let dy = location.y - start.y
            var r = rect
            r.origin = CGPoint(x: origin.x + dx, y: origin.y + dy)
            rect = clampRect(r)

        case .resizing(let handle, let startRect):
            var r = startRect
            let lx = min(max(0, location.x), imageSize.width)
            let ly = min(max(0, location.y), imageSize.height)
            switch handle {
            case .nw:
                let nx = min(lx, startRect.maxX - minSize)
                let ny = min(ly, startRect.maxY - minSize)
                r = CGRect(x: nx, y: ny,
                           width: startRect.maxX - nx, height: startRect.maxY - ny)
            case .ne:
                let ny = min(ly, startRect.maxY - minSize)
                let nx = max(lx, startRect.minX + minSize)
                r = CGRect(x: startRect.minX, y: ny,
                           width: nx - startRect.minX, height: startRect.maxY - ny)
            case .sw:
                let nx = min(lx, startRect.maxX - minSize)
                let ny = max(ly, startRect.minY + minSize)
                r = CGRect(x: nx, y: startRect.minY,
                           width: startRect.maxX - nx, height: ny - startRect.minY)
            case .se:
                let nx = max(lx, startRect.minX + minSize)
                let ny = max(ly, startRect.minY + minSize)
                r = CGRect(x: startRect.minX, y: startRect.minY,
                           width: nx - startRect.minX, height: ny - startRect.minY)
            }
            rect = clampRect(r)
        }
    }
}

/// 带镂空的遮罩形状（奇偶填充规则）
private struct HoleShape: Shape {
    let hole: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRect(hole)
        return path
    }
}

private struct CornerHandle: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.white)
                .frame(width: 10, height: 10)
            Rectangle()
                .stroke(Color.black.opacity(0.7), lineWidth: 1)
                .frame(width: 10, height: 10)
        }
        .shadow(color: .black.opacity(0.3), radius: 1)
    }
}
