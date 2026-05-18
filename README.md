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

### SSH 远程登录

在 Alpine 里配置 sshd，就可以从局域网直接 SSH 进来，不需要 hdc：

```bash
# Alpine 里执行
ssh-keygen -A
echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
passwd root
/usr/sbin/sshd

# PC 上直接 SSH（替换为设备 IP）
ssh root@<设备IP>
```

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
