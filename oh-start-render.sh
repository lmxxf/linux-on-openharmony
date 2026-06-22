#!/bin/sh
#
# OH 侧脚本：恢复 render_service，把 HDMI 还给 OH 桌面
#
# 配合 oh-stop-render.sh 使用。
#
# 用法（hdc shell 里执行）：
#   sh /data/local/tmp/oh-start-render.sh
#

CFG=/etc/init/graphic.cfg
BAK=/data/local/tmp/graphic.cfg.bak

info() { echo "[OH] $1"; }
warn() { echo "[OH!] $1"; }
err()  { echo "[OH!] $1" >&2; exit 1; }

# ── 恢复 graphic.cfg ──

if [ -f "$BAK" ]; then
    info "恢复 $CFG"
    cp "$BAK" "$CFG"
else
    warn "找不到备份 $BAK，graphic.cfg 维持当前状态"
fi

# ── 起 render_service ──
#
# OH 没有标准的 init.start XXX 命令，但有以下手段：
#   1. 直接跑 /system/bin/render_service（缺 selinux context，可能起不来）
#   2. reboot 让 init 重新解析 cfg 并启动（最稳但慢）
#   3. 用 begetctl service_control（如果有）
#

if command -v begetctl >/dev/null 2>&1; then
    info "尝试用 begetctl 启动 render_service ..."
    begetctl service_control start render_service 2>&1 || warn "begetctl 启动失败，建议 reboot"
else
    warn "没有 begetctl，建议 reboot 让 init 重新加载 graphic.cfg"
fi

info ""
info "如果 HDMI 还是黑屏 / 显示异常："
info "  reboot"
info ""
info "（reboot 后 OH 桌面回来；graphic.cfg 已恢复成原版）"
