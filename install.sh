#!/bin/sh
#
# Linux on OpenHarmony — 一键安装脚本
# 在 OH 设备上通过 chroot 运行完整的 Alpine Linux
#
# 用法:
#   PC 端: hdc shell 'sh /data/local/tmp/install.sh'
#   或 hdc shell 进去后: sh /data/local/tmp/install.sh
#

set -e

ALPINE_DIR="/data/alpine"
ALPINE_VERSION="3.21"
ROOTFS_FILE="/data/local/tmp/alpine-minirootfs.tar.gz"
ENTER_SCRIPT="/data/local/tmp/alpine-enter.sh"

info() { echo "[*] $1"; }
err()  { echo "[!] $1" >&2; exit 1; }

# ── 前置检查 ──

[ "$(id -u)" -eq 0 ] || err "需要 root 权限"
[ "$(uname -m)" = "aarch64" ] || err "仅支持 aarch64 架构"

if [ -f "$ALPINE_DIR/etc/alpine-release" ]; then
    installed=$(cat "$ALPINE_DIR/etc/alpine-release")
    info "已安装 Alpine $installed，跳过安装"
    info "如需重装，先执行: sh /data/local/tmp/uninstall.sh"
    info "入口脚本: sh $ENTER_SCRIPT"
    exit 0
fi

# ── 检查 rootfs ──

[ -f "$ROOTFS_FILE" ] || err "未找到 $ROOTFS_FILE，请先推送:
  hdc file send alpine-minirootfs-3.21.3-aarch64.tar.gz $ROOTFS_FILE"

# ── 解压 ──

info "解压到 $ALPINE_DIR ..."
mkdir -p "$ALPINE_DIR"

# toybox tar 对 ./ 条目报错但实际能解压，忽略该错误
tar xzf "$ROOTFS_FILE" -C "$ALPINE_DIR" 2>/dev/null || true

# 验证
[ -f "$ALPINE_DIR/etc/alpine-release" ] || err "解压失败，未找到 alpine-release"
info "Alpine $(cat "$ALPINE_DIR/etc/alpine-release") 解压完成"

# ── 基础配置 ──

info "配置 DNS 和软件源 ..."
echo "nameserver 8.8.8.8" > "$ALPINE_DIR/etc/resolv.conf"
cat > "$ALPINE_DIR/etc/apk/repositories" << EOF
http://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/main
http://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/community
EOF

# ── 挂载 ──

info "挂载虚拟文件系统 ..."
mkdir -p "$ALPINE_DIR/dev/pts"
mountpoint -q "$ALPINE_DIR/proc"    || mount -t proc proc "$ALPINE_DIR/proc"
mountpoint -q "$ALPINE_DIR/sys"     || mount -t sysfs sysfs "$ALPINE_DIR/sys"
mountpoint -q "$ALPINE_DIR/dev"     || mount -o bind /dev "$ALPINE_DIR/dev"
mountpoint -q "$ALPINE_DIR/dev/pts" || mount -t devpts devpts "$ALPINE_DIR/dev/pts"

# ── 网络修复 ──

# eth0/eth1 没有 IP 但可能抢占默认路由，导致网络不通
# 检测 wlan0 有 IP 时，删掉指向 eth0/eth1 的默认路由
# 注意：OH 的 toybox 没有 awk 和 grep -P，只用 sed/grep 基础功能
WLAN_IP=$(ip addr show wlan0 2>/dev/null | grep "inet " | sed 's/.*inet \([^ ]*\).*/\1/' | head -1)
if [ -n "$WLAN_IP" ]; then
    for iface in eth0 eth1; do
        if ip route show default dev $iface 2>/dev/null | grep -q default; then
            info "删除 $iface 上的默认路由（wlan0 有 IP: $WLAN_IP）"
            ip route del default dev $iface 2>/dev/null || true
        fi
    done
    # 确保 wlan0 有默认路由
    if ! ip route show default dev wlan0 2>/dev/null | grep -q default; then
        GATEWAY=$(ip route show dev wlan0 2>/dev/null | sed -n 's/.*via \([0-9.]*\).*/\1/p' | head -1)
        if [ -z "$GATEWAY" ]; then
            GATEWAY=$(echo "$WLAN_IP" | sed 's|/.*||; s|\.[0-9]*$|.1|')
        fi
        info "添加默认路由: via $GATEWAY dev wlan0"
        ip route add default via "$GATEWAY" dev wlan0 2>/dev/null || true
    fi
fi

# ── 初始化包管理器 ──

info "更新软件源索引 ..."
chroot "$ALPINE_DIR" /bin/sh -c "export PATH=/usr/bin:/usr/sbin:/bin:/sbin; apk update --allow-untrusted" 2>&1

info "安装基础工具 ..."
chroot "$ALPINE_DIR" /bin/sh -c "export PATH=/usr/bin:/usr/sbin:/bin:/sbin; apk add --allow-untrusted bash curl htop tmux openssh" 2>&1

# ── 生成入口脚本 ──

info "生成入口脚本: $ENTER_SCRIPT"
cat > "$ENTER_SCRIPT" << 'ENTER'
#!/bin/sh
ALPINE=/data/alpine

[ -d "$ALPINE/bin" ] || { echo "[!] Alpine 未安装，先运行 install.sh"; exit 1; }

mountpoint -q $ALPINE/proc    || mount -t proc proc $ALPINE/proc
mountpoint -q $ALPINE/sys     || mount -t sysfs sysfs $ALPINE/sys
mountpoint -q $ALPINE/dev     || mount -o bind /dev $ALPINE/dev
mountpoint -q $ALPINE/dev/pts || mount -t devpts devpts $ALPINE/dev/pts

echo "nameserver 8.8.8.8" > $ALPINE/etc/resolv.conf

# 网络修复：删掉没有 IP 的 eth 口上的默认路由
WLAN_IP=$(ip addr show wlan0 2>/dev/null | grep "inet " | sed 's/.*inet \([^ ]*\).*/\1/' | head -1)
if [ -n "$WLAN_IP" ]; then
    for iface in eth0 eth1; do
        ip route del default dev $iface 2>/dev/null
    done
    if ! ip route show default dev wlan0 2>/dev/null | grep -q default; then
        GW=$(echo "$WLAN_IP" | sed 's|/.*||; s|\.[0-9]*$|.1|')
        ip route add default via "$GW" dev wlan0 2>/dev/null
    fi
fi

chroot $ALPINE /bin/sh -l -c "export PATH=/usr/bin:/usr/sbin:/bin:/sbin; exec /bin/sh -l"
ENTER
chmod +x "$ENTER_SCRIPT"

# ── 清理 ──

rm -f "$ROOTFS_FILE"

# ── 完成 ──

info "========================================"
info "  安装完成！"
info "  进入 Linux:  sh $ENTER_SCRIPT"
info "  安装软件:    apk add <包名>"
info "  占用空间:    约 $(du -sh "$ALPINE_DIR" 2>/dev/null | sed 's/[[:space:]].*//')"
info "========================================"
