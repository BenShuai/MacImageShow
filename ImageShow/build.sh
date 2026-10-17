#!/bin/bash
# 编译并打包 ImageShow.app
set -e

cd "$(dirname "$0")"
ROOT="$(pwd)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/ImageShow.app"
MACOS_DIR="$APP/Contents/MacOS"
RESOURCES_DIR="$APP/Contents/Resources"
DEPLOYMENT_TARGET="12.0"

echo "==> 清理旧构建"
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

NATIVE_ARCH="$(uname -m)"
TMP_BIN="/tmp/ImageShow.bin.$$"
trap 'rm -f /tmp/ImageShow.bin.$$ /tmp/ImageShow.arm64.$$ /tmp/ImageShow.x86_64.$$' EXIT

compile() {
    local arch="$1"
    local output="$2"
    echo "==> 编译 $arch"
    swiftc \
        -parse-as-library \
        -O \
        -target "${arch}-apple-macos${DEPLOYMENT_TARGET}" \
        -swift-version 5 \
        Sources/*.swift \
        -o "$output"
}

# 先编译本机架构（必选）
compile "$NATIVE_ARCH" "$TMP_BIN"
FINAL_BIN="$TMP_BIN"

# 尝试同时编译另一种架构，合成通用二进制（失败则仅使用本机架构）
OTHER_ARCH=""
if [ "$NATIVE_ARCH" = "arm64" ]; then OTHER_ARCH="x86_64"; else OTHER_ARCH="arm64"; fi
OTHER_BIN="/tmp/ImageShow.${OTHER_ARCH}.$$"
if compile "$OTHER_ARCH" "$OTHER_BIN" 2>/dev/null; then
    echo "==> 合成通用二进制"
    lipo -create "$TMP_BIN" "$OTHER_BIN" -output "$MACOS_DIR/ImageShow"
else
    echo "==> 仅打包 $NATIVE_ARCH 架构"
    cp "$TMP_BIN" "$MACOS_DIR/ImageShow"
fi

echo "==> 组装 App Bundle"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> 临时签名（ad-hoc）"
codesign --force --sign - "$APP" 2>/dev/null || true

echo "==> 注册到 Launch Services（Finder 打开方式 / 双击关联）"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -f "$APP"
fi

echo ""
echo "✅ 构建完成：$APP"
echo "   首次使用：在 Finder 中右键图片 → 打开方式 → ImageShow"
echo "   设为默认：右键图片 → 显示简介 → 打开方式 → ImageShow → 全部更改"
