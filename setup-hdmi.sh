#!/bin/sh
#
# Alpine on OpenHarmony — HDMI 直出方案（路线 3：Alpine 独占显卡）
#
# 前置条件：已执行 install.sh 装好 Alpine，已通过 alpine-enter.sh 进入 chroot。
#
# 用法（在 Alpine chroot 里执行）：
#   sh /shared/setup-hdmi.sh
#
# 安装内容：
#   - weston（Wayland 参考实现，DRM backend）
#   - seatd（DRM/input 设备访问权限管理，非 root 也能用，但我们用 root）
#   - mesa-dri-gallium（用户态 DRM 驱动，包含 panfrost 给 Mali-G52）
#   - 几个测试工具：weston-terminal、kmscube、libinput
#
# 不动 X11 那条链路，VNC 桌面继续可用。这是平行的 HDMI 输出方案。
#

info() { echo "[*] $1"; }
warn() { echo "[!] $1"; }
err()  { echo "[!] $1" >&2; exit 1; }

[ -f /etc/alpine-release ] || err "请先进入 Alpine 环境（sh alpine-enter.sh）"

info "Alpine $(cat /etc/alpine-release) 检测到"

# ── 安装包 ──

info "更新软件源 ..."
rm -f /lib/apk/db/lock
apk update --allow-untrusted || err "apk update 失败，检查网络"

# weston 拉 wayland + libdrm + mesa
# panfrost 是 RK3568 上 Mali-G52 的开源驱动，能跑 GLES2/3
# eudev 提供 /dev 节点的 uevent 处理（chroot 下 input/drm 节点已经 bind 进来了，不一定需要）
PACKAGES="weston weston-backend-drm weston-terminal weston-shell-desktop seatd \
          mesa-dri-gallium mesa-egl mesa-gles \
          libinput libinput-tools \
          kmscube \
          eudev"

info "安装包（已装的会跳过）..."
apk add --allow-untrusted $PACKAGES || err "软件包安装失败"

# ── 配置 XDG runtime dir ──

# Wayland 需要 XDG_RUNTIME_DIR
mkdir -p /tmp/runtime-root
chmod 700 /tmp/runtime-root

# ── 生成启动脚本 ──

info "生成 /root/start-hdmi.sh ..."

cat > /root/start-hdmi.sh << 'STARTHDMI'
#!/bin/sh
# 在 HDMI 上启动 Weston 桌面
# 前置：OH 侧已经停掉 render_service（否则 DRM master 冲突）
#
# 用法：
#   sh /root/start-hdmi.sh             # 默认参数，让 weston 自己挑分辨率
#   WIDTH=1920 HEIGHT=1080 sh /root/start-hdmi.sh

export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p $XDG_RUNTIME_DIR
chmod 700 $XDG_RUNTIME_DIR

# 检查 DRM 设备
if [ ! -c /dev/dri/card0 ]; then
    echo "[!] /dev/dri/card0 不存在，chroot 的 /dev 没 bind？"
    exit 1
fi

# 报告 card0 当前占用情况（只警告，不退出 —— codec_host 这种不抢 master 的不挡 weston）
HOLDERS=""
for p in /proc/[0-9]*; do
    if ls -l "$p/fd" 2>/dev/null | grep -q "/dev/dri/card0"; then
        HOLDERS="$HOLDERS $(cat "$p/comm" 2>/dev/null)($(basename "$p"))"
    fi
done
[ -n "$HOLDERS" ] && echo "[*] card0 当前占用:$HOLDERS  (weston 会尝试抢 DRM master)"

# 杀掉旧的 weston/seatd
pkill -f weston 2>/dev/null
pkill -f seatd 2>/dev/null
sleep 1

# root 跑 weston，不走 seatd（root 直接 open DRM/input，不需要中介）
# 必须用 launcher=direct，否则 weston 默认找 logind/seatd 失败
weston \
    --backend=drm-backend.so \
    --tty=/dev/tty1 \
    --log=/tmp/weston.log \
    -- \
    &

WESTON_PID=$!
sleep 3

if ! kill -0 $WESTON_PID 2>/dev/null; then
    echo "[!] weston 启动失败，查日志：cat /tmp/weston.log"
    tail -30 /tmp/weston.log 2>/dev/null
    exit 1
fi

echo "[*] Weston 启动成功，PID=$WESTON_PID"
echo "[*] 日志：/tmp/weston.log"
echo "[*] 屏幕应该已经亮了。如果黑屏，检查 HDMI 连接和 dmesg"
echo "[*] 停止：sh /root/stop-hdmi.sh"
STARTHDMI
chmod +x /root/start-hdmi.sh

cat > /root/stop-hdmi.sh << 'STOPHDMI'
#!/bin/sh
# 停 Weston 桌面，释放 DRM
pkill -f weston 2>/dev/null
pkill -f seatd 2>/dev/null
sleep 1
echo "[*] HDMI 桌面已停"
echo "[*] 如要恢复 OH 桌面：sh /data/local/tmp/oh-start-render.sh（在 OH shell 里执行）"
STOPHDMI
chmod +x /root/stop-hdmi.sh

# ── 完成 ──

info "========================================"
info "  HDMI 方案准备完成。"
info ""
info "  接下来在 OH 侧（不是 Alpine chroot 里）："
info "    1. 停掉 OH 的 render_service（脚本：oh-stop-render.sh）"
info "    2. 进 chroot，跑 sh /root/start-hdmi.sh"
info ""
info "  HDMI 桌面起来后，键盘鼠标直接接到板子上用。"
info "  回到 VNC：sh /root/stop-hdmi.sh，再 sh /data/local/tmp/oh-start-render.sh"
info "========================================"
