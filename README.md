# Linux on OpenHarmony

在 OpenHarmony 设备上一键运行完整的 Linux（Alpine Linux），通过 chroot 实现，零虚拟化开销。

## 原理

OpenHarmony 底层就是 Linux 内核。chroot 只是让内核使用 Alpine 的用户空间（文件系统、包管理器、工具链），不需要虚拟机，不需要额外内核模块，原生性能。

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
# 进入 Linux 环境
hdc shell "sh /data/local/tmp/alpine-enter.sh"

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
apk add gcc musl-dev  # C 编译器
apk add nodejs npm    # Node.js
apk add git           # Git
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
