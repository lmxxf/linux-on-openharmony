#!/bin/sh
# 在板载屏/HDMI 上启动 Weston 桌面
# 前置：OH 侧已经停掉 render_service + composer_host
#
# 用法：
#   sh /root/start-hdmi.sh

export XDG_RUNTIME_DIR=/tmp/runtime-root
mkdir -p $XDG_RUNTIME_DIR
chmod 700 $XDG_RUNTIME_DIR

# 检查 DRM 设备
if [ ! -c /dev/dri/card0 ]; then
    echo "[!] /dev/dri/card0 不存在，chroot 的 /dev 没 bind？"
    exit 1
fi

# 报告 card0 当前占用情况（只警告，不退出）
# codec_host 这种不抢 DRM master 的不挡 weston
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
rm -f /run/seatd.sock

# 起 seatd 后台跑（不要让它按需退出）
# -n 3 = stdin-fd 关掉; 让它纯 daemon
echo "[*] 启动 seatd ..."
mkdir -p /run
seatd -g wheel > /tmp/seatd.log 2>&1 &
SEATD_PID=$!
sleep 2

if ! kill -0 $SEATD_PID 2>/dev/null; then
    echo "[!] seatd 启动失败:"
    cat /tmp/seatd.log
    exit 1
fi

# 等 socket 出现
for i in 1 2 3 4 5; do
    [ -S /run/seatd.sock ] && break
    sleep 1
done

if [ ! -S /run/seatd.sock ]; then
    echo "[!] /run/seatd.sock 没出现:"
    cat /tmp/seatd.log
    exit 1
fi

echo "[*] seatd 就绪 (PID=$SEATD_PID), 启动 weston ..."
# --continue-without-input: chroot 里 udev 数据库不完整，input 设备没 seat tag，
# 让 weston 先把屏幕点亮再说。键盘鼠标可以走 SSH/VNC 远程过来。
LIBSEAT_BACKEND=seatd weston \
    --backend=drm-backend.so \
    --continue-without-input \
    --log=/tmp/weston.log \
    &

WESTON_PID=$!
sleep 3

if ! kill -0 $WESTON_PID 2>/dev/null; then
    echo "[!] weston 启动失败，日志末尾："
    tail -40 /tmp/weston.log 2>/dev/null
    exit 1
fi

echo "[*] Weston 启动成功，PID=$WESTON_PID (seatd PID=$SEATD_PID)"
echo "[*] 日志：/tmp/weston.log"
echo "[*] 屏幕应该已经亮了。如果黑屏，检查 connector 状态和 dmesg"
echo "[*] 停止：sh /root/stop-hdmi.sh"
