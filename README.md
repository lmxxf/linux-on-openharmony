# Linux on OpenHarmony

在 OpenHarmony 设备上一键运行完整的 Linux（Alpine Linux），通过 chroot 实现，零虚拟化开销。

## 特性

- 一键部署：Windows PowerShell 脚本，自动完成全部安装配置
- XFCE4 桌面 + Firefox 浏览器，通过 VNC 远程访问
- SSH 远程登录（dropbear，适配 chroot 环境）
- Alpine 仓库 25000+ 软件包可用
- 与 OH 共享内核，原生性能，零虚拟化开销

## 快速开始

### 环境要求

- OpenHarmony 设备（aarch64，root 权限）
- PC 端安装 `hdc` 工具
- 网络连接（安装软件包时需要）
- [alpine-minirootfs-3.21.3-aarch64.tar.gz](https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/aarch64/alpine-minirootfs-3.21.3-aarch64.tar.gz) 放在项目目录下

### 一键部署（Windows PowerShell）

```powershell
.\deploy.ps1
```

自动完成：推送文件 -> 安装 Alpine -> 安装 SSH + VNC + XFCE4 桌面 + Firefox + 中文字体。

### 部署后设置

```bash
# 进入 Alpine
hdc shell
sh /data/local/tmp/alpine-enter.sh

# 设置 root 密码（首次必须）
passwd root

# 启动所有服务（SSH + VNC 桌面）
sh ~/start-services.sh 1920x1080
```

### 连接

**SSH（通过 USB 端口转发，不依赖网络）：**

```powershell
hdc fport tcp:2222 tcp:22
ssh root@127.0.0.1 -p 2222
```

**VNC 桌面：**

VNC 客户端连接 `<设备IP>:5900`，即可看到 XFCE4 桌面和 Firefox 浏览器。

## 手动安装

如果不用一键部署脚本，也可以分步操作：

```bash
# 1. 推送并安装 Alpine
hdc file send install.sh /data/local/tmp/install.sh
hdc file send alpine-minirootfs-3.21.3-aarch64.tar.gz /data/local/tmp/alpine-minirootfs.tar.gz
hdc shell "sh /data/local/tmp/install.sh"

# 2. 进入 Alpine
hdc shell
sh /data/local/tmp/alpine-enter.sh

# 3. 部署桌面环境（在 Alpine 内执行）
# 把 setup-desktop.sh 推到设备后：
sh /tmp/setup-desktop.sh
```

## 卸载

> **不要直接 `rm -rf /data/alpine`**，挂载点没卸载会删到宿主系统的 `/dev` 和 `/sys`。

```bash
hdc file send uninstall.sh /data/local/tmp/uninstall.sh
hdc shell "sh /data/local/tmp/uninstall.sh"
```

## 文档

- [安装配置细节](OpenHarmony安装linux细节.md) — 代理上网、共享目录、网络修复、tmux 等详细说明
- [RK3588 欧拉桌面浏览器安装指南](3588欧拉桌面浏览器安装指南.md) — 欧拉 Linux 上的 VNC + Firefox 安装
- [hdc 开发记录](DevHistory.md) — hdc 终端窗口大小支持 + PC 端独立编译

## 技术细节

| 项目 | 说明 |
|------|------|
| 宿主系统 | OpenHarmony（Linux 6.6 内核） |
| 客户系统 | Alpine Linux 3.21（aarch64） |
| 隔离方式 | chroot（非虚拟机，非容器） |
| 性能损耗 | 无 |
| 安装位置 | `/data/alpine` |
| SSH | dropbear（OpenSSH 在 chroot 下 privilege separation 失败） |
| VNC | Xvfb + x11vnc + XFCE4 |
| 浏览器 | Firefox |

## 文件说明

| 文件 | 用途 |
|------|------|
| `deploy.ps1` | Windows 一键部署脚本 |
| `install.sh` | Alpine 基础安装 |
| `setup-desktop.sh` | SSH + VNC + 桌面环境部署 |
| `uninstall.sh` | 安全卸载 |
| `build_standalone_linux_host.sh` | hdc PC 端独立编译（Linux） |
| `build_standalone_mingw_host.sh` | hdc PC 端交叉编译（Windows） |

## License

MIT
