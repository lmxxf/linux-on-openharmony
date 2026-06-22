# RK3568 板载屏 + HDMI 输出 Linux 桌面

让 Alpine Linux 桌面直接出现在 OpenHarmony 设备的**板载屏**和/或 **HDMI 接口**上(不走 VNC),板子变 Linux 工作站。

## 适用

- RK3568 + OpenHarmony(Linux 6.6 内核,DRM/KMS 完整)
- 已按主 README 装好 Alpine(`/data/alpine`)
- 板子有板载 DSI 屏 / HDMI 接口至少其一

## 效果

跑完这套流程,板子会:

- ✅ 板载 DSI 屏显示 Alpine + Weston 桌面
- ✅ HDMI 同时输出(扩展屏)
- ✅ USB 键鼠 / 板载触屏可用
- ⚠️ GPU 加速没有(Mesa 软渲染 llvmpipe),桌面够用,3D 游戏算了
- ⚠️ OH 桌面消失(我们抢了 DRM master)

恢复 OH 桌面: `reboot` 即可,所有改动都是运行时的,不持久化。

## 前置:Alpine 已装好

参考主 [README.md](README.md)。确认能进 chroot:

```bash
hdc shell
sh /data/local/tmp/alpine-enter.sh
# 看到 localhost:~# 即成功
```

## 一、装 Weston 等组件(只在 Alpine 装一次)

在 chroot 里:

```sh
sh /root/setup-hdmi.sh
```

(setup-hdmi.sh 在仓库里,首次部署时 push 进 chroot)

装好后退出 chroot:

```sh
exit
```

## 二、停掉 OH 图形栈(每次开机要做)

回到 hdc shell(不是 chroot),按顺序跑:

```sh
# 1. 让 / 分区可写(为了改 udev 规则等;OH 的 / 默认只读)
mount -o remount,rw /

# 2. 安全停掉 render_service 和 composer_host
#    用 begetctl,触发 init 的协议停止,不会被 critical 保护重启
begetctl service_control stop render_service
begetctl service_control stop composer_host
```

**屏幕会黑掉**——这是正常的,OH 的合成器停了。hdc 仍连通。

如果你担心副作用,确认一下:

```sh
pidof render_service composer_host
# 应该没有输出
```

## 三、起 Weston(每次开机要做)

进 chroot:

```sh
sh /data/local/tmp/alpine-enter.sh
```

第一次跑要建 udev 数据库 + 写 seat 规则(后面只跑这次):

```sh
# 起 udev daemon
udevd --daemon

# 让 udev 扫所有设备,生成元数据
udevadm trigger --type=devices --action=add
udevadm settle

# 写 seat 规则:把所有 input/drm 设备打 seat0 标签
# (Alpine 没有 systemd-logind,需要手动告诉 libseat 设备属于谁)
cat > /etc/udev/rules.d/70-seat.rules << 'EOF'
SUBSYSTEM=="input", TAG+="seat", ENV{ID_SEAT}="seat0"
SUBSYSTEM=="drm", TAG+="seat", ENV{ID_SEAT}="seat0"
EOF

# 重新加载规则并触发
udevadm control --reload
udevadm trigger --type=devices --action=change
udevadm settle

# 验证 input 设备已经打了 seat 标签
udevadm info /dev/input/event0 | grep SEAT
# 应该看到: E: ID_SEAT=seat0
```

启动桌面:

```sh
sh /root/start-hdmi.sh
```

屏幕亮起 Weston 灰色背景。

**热插拔说明**: Weston 14 启动时枚举一次 connector。
- 想要 HDMI 输出: **先插好 HDMI 线再跑 start-hdmi.sh**。后插的 HDMI 不会被识别。
- 想要纯板载屏: HDMI 拔掉跑即可。

## 四、收工(关 Linux 桌面)

在 chroot 里:

```sh
sh /root/stop-hdmi.sh
```

OH 的合成器**不会自动回来**(它被 stop 过 init 不重启它),屏幕保持黑。
如果想回到 OH 桌面,最简单:

```sh
exit              # 出 chroot
reboot            # OH 桌面回来
```

(我们的所有改动都是运行时的,reboot 后全复位。)

## 故障速查

### Q: start-hdmi.sh 报 `card0 当前占用: composer_host(xxx)`,weston 起不来?

A: OH 图形栈没真停干净。回到 hdc shell 再跑:

```sh
begetctl service_control stop render_service
begetctl service_control stop composer_host
```

### Q: weston.log 报 `XDG_RUNTIME_DIR is not set`?

