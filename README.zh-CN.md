# CordKey

[English](README.md) · [简体中文](README.zh-CN.md) · [产品主页](https://arronkler.github.io/cordkey/)

**将 USB / HID 有线耳机按键映射为 Mac 键盘快捷键 —— 专为语音输入 Push-to-Talk 与语音通话打磨。**

CordKey 是一个轻量、零外部依赖的原生 macOS 状态栏应用（`CordKey.app`）与命令行工具（`cordkey`），可将 USB-C EarPods 或任意通用 USB/HID 有线耳麦（Jabra、罗技、Poly、HyperX、Sony、USB-C 转接头等）上的按键映射为 Mac 键盘单键、独立修饰键或组合键。

## 核心特性

- **通用 USB 耳麦兼容（Consumer `0x0C` + Telephony `0x0B` 双页支持）**
  - 除标准媒体播放/音量键外，原生支持办公/会议 USB 耳麦常见的 **麦克风静音键（`0x0B:0x2F`）**、**通话/挂断键（`0x0B:0x20`）**、**通话保持（`0x0B:0x21`）**、**音频静音（`0x0C:0xE2`）**、**语音助手键（`0x0C:0xCF`）** 及任意自定义 HID 按键。
  - **「+ 识别耳机键」一键学习**：插上任何品牌的 USB 耳麦后，在面板点「识别耳机键」再按一下耳机上的目标按键，自动识别设备（`VendorID:ProductID`）与按键码并添加到映射列表，无需查十六进制 ID。
- **原生 SwiftUI 状态栏面板（`CordKey.app`）**
  - **左键打开面板 · 右键快捷菜单**：支持一键暂停/恢复映射、立即松开卡住按键、打开辅助功能设置、退出应用。
  - **交互式键盘快捷键录制器**：点按键行右侧键盘图标，直接按 Mac 键盘上的任意单键、单独修饰键（`右 Option`、`Fn`）或组合键（`Cmd+Shift+Space`）即可录入。
  - **状态栏实时计时 + 一键松开**：保持按下期间状态栏线控胶囊图标亮起橙色并显示持续秒数（如 `0:08`），面板顶部显示「立即松开」防卡键按钮。
  - **中英文实时切换**：在 **音频与设备** 卡片内置 `Auto / English / 简体中文` 语言切换器，点击即刻生效。
- **EarPods 麦克风物理短路专项优化**
  - **纯净音频「单击切换」**：第一下松手后延迟 60ms（等物理触点脱离短路）再按下目标键，消除开头杂音与静音；第二下按下瞬间立即结束。
  - **智能提示 + 内置 CoreAudio 麦克风切换器**：检测到 EarPods 麦克风在按住模式下冲突时自动提示，并可在面板直接切换至「单击切换」或机身内置麦克风。
  - **轻柔系统提示音**：开启/松开时播放 `Tink` / `Pop` 提示音（可开关）。
- **进阶效率与多设备能力**
  - **输入麦克风锁定**：在麦克风选择器旁一键锁定首选默认麦，防止插拔耳机时被 macOS 自动抢占默认输入设备。
  - **多耳机配置记忆与自动切换**：按设备 `VID:PID` 自动保存并切换对应耳机的映射与触发模式。
  - **悬浮状态胶囊与超时自动松开**：支持在屏幕顶部/底部显示不抢焦点的毛玻璃悬浮胶囊（点击即松开），并为「单击切换」提供 `1分 / 2分 / 5分` 安全自动松开。
  - **长按多动作（长按 + 短按 + 双击）**：在「长按触发」模式下可分别为短按与双击指定独立快捷键（CLI 支持 `--tap` / `--double-tap`）。
  - **分应用规则**：可在影音应用（Music、IINA、QuickTime）中自动暂停映射，或为飞书、Zoom、Discord 等会议软件单独覆写播放键。
  - **蓝牙耳机兼容模式**：无需抢占 USB HID，通过「单击切换」兼容 AirPods、Sony 等蓝牙耳机播放键。

## 快速开始

### 方式一：Homebrew 一行安装（推荐，零 Gatekeeper 拦截）

自动安装 Universal 通用版 **`CordKey.app`** 到 `/Applications`，并同步将 `cordkey` 命令行链接进 `PATH`：

```bash
brew install --cask --no-quarantine arronKler/tap/cordkey
open /Applications/CordKey.app
```

> 后续升级：`brew upgrade --cask arronKler/tap/cordkey`；彻底卸载：`brew uninstall --cask --zap cordkey`。

### 方式二：下载官方 Universal DMG 安装包

无需 Homebrew 或 Xcode，支持 **Apple Silicon (M1–M4) 与 Intel**（macOS 13.0+）：

1. 前往 [**GitHub Releases**](https://github.com/arronKler/cordkey/releases/latest) 下载最新的 **`CordKey-*-macos-universal.dmg`**。
2. 双击打开 `.dmg`，**先将 `CordKey.app` 拖入「应用程序（Applications）」**（请勿直接在 DMG 内双击打开）。
3. 首次打开前（或遇到“无法验证开发者”提示时），在终端执行一次放行命令，或在 **系统设置 → 隐私与安全性 → 安全性 → 仍要打开** 授权：
   ```bash
   xattr -cr /Applications/CordKey.app && open /Applications/CordKey.app
   ```
4. 打开后点击右上角状态栏线控胶囊图标，点 **「前往授权」** 并在 **系统设置 → 隐私与安全性 → 辅助功能** 中勾选 **CordKey**。

<details>
<summary><strong>方式三：开发者源码构建（可选）</strong></summary>

```bash
git clone https://github.com/arronKler/cordkey.git
cd cordkey
make app-install   # 编译打包并安装到 /Applications/CordKey.app
open /Applications/CordKey.app
```

</details>

## 命令行模式（可选）

```bash
make build
./bin/cordkey --help
./bin/cordkey devices                                      # 查看所有 Consumer/Telephony USB 耳麦
./bin/cordkey probe                                        # 实时探测任意 USB 耳麦按键的页码与键码
./bin/cordkey --play right_option --toggle --sound         # EarPods 干净音频单击切换 + 提示音
./bin/cordkey --vendor 0x0b0e --product 0x0301 --mic-mute right_option   # Jabra 等办公耳麦静音键映射
./bin/cordkey --button 0x0b:0x20 f13                       # 映射任意 PAGE:USAGE 按钮
./bin/cordkey watch                                        # 实时验证系统收到的键盘与媒体键事件
```

### 常用 Makefile 目标

- `make build` — 编译 CLI 二进制 `bin/cordkey`
- `make app` — 打包 `build/CordKey.app`（`io.github.cordkey.app`）
- `make app-install` — 安装到 `/Applications/CordKey.app`
- `make install` — 安装 CLI 到 `~/.local/bin/cordkey`
- `make service-install` / `make service-uninstall` / `make service-status` — 管理 `io.github.cordkey.cli` LaunchAgent

## 系统要求

- macOS 13.0 (Ventura) 及以上版本
- Xcode Command Line Tools（`swiftc`），零第三方依赖
