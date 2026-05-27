# Linux on OpenHarmony

在 OpenHarmony 设备上一键运行完整的 Linux（Alpine Linux），通过 chroot 实现，零虚拟化开销。

## 原理

OpenHarmony 底层就是 Linux 内核。本项目通过 `chroot` 把根目录切换到 Alpine Linux 的文件系统，让你在 OH 设备上直接使用完整的 Linux 用户空间（包管理器、工具链、开发环境）。

具体流程：

1. 将 Alpine rootfs 解压到 `/data/alpine`
2. 挂载 `/proc`、`/sys`、`/dev`（让 Alpine 能访问内核的虚拟文件系统）
3. `chroot /data/alpine /bin/sh` 切换根目录，进入 Alpine 环境

**不是虚拟机，不是容器**。Alpine 和 OH 共享同一个 Linux 内核、进程空间和网络栈，没有任何虚拟化开销，原生性能。代价是没有 namespace 隔离——Alpine 里能看到 OH 的所有进程，`kill` 也能杀掉 OH 的进程，操作时注意。

## 环境要求

- OpenHarmony 设备（aarch64）
- root 权限
- 网络连接（安装软件包时需要）
- `hdc` 工具（PC 端）
- 约 50MB 可用存储（基础安装）

## 安装

```bash
# 1. 推送到设备
hdc file send install.sh /data/local/tmp/install.sh
hdc file send alpine-minirootfs-3.21.3-aarch64.tar.gz /data/local/tmp/alpine-minirootfs.tar.gz

# 2. 执行安装
hdc shell "sh /data/local/tmp/install.sh"
```

安装过程自动完成：解压 Alpine rootfs → 配置 DNS 和软件源 → 挂载虚拟文件系统 → 安装基础工具（bash、curl、htop、openssh）。

## 使用

```bash
# 先连接设备
hdc shell

# 再进入 Linux 环境
sh /data/local/tmp/alpine-enter.sh

# 安装软件（在 Alpine 里）
apk add python3 gcc git nodejs

# 卸载软件
apk del python3

# 退出
exit
```

### 可以装什么

Alpine 仓库有 25000+ 个包，随便装：

```bash
apk add python3       # Python
apk add openjdk17     # Java 17
apk add gcc musl-dev  # C 编译器
apk add nodejs npm    # Node.js
apk add git           # Git
apk add tmux          # 终端复用
apk add openssh       # SSH 服务
apk add vim           # 编辑器
```

### Python 开发环境

```bash
# 基础安装（CPython 3.12 + pip）
apk add python3 py3-pip

# 需要编译 C 扩展的包（numpy、pandas 等）时，补装编译工具链
apk add python3-dev gcc musl-dev linux-headers

# 常用科学计算包（Alpine 预编译版，比 pip install 快得多）
apk add py3-numpy py3-pandas py3-scipy py3-matplotlib

# 或者用 pip
pip install requests flask
```

`apk search py3-` 可以查看所有预编译的 Python 包。

### 代理上网（翻墙）

OH 设备通过手机热点上网时，可以走手机上的 Clash 代理访问外网：

```bash
# 设置代理（192.168.152.190 是手机热点 IP，7897 是 Clash 端口）
export http_proxy=http://192.168.152.190:7897
export https_proxy=http://192.168.152.190:7897

# Alpine 的 SSL 证书路径和 OH 系统的不同，需要修正
apk add ca-certificates
export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt

# 验证
curl -I https://www.google.com
```

手机端 Clash 需要开启「允许局域网连接」（Allow LAN），否则只监听 127.0.0.1。

如果 `apk` 报 `Unable to lock database`，先清锁文件：

```bash
rm -f /lib/apk/db/lock
```

写进 shell profile 免得每次手动设：

```bash
cat >> ~/.profile << 'EOF'
export http_proxy=http://192.168.152.190:7897
export https_proxy=http://192.168.152.190:7897
export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
EOF
```

### 共享目录

chroot 进 Alpine 后根目录变成了 `/data/alpine`，看不到 OH 侧的文件。通过 bind mount 建一个共享目录：

```bash
# OH 侧执行（alpine-enter.sh 之前或之后都行）
mkdir -p /data/alpine/shared
mount -o bind /data/local/tmp /data/alpine/shared
```

之后 OH 侧写 `/data/local/tmp/xxx`，Alpine 里就能在 `/shared/xxx` 看到，反之亦然。用 `hdc file send` 推到 `/data/local/tmp` 的文件，Alpine 里直接就能用。

### 网络修复

OH 设备可能有多个网口（eth0、eth1、wlan0），没有 IP 的 eth0/eth1 可能抢占默认路由，导致网络不通：

```bash
# 查看当前路由
ip route

# 如果 default 指向 eth0 而不是 wlan0，删掉它
ip route del default dev eth0

# 确保 default 走 wlan0（网关地址看你的路由器）
ip route add default via 192.168.7.1 dev wlan0

# 验证
ping -c 1 8.8.8.8
```

