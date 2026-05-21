# hdc 终端窗口大小支持 — 开发记录

## 问题

hdc shell 已有完整的 PTY 支持（设备端用 `/dev/ptmx` 创建伪终端），但没有传递终端窗口大小（TIOCSWINSZ），导致 tmux、vim、htop 等全屏程序不知道终端尺寸，显示混乱。

## 方案

在 hdc 协议中新增 `CMD_SHELL_WINSIZE` 命令，PC 端获取本地终端大小发给设备端，设备端用 `ioctl(TIOCSWINSZ)` 设置 PTY。

### 数据格式

PC 端通过 shell 交互数据通道发送 8 字节消息：

```
字节 0-3: magic "\x00WSZ" （区分普通 shell 数据）
字节 4-5: rows (uint16, big-endian)
字节 6-7: cols (uint16, big-endian)
```

server_for_client 在 `interactiveShellMode` 下识别 magic 前缀，将其转为 `CMD_SHELL_WINSIZE` 命令转发给 daemon，而非当作 `CMD_SHELL_DATA`。

### 改动文件（基于 OH6 源码）

| 文件 | 归属 | 改动 |
|------|------|------|
| `src/common/define_enum.h` | 公共 | 新增 `CMD_SHELL_WINSIZE = 2002` |
| `src/daemon/shell.cpp` | hdcd（设备端） | 处理 `CMD_SHELL_WINSIZE`，用 `ioctl(fdPTY, TIOCSWINSZ, &ws)` 设置 PTY 窗口大小 |
| `src/host/server_for_client.cpp` | hdc（PC 端） | `CMD_SHELL_WINSIZE` 加入转发列表；interactiveShellMode 下识别 `\x00WSZ` magic 前缀 |
| `src/host/client.cpp` | hdc（PC 端） | 新增 `SendWinsize()` 获取本地终端大小并发送；新增 `SIGWINCH` handler 窗口 resize 时重发；连接 shell 后立即发一次初始大小 |
| `src/host/client.h` | hdc（PC 端） | 声明 `SendWinsize()`、`WinsizeCallback()`、`sigWinch` 成员 |

### 改动补丁

已打包到 `C:\work\transfer\hdc-winsize-patch.tar.gz`，保留了相对于 OH 源码根目录的路径结构。

解压方式：

```bash
cd /path/to/oh6/source
tar xzf hdc-winsize-patch.tar.gz
```

会覆盖 `developtools/hdc/src/` 下的 5 个文件。

## 编译

### hdcd（设备端 daemon）

随 OH 整包编译即可，刷机后自动部署到设备：

```bash
./build.sh --product-name taihang3100 --ccache
```

### hdc（PC 端命令行工具）

OH 构建系统只编译设备端（aarch64），PC 端的 hdc 是 x86_64 Linux 程序，需要单独编译。

OH 官方的做法是编译整个 SDK，hdc 打包在 SDK 的 `toolchains/` 里。尚未找到独立编译 PC 端 hdc 的官方方式。

已完成独立编译脚本：`scripts/build_standalone_linux_host.sh`（同时保存在本工程根目录）。

用法：

```bash
cd ~/oh6/source
./developtools/hdc/scripts/build_standalone_linux_host.sh ~/oh6/source
```

脚本自动从 OH 源码树拷贝依赖（libuv、openssl、lz4、securec、libusb）并静态编译，产物为当前目录下的 `hdc_std`。如不传 OH 源码路径，则从 gitee clone 依赖。

支持增量编译：`KEEP=1` 跳过已编译的依赖库。

注意：此脚本编译 Linux x86_64 版本，Windows 下不可用。WSL 中可编译但因 USB 设备透传限制无法直接使用，需通过 TCP 模式连接设备（`hdc_std tconn IP:端口`）。

## 时间线

- 2026-05-19：完成代码改动，打包补丁，hdcd 可随 OH 整包编译。
- 2026-05-20：完成 PC 端 hdc 独立编译脚本（Linux x86_64），WSL 下编译验证通过。
- 2026-05-21：hdc 源码目录整理为独立 git repo（合并子目录 git，建立原始代码基线）。
