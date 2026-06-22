# 开发记录

按时间倒序记录这个项目的每一段独立工作。

---

## 2026-06-23 — 板载屏 / HDMI 直出 Linux 桌面

让 Alpine 桌面直接显示在 RK3568 板载屏 + HDMI 上,不走 VNC。OH 让出 DRM master,Weston 接管。

**核心思路**:`begetctl service_control stop` 安全停 OH 的 render_service / composer_host(绕开 init 的 critical 保护),Alpine chroot 里起 seatd + Weston 14 接管 `/dev/dri/card0`。

**新增文件**:

| 文件 | 用途 |
|------|------|
| `setup-hdmi.sh` | chroot 内一次性装包(weston / weston-backend-drm / seatd / mesa / eudev / kmscube) |
| `start-hdmi.sh` | 起 seatd + Weston,板载 DSI 屏 + HDMI 同屏 |
| `oh-stop-render.sh` | OH 侧停图形栈(begetctl,绕开 critical) |
| `oh-start-render.sh` | OH 侧恢复(或直接 reboot) |
| `RK3568_UI_内置屏幕+hdmi输出.md` | 完整使用手册 + 踩坑记录 |

**踩过的坑**(详见使用手册末尾):

1. RK3568 OH 没 `/dev/fb*`,只能走 DRM/KMS
2. `render_service` 是 critical 服务,直接 kill 会触发 init 重启系统
3. `/` 分区 100% 满,任何 `sed -i` / 文件改写都 `No space left` —— 但 `begetctl` 能用,完全绕开改 cfg
4. Weston 14 把 `weston-backend-drm` 拆成单独子包,主包不带
5. Weston 14 强制 seatd 或 logind,root 不能直接跑;Alpine 不打包 `seatd-launch`,得手动后台起 seatd
6. Weston 14 的 `--tty=` 参数被去掉(VT 由 seatd 管)
7. Alpine 默认 udev 规则不打 `ID_SEAT=seat0`(没有 systemd-logind),要手写规则
8. Mali-G52 闭源 `bifrost_kbase` 占用 GPU,Mesa panfrost 起不来,EGL 退回 llvmpipe 软渲染——纯桌面够用,3D 不行

**遗留**:

- 触屏 input 默认关联到第一个 output(HDMI),板载 DSI 屏触点映射不对——还没写 udev 规则绑定
- VSCode/VSCodium 在 Alpine aarch64 musl 仓库里没有,得走 code-server 路线
- OH 桌面停了之后没法不 reboot 恢复(begetctl `start` 在 stop 过的 critical 服务上无效)

---

## 2026-05-21 — hdc 终端窗口大小(未合并)

试过给 hdc 协议加 `CMD_SHELL_WINSIZE` 命令(PC 端 `SIGWINCH` → 发 8 字节 magic + rows/cols → 设备端 `ioctl(TIOCSWINSZ)`),让 tmux/vim/htop 在 hdc shell 里能正确感知终端尺寸。同步搞了 hdc PC 端独立编译(Linux x86_64 + Windows MinGW 交叉),不依赖整套 SDK。

**结果**:补丁打通了,设备端 hdcd 跟 OH 整包编译,PC 端独立编出 hdc_std。但**没有合并到 OH 主线**,只在本地用过几次,之后被 alpine + dropbear + ssh 这条更稳的方案替代(SSH 客户端原生支持窗口大小通知,不用改 hdc 协议)。

历史代码留在 `build_standalone_linux_host.sh` / `build_standalone_mingw_host.sh` 两个独立编译脚本里,以后想再折腾 hdc 还能用。
