#!/bin/sh
#
# Alpine on OpenHarmony — 一键部署 SSH + VNC 桌面 + Firefox
#
# 前置条件：已执行 install.sh 安装 Alpine，已进入 Alpine 环境（alpine-enter.sh）
#
# 用法：
#   方式一（推荐）：在 Alpine 内直接执行
#     sh /shared/setup-desktop.sh
#
#   方式二：从 OH 侧 chroot 执行
#     hdc shell
#     chroot /data/alpine /bin/sh -c "sh /shared/setup-desktop.sh"
#
# 安装内容：
#   - dropbear（SSH 服务端，替代 OpenSSH，适合 chroot 环境）
#   - Xvfb + x11vnc（VNC 服务）
#   - XFCE4 桌面环境
#   - Firefox 浏览器
#   - 中文字体（Noto Sans CJK）
#
# 支持重复执行：已安装的软件包会跳过，脚本文件会覆盖更新。
#

set -e

info() { echo "[*] $1"; }
warn() { echo "[!] $1"; }
err()  { echo "[!] $1" >&2; exit 1; }

# ── 前置检查 ──

[ -f /etc/alpine-release ] || err "请先进入 Alpine 环境（sh alpine-enter.sh）"

info "Alpine $(cat /etc/alpine-release) 检测到"

# ── 网络检查 ──

info "检查网络连接 ..."
if ! wget -q --spider --timeout=5 http://dl-cdn.alpinelinux.org 2>/dev/null; then
    warn "无法连接 Alpine 软件源！"
    warn "请检查："
    warn "  1. 设备 WiFi 是否已连接"
    warn "  2. 默认路由是否正确（ip route，确认 default 走 wlan0）"
    warn "  3. 系统时间是否正确（date，时间错会导致 SSL 失败）"
    warn "  4. 如需翻墙，设置 http_proxy/https_proxy 环境变量"
    err "网络不通，无法安装软件包"
fi
info "网络正常"

# ── 安装软件包 ──

info "更新软件源索引 ..."
rm -f /lib/apk/db/lock
apk update --allow-untrusted

PACKAGES="dropbear xvfb x11vnc xfce4 xfce4-terminal dbus firefox font-noto-cjk"

info "安装软件包（已安装的会跳过）..."
apk add --allow-untrusted $PACKAGES

# ── 配置 SSH ──

info "配置 SSH ..."
mkdir -p /etc/dropbear
[ -f /etc/dropbear/dropbear_ecdsa_host_key ] || dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key

# ── 配置 VNC ──

info "配置 VNC 启动脚本 ..."
mkdir -p /root/.vnc

cat > /root/start-vnc.sh << 'VNCSCRIPT'
#!/bin/sh
# 启动 VNC 桌面
# 用法: sh /root/start-vnc.sh [分辨率]
# 例如: sh /root/start-vnc.sh 1920x1080

RESOLUTION=${1:-1920x1080}
DISPLAY_NUM=:1
VNC_PORT=5900

# 清理之前的进程
pkill -f "Xvfb ${DISPLAY_NUM}" 2>/dev/null || true
pkill -f "x11vnc.*${DISPLAY_NUM}" 2>/dev/null || true
pkill -f xfwm4 2>/dev/null || true
pkill -f xfce4-terminal 2>/dev/null || true
pkill -f firefox 2>/dev/null || true
sleep 1

# 启动虚拟显示
Xvfb ${DISPLAY_NUM} -screen 0 ${RESOLUTION}x24 &
sleep 1

export DISPLAY=${DISPLAY_NUM}

# 启动窗口管理器（不用 xfce4-session，chroot 下会话管理不正常）
xfwm4 &
sleep 1

# 启动终端和浏览器
xfce4-terminal &
firefox &
sleep 2

# 启动 VNC 服务（无密码，局域网用）
# 如需密码：先运行 x11vnc -storepasswd，然后加 -rfbauth /root/.vnc/passwd
x11vnc -display ${DISPLAY_NUM} -forever -shared -rfbport ${VNC_PORT} -bg -nopw -noshm

echo "[*] VNC 已启动"
echo "[*] 分辨率: ${RESOLUTION}"
echo "[*] 连接地址: <设备IP>:${VNC_PORT}"
echo "[*] 停止: sh /root/stop-vnc.sh"
VNCSCRIPT
chmod +x /root/start-vnc.sh

cat > /root/stop-vnc.sh << 'STOPSCRIPT'
#!/bin/sh
pkill -f x11vnc 2>/dev/null
pkill -f firefox 2>/dev/null
pkill -f xfce4-terminal 2>/dev/null
pkill -f xfwm4 2>/dev/null
pkill -f Xvfb 2>/dev/null
echo "[*] VNC 已停止"
STOPSCRIPT
chmod +x /root/stop-vnc.sh

# ── 配置 SSH + VNC 一键启动 ──

cat > /root/start-services.sh << 'STARTALL'
#!/bin/sh
# 一键启动 SSH + VNC
echo "[*] 启动 SSH（端口 22）..."
dropbear -R -p 22 2>/dev/null || echo "[*] SSH 已在运行"
echo "[*] 启动 VNC 桌面 ..."
sh /root/start-vnc.sh "$@"
STARTALL
chmod +x /root/start-services.sh

# ── 完成 ──

info "========================================"
info "  部署完成！"
info ""
info "  设置 root 密码（首次必须）："
info "    passwd root"
info ""
info "  一键启动所有服务："
info "    sh /root/start-services.sh [分辨率]"
info "    sh /root/start-services.sh 1920x1080"
info "    sh /root/start-services.sh 2560x1440"
info ""
info "  单独启动："
info "    SSH:  dropbear -R -p 22"
info "    VNC:  sh /root/start-vnc.sh"
info ""
info "  SSH 连接（通过 hdc 端口转发）："
info "    PC 端: hdc fport tcp:2222 tcp:22"
info "    PC 端: ssh root@127.0.0.1 -p 2222"
info ""
info "  VNC 连接（通过 hdc 端口转发）："
info "    PC 端: hdc fport tcp:5900 tcp:5900"
info "    VNC 客户端连接 127.0.0.1:5900"
info ""
info "  停止 VNC："
info "    sh /root/stop-vnc.sh"
info "========================================"