### SSH 远程登录

在 Alpine 里用 dropbear（轻量 SSH 服务端）开启 SSH 服务。不用 OpenSSH 的 sshd，因为 OpenSSH 9.9 的 privilege separation 在 chroot 环境下会失败（降权后发现能恢复 gid，认为不安全直接退出）。

```bash
# Alpine 里执行
apk add dropbear
passwd root
dropbear -R -p 22

# 通过 hdc 端口转发连接（USB，不依赖网络）
# PC 端执行：
hdc fport tcp:2222 tcp:22
ssh root@127.0.0.1 -p 2222

# 或通过局域网直接连接（需要网络互通）
ssh root@<设备IP>
```

> 注意：手机热点通常开启了 AP 隔离，热点下的设备之间不能互通。这种情况下用 hdc fport 走 USB 转发。

### VNC 桌面 + Firefox 浏览器

`setup-desktop.sh` 会自动安装以下组件：

- **Xvfb** — 虚拟帧缓冲（无需物理显示器）
- **x11vnc** — VNC 服务端
- **XFCE4** — 轻量桌面环境（Alpine 仓库有完整包，不像欧拉只有空壳）
- **Firefox** — 浏览器
- **font-noto-cjk** — 中文字体
- **fcitx5 + fcitx5-chinese-addons** — 中文输入法

手动安装：

```bash
apk add xvfb x11vnc xfce4 xfce4-terminal dbus firefox font-noto-cjk fcitx5 fcitx5-chinese-addons
```

启动 VNC 桌面：

```bash
sh /root/start-vnc.sh              # 默认 1920x1080
sh /root/start-vnc.sh 2560x1440    # 自定义分辨率
```

停止：

```bash
sh /root/stop-vnc.sh
```

连接方式：

```bash
# PC 端映射端口（USB 连接时必须）
hdc fport tcp:5900 tcp:5900

# VNC 客户端连接 127.0.0.1:5900
```

### 中文输入法

`setup-desktop.sh` 会自动安装 fcitx5 并在 VNC 启动时加载。切换输入法快捷键：`Ctrl+Space`。

如需手动配置：

```bash
apk add fcitx5 fcitx5-chinese-addons

# 设置环境变量（加到 ~/.profile 或 start-vnc.sh 里）
export GTK_IM_MODULE=fcitx
export QT_IM_MODULE=fcitx
export XMODIFIERS=@im=fcitx

# 启动
fcitx5 -d
```

> **为什么不用 tigervnc？** Alpine 仓库里有 tigervnc，但 Xvfb + x11vnc 的组合更轻量，配置更简单，在 chroot 环境下兼容性更好。

> **为什么不用 OpenSSH？** OpenSSH 9.9 的 privilege separation 在 chroot 环境下会失败——sshd 降权后发现能恢复 gid，认为不安全直接退出（status 255）。dropbear 没有这个机制，专为嵌入式/受限环境设计。

### tmux 保持会话

hdc 断开后 Alpine 里正在运行的进程会被杀掉。用 tmux 可以让会话在后台保持运行：

```bash
# 在 Alpine 里
tmux                    # 新建会话
tmux new -s work        # 新建命名会话

# tmux 快捷键（先按 Ctrl+b，再按对应键）
# d     断开会话（后台保持运行）
# c     新建窗口
# n/p   下一个/上一个窗口
# %     左右分屏
# "     上下分屏

# 重新连回
tmux attach -t work     # 连回命名会话
tmux ls                 # 列出所有会话
```

下次 `hdc shell` 进来后重新执行 `alpine-enter.sh`，再 `tmux attach` 就能接回之前的会话。

## 卸载

> **不要直接 `rm -rf /data/alpine`**，挂载点没卸载会删到宿主系统的 `/dev` 和 `/sys`。

```bash
hdc file send uninstall.sh /data/local/tmp/uninstall.sh
hdc shell "sh /data/local/tmp/uninstall.sh"
```

## 已知限制

- **SELinux**：OH 默认 Enforcing，某些操作可能被拦截。必要时 `setenforce 0` 临时关闭
- **重启后挂载点丢失**：设备重启后需要重新执行 `alpine-enter.sh`（它会自动重新挂载）
- **共享内核**：Alpine 和 OH 共享同一个 Linux 内核，Alpine 里的 `kill -9` 能杀 OH 的进程，小心操作

## 技术细节

| 项目 | 说明 |
|------|------|
| 宿主系统 | OpenHarmony（Linux 6.6 内核） |
| 客户系统 | Alpine Linux 3.21（aarch64） |
| 隔离方式 | chroot（非虚拟机，非容器） |
| 性能损耗 | 无 |
| 安装位置 | `/data/alpine` |
| 入口脚本 | `/data/local/tmp/alpine-enter.sh` |

## License

MIT