A: 你绕过 start-hdmi.sh 手敲了 weston。先 `export XDG_RUNTIME_DIR=/tmp/runtime-root` 再敲。

### Q: weston.log 报 `seatd: Could not connect to socket /run/seatd.sock`?

A: seatd daemon 没跑或者退了。Alpine 的 seatd 没有 seatd-launch 工具,要单独后台起:

```sh
seatd -g wheel > /tmp/seatd.log 2>&1 &
```

然后再起 weston。**start-hdmi.sh 已经包了这个**,出问题用脚本而不是手敲。

### Q: weston.log 报 `no input devices`?

A: udev 没起或者 seat 规则没写,跑第三章里那一段 udev 初始化命令。

### Q: 触屏戳板载屏,光标在 HDMI 屏上动?

A: Weston 默认把所有 input 关联到第一个 output(`(none by udev)` 表示没显式绑定)。
修法: 给 event5 写条 udev 规则绑到 DSI-1。但这个比较细,等用上再调。

### Q: 屏幕亮了,但只有壁纸 + 顶栏一个图标,没东西可点?

A: Weston 自带的 `desktop-shell` 极简,只有左上角一个 launcher。点那个图标(或顶栏对应位置)能开 `weston-terminal`。从终端可以起 firefox、xterm 等任何东西。

如果想要 XFCE4 那种正经桌面,得换 X11 路线(主 README 里那个,但要拆掉 VNC 让 Xorg 直接用 DRM)。

### Q: 怎么搞 VSCode?

A: Alpine 仓库**没有** VSCode 也没有 VSCodium 的 aarch64 musl 包。
推荐路: 装 `nodejs npm`,`npm i -g code-server`,浏览器开 `localhost:8080`。
野路子: 微软官方 .tar.gz aarch64 + `apk add gcompat`(glibc 兼容层)。能跑,不稳。

## 技术原理(踩坑记录)

这一路踩了几个坑,简单记录,免得下次重蹈:

### 1. RK3568 的 OH 没有 `/dev/fb*`,只有 DRM

OH 关掉了 fbdev 兼容,Linux 老式 framebuffer 那套(`Xorg -fbdev` / `fbcon`)走不通。**必须走 DRM/KMS**。这反而是好事,KMS 是现代正路。

### 2. render_service 是 critical 服务,直接 kill 会触发系统重启

`/etc/init/graphic.cfg` 里 render_service 标了 `"critical": [1, 5, 60]`——5 秒内死 1 次,init 重启整个系统。

**第一次重启原因**: HDMI 热插拔触发 HDF 输入驱动 NULL 指针刷屏(`[E/HDF_INPUT_DRV] hdfInDev is NULL`),最终拖死了 OH 图形栈,critical 保护启动,系统重启。

**正确停法**: `begetctl service_control stop render_service`——这是 init 协议级的"我同意停",不算 crash,不触发保护。

### 3. `/` 分区是 100% 满的,sed -i 改 cfg 行不通

OH 的 system 分区按精确大小做镜像,剩 0 字节。任何"原地修改"的命令(sed -i、tee 之类)都会 `No space left on device`。

幸运的是 begetctl 能用,根本不用改 cfg,这条路完全绕开。

### 4. Weston 14 的几个 API 变动(我们踩到的)

- `weston-backend-drm` 是单独的子包,不在 `weston` 主包里(老版本是带的)
- 强制 seatd 或 logind,root 不能直接跑 weston(老版本能)
- `--tty=/dev/tty1` 参数被去掉了(VT 由 seatd 管)
- `seatd-launch` 工具 Alpine 不打包,得手动后台起 seatd

### 5. udev seat 规则必须显式写

Alpine 没有 systemd-logind,默认 udev 规则不会给设备打 `ID_SEAT=seat0` 属性。
libseat 找不到 seat 归属,weston 就报 "no input devices"。

七字总结: **手动 echo 规则到 `/etc/udev/rules.d/70-seat.rules`**。

### 6. GPU 加速暂时没有

RK3568 的 Mali-G52 在 OH 里挂着闭源 `bifrost_kbase` 内核模块,占用着 `/dev/mali0`。
Alpine 用 Mesa panfrost(开源),走 `/dev/dri/renderD128`,但底层硬件被闭源占着初始化失败,EGL 回退到 llvmpipe 软渲染。

**实测**: 720x1280 + HDMI 1080p 双屏,纯桌面 + 终端 + 文本编辑流畅。Firefox 能开,网页滚动有点钝。不适合视频和游戏。

要真用 GPU,得卸 bifrost 内核模块再起 panfrost——但 OH 里 bifrost 是 builtin 还是模块要看具体编译,这条以后再研究。
