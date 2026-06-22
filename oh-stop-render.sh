#!/bin/sh
#
# OH 侧脚本：安全停掉 render_service，释放 HDMI/DRM 给 Alpine
#
# 危险性提示：
#   - render_service 是 OH 的 critical 服务（graphic.cfg: "critical": [1, 5, 60]）
#   - 直接 kill 会触发 init 的关键服务保护，可能导致系统重启
#   - 必须先把 graphic.cfg 改成非 critical，再 kill
#
# 这个脚本干 3 件事：
#   1. 备份 /etc/init/graphic.cfg → graphic.cfg.bak（恢复用）
#   2. 改 graphic.cfg：去掉 "critical"，加 "disabled" : 1
#   3. kill 现有 render_service / composer_host / foundation 进程
#
# 完成后，DRM/HDMI plane 就空出来给 chroot 里的 weston 用。
#
# 用法（在 hdc shell 里执行，不是 chroot 里）：
#   sh /data/local/tmp/oh-stop-render.sh
#
# 恢复 OH 桌面：
#   sh /data/local/tmp/oh-start-render.sh
#

set -e

CFG=/etc/init/graphic.cfg
BAK=/data/local/tmp/graphic.cfg.bak

info() { echo "[OH] $1"; }
warn() { echo "[OH!] $1"; }
err()  { echo "[OH!] $1" >&2; exit 1; }

# ── 检查 ──

[ -f "$CFG" ] || err "$CFG 不存在"

# 第一次跑时备份
if [ ! -f "$BAK" ]; then
    cp "$CFG" "$BAK"
    info "原始 graphic.cfg 备份到 $BAK"
fi

# ── 改 graphic.cfg ──
#
# OH 的 init.cfg 是 JSON，但格式比较死板：
#   - 用 sed 改 "critical" 和加 "disabled" 是脆的（万一字段名变了）
#   - 但 RK3568 OH 的 graphic.cfg 我们见过，可以针对性改
#
# 改动：
#   "critical" : [1, 5, 60],    → 删掉
#   "once" : 0                   → 保持不变（once: 0 = 不只跑一次，正常）
#   加上 "disabled" : 1           → 让 init 启动时不自动起 render_service
#
# 安全做法：直接用一个新版本的 graphic.cfg 覆盖
# 但是我们不知道完整字段，sed 删除单行最稳

info "patch $CFG："

# 用 sed 删除 critical 那一行
# 原行: "critical" : [1, 5, 60],
sed -i '/"critical"[[:space:]]*:[[:space:]]*\[/d' "$CFG" \
    || err "sed 删除 critical 失败"

# 在 "once" : 0 那一行前插入 "disabled" : 1,
sed -i 's/"once"[[:space:]]*:[[:space:]]*0/"disabled" : 1,\n            "once" : 0/' "$CFG" \
    || err "sed 加 disabled 失败"

info "patch 后的 services 段："
grep -A 2 '"name" : "render_service"' "$CFG" | head -20

# ── 停进程 ──

info "停现有图形进程 ..."

# critical 已去除，可以安全 kill
# 顺序：先停 launcher，再停 foundation，再停 render_service / composer_host
for proc in launcher render_service composer_host foundation; do
    PIDS=$(pidof "$proc" 2>/dev/null || true)
    if [ -n "$PIDS" ]; then
        info "  kill $proc (pid $PIDS)"
        kill $PIDS 2>/dev/null || true
    fi
done

sleep 2

# 第二轮，强制
for proc in launcher render_service composer_host foundation; do
    PIDS=$(pidof "$proc" 2>/dev/null || true)
    if [ -n "$PIDS" ]; then
        warn "  $proc 还在，强杀 (pid $PIDS)"
        kill -9 $PIDS 2>/dev/null || true
    fi
done

# ── 确认 DRM 已释放 ──

sleep 1
if command -v fuser >/dev/null 2>&1; then
    HOLDER=$(fuser /dev/dri/card0 2>&1 | grep -v "^$" || true)
    if [ -n "$HOLDER" ]; then
        warn "/dev/dri/card0 仍被占用：$HOLDER"
        warn "可能还有进程在用 DRM，weston 启动会失败"
    else
        info "/dev/dri/card0 已释放"
    fi
fi

info "========================================"
info "OH 图形栈已停。屏幕现在应该是黑的（这是正常的）。"
info ""
info "下一步（在 hdc shell 里）："
info "  sh /data/local/tmp/alpine-enter.sh"
info "  sh /root/start-hdmi.sh"
info ""
info "恢复 OH 桌面（注意：会立即抢回 HDMI）："
info "  sh /data/local/tmp/oh-start-render.sh"
info "========================================"
