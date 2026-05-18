#!/bin/sh
# DeepSeek TUI 从源码编译安装脚本（Alpine on OpenHarmony）
#
# 预编译二进制要求 glibc，Alpine 是 musl，只能从源码编译。
# 需要网络（代理）和约 1GB 临时空间，编译耗时约 10-20 分钟。
#
# 用法：sh build_install_deepseek_tui.sh

set -e

echo "=== 1/4 安装编译依赖 ==="
rm -f /lib/apk/db/lock
apk add gcc musl-dev pkgconfig dbus-dev ncurses-terminfo-base

echo "=== 2/4 安装 Rust 工具链（rustup） ==="
if command -v rustup >/dev/null 2>&1; then
    echo "rustup 已安装，跳过"
else
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi
. "$HOME/.cargo/env"

echo "Rust 版本: $(rustc --version)"
echo "Cargo 版本: $(cargo --version)"

RUSTFLAGS="-C target-feature=-crt-static -C link-arg=-latomic"
export RUSTFLAGS

echo "=== 3/4 编译 deepseek-tui-cli ==="
cargo install deepseek-tui-cli --locked

echo "=== 4/4 编译 deepseek-tui ==="
cargo install deepseek-tui --locked

echo ""
echo "=== 安装完成 ==="
echo "二进制位置: ~/.cargo/bin/deepseek 和 ~/.cargo/bin/deepseek-tui"
echo ""
echo "使用前设置环境变量："
echo "  export TERM=xterm-256color"
echo "  export DEEPSEEK_API_KEY=your-api-key"
echo "  deepseek"
