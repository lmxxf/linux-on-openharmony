#!/bin/sh
#
# Linux on OpenHarmony — 卸载脚本
#

set -e

ALPINE_DIR="/data/alpine"
ENTER_SCRIPT="/data/local/tmp/alpine-enter.sh"

info() { echo "[*] $1"; }
err()  { echo "[!] $1" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || err "需要 root 权限"

if [ ! -d "$ALPINE_DIR" ]; then
    info "Alpine 未安装，无需卸载"
    exit 0
fi

info "卸载挂载点 ..."
umount "$ALPINE_DIR/dev/pts" 2>/dev/null || true
umount "$ALPINE_DIR/dev"     2>/dev/null || true
umount "$ALPINE_DIR/sys"     2>/dev/null || true
umount "$ALPINE_DIR/proc"    2>/dev/null || true

info "删除 Alpine rootfs ..."
rm -rf "$ALPINE_DIR"

info "删除入口脚本 ..."
rm -f "$ENTER_SCRIPT"
rm -f "/data/local/tmp/install.sh"
rm -f "/data/local/tmp/uninstall.sh"
rm -f "/data/local/tmp/alpine-minirootfs.tar.gz"

info "卸载完成"
