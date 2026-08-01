# Madedown

[English](README.md) | **简体中文**

[![CI](https://github.com/zhxnix/Madedown/actions/workflows/ci.yml/badge.svg)](https://github.com/zhxnix/Madedown/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/zhxnix/Madedown)](https://github.com/zhxnix/Madedown/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

<p align="center">
  <img src="Assets/Logo/madedown-wordmark-transparent.png" alt="Madedown" width="420">
</p>

一个轻量、免费、开源的原生 macOS Markdown 编辑器。默认提供可直接编辑的实时渲染界面，也可以随时切换到 Markdown 源码。

## 为什么做 Madedown

在 macOS 上，我一直怀念 Windows 11 自带文本编辑器那种简单、直接、打开就写的感觉，却没有找到一款同时满足“顺手、轻量、免费”的 Markdown 编辑器。于是我把心里那款小工具交给 AI 实现，并决定将它完整开源。

> 本项目完全由 AI 编码，我只是个搬运工。

Madedown 不想成为庞大的知识库或项目管理系统。它只专注一件事：让你在 Mac 上快速打开一个 Markdown 文件，然后舒服地写下去。

## 亮点

- 原生 Swift / AppKit / SwiftUI，启动快、占用克制
- 支持英文与简体中文界面；默认英文，可在应用内即时切换
- 默认实时渲染编辑，也可切换 Markdown 源码
- 在实时渲染窗口粘贴 Markdown 源码时，可选择直接转换成所见即所得内容，或逐字保留源码
- 多标签页、新建、打开、保存、另存为和会话恢复
- 标签页与编辑模式、宽度、窗口布局、置顶和语言控件合并在一条紧凑顶部栏中
- 行首输入 `/` 弹出 Markdown 格式菜单
  - 双列展示，支持正文、1–6 级标题、粗体、斜体、删除线、行内代码和链接
  - 支持无序/有序/任务列表、引用、代码块、表格、分割线和图片
  - 菜单打开时按一次退格，只关闭菜单并保留 `/`
  - 支持上下左右方向键选择、回车确认、Esc 关闭
- 文本区域右上角悬浮 H1–H6 标题目录，支持点击跳转和收起
- 插入图片后直接显示
  - 可按 `⇧⌘I`、使用 `/` 菜单、从访达拖入，或直接粘贴截图和已复制的图片文件
  - 未保存文档也能直接插入；首次保存时自动整理附件
  - 图片副本保存在 Markdown 文件旁的 `<文件名>.assets` 目录
  - 文档使用相对路径，移动或分享时只需连同附件目录一起带走
- CommonMark 与常见 GitHub Flavored Markdown
  - 标题、粗体、斜体、删除线、链接、引用、代码和分割线
  - 有序/无序列表、任务列表
  - 原生可编辑表格、连续网格边框及行列增删控件
- 窗口置顶、左右半屏、紧凑窗口、最大化、全宽/阅读宽度切换
- 原生查找替换（`⌘F`）与最近文件快速打开（`⌘P`）
- `⌘B` 加粗、`⇧⌘X` 删除线等常用格式快捷键
- 从 GitHub Releases 检查稳定版，校验后在原路径安全替换、失败回滚并自动重启
- 标签页分别恢复源码/渲染模式的光标、顶部可见文字与视口内偏移
- 按需导出 HTML 或 PDF，不增加常驻后台组件
- 未保存标签关闭提醒，降低误删风险

## 安装与运行

### 直接安装

从 [GitHub Releases](https://github.com/zhxnix/Madedown/releases/latest) 下载最新 DMG，将 `Madedown.app` 拖入“应用程序”。

安装后可在菜单中选择 **Help → Check for Updates…**；切换为中文界面后对应 **帮助 → 检查更新…**。Madedown 会调用 GitHub 的公开 Releases API 比较稳定版本，并可下载对应 DMG 或 ZIP。安装前会校验 Bundle ID、Release 版本、主程序和代码签名。

点击“安装并重新启动”后，独立更新助手会等待 Madedown 退出，在**当前应用原路径**创建临时回滚副本并替换它。新版本成功启动后，旧版本、下载包与暂存目录会自动删除；替换或启动失败则恢复并重新打开旧版本。目标目录需要管理员权限时，macOS 会显示系统授权窗口，而不是另装一份应用。

原位更新只处理当前启动的那个 `Madedown.app`，不会扫描或静默删除其他目录中的同名副本。如果此前手动安装过多个副本，请保留需要的文档后自行移除多余副本；以后从准备长期保留的那份应用内更新即可。

通过 `swift run Madedown` 启动的开发进程可以检查版本，但会拒绝原位替换，避免覆盖 `.build` 或源码目录；请从打包后的 `Madedown.app` 使用在线升级。

### 从源码运行

要求：macOS 13 或更高版本，以及 Swift 6 / Xcode 16 或兼容工具链。

```bash
git clone https://github.com/zhxnix/Madedown.git
cd Madedown
swift run Madedown
```

### 生成 `.app`

```bash
./Scripts/build_app_bundle.sh
open dist/Madedown.app
```

### 生成 DMG

```bash
./Scripts/build_dmg.sh
```

当前本地构建使用 ad-hoc 签名，没有 Apple Developer 公证。首次打开时，macOS 可能要求你在“系统设置 → 隐私与安全性”中确认。

## 常用快捷键

| 操作 | 快捷键 |
| --- | --- |
| 新建 | `⌘N` |
| 打开 | `⌘O` |
| 保存 | `⌘S` |
| 另存为 | `⇧⌘S` |
| 加粗 | `⌘B` |
| 删除线 | `⇧⌘X` |
| 插入图片 | `⇧⌘I` |
| 行首格式菜单 | `/` |
| 查找与替换 | `⌘F` |
| 快速打开最近文件 | `⌘P` |

## 性能设计

Madedown 的目标是保持“小而快”：

- 会话快照采用短延迟合并写入，避免每次按键都进行磁盘写入
- 标签页切换复用现有编辑器实例，不再销毁重建整套文本视图
- 编辑时仅刷新受影响的文本行，而不是反复遍历整篇文档
- 图片由 ImageIO 直接按显示尺寸解码，并使用 32 MiB 上限的内存缓存
- 图片使用相对文件引用，不使用会明显放大文档和内存的 Base64
- Release 构建使用 Swift 编译优化
- CI 对启动时间、峰值内存、可执行文件和 `.app` 包体积设置硬预算，详见[性能预算](Docs/PERFORMANCE_BUDGET.md)

## 隐私与开源安全

仓库不会包含你的编辑内容、最近打开的文件或会话数据。

- 会话仅保存在本机：`~/Library/Application Support/MarkdownNotepad/session.json`
- 构建缓存、应用包、DMG、`.DS_Store`、环境变量文件和常见密钥文件均由 `.gitignore` 排除
- 插入到个人文档的图片保存在该文档旁边，不会自动复制到 Madedown 源码仓库
- 应用没有埋点、账号系统或遥测，不会上传文档内容
- 仅在用户手动点击“检查更新”时访问网络；下载安装包时只接受批准的 GitHub HTTPS 域名
- 更新下载与暂存文件位于 `~/Library/Application Support/Madedown/Updates/`；成功替换后自动清理，超过 7 天的中断目录会在下次更新时清理
- 提交前可运行 `./Scripts/audit_open_source.sh` 做基础敏感信息与大文件检查

注意：如果你主动在项目源码目录中创建 Markdown 文档、附件或密钥，仍应在提交前检查 `git status`。开源安全最终以实际提交内容为准。

## 技术栈

- Swift 6
- SwiftUI + AppKit
- [swift-markdown](https://github.com/swiftlang/swift-markdown) 0.8.0（包含 cmark-gfm，用于 CommonMark / GFM 解析）

## 验证

```bash
swift build
swift run Madedown --self-test
swift run MadedownUpdaterHelper --self-test
./Scripts/check_performance_budget.sh
./Scripts/audit_open_source.sh
```

版本发布前的自动化、真实 UI 和性能验收记录见[发布验收](Docs/RELEASE_VALIDATION.zh-CN.md)。

## 参与贡献

欢迎提交 Issue 和 Pull Request。开始前请阅读[贡献指南中文版](CONTRIBUTING.zh-CN.md)；安全问题请按 [SECURITY.md](SECURITY.md) 中的方式报告。

## 许可证

Madedown 使用 [MIT License](LICENSE) 开源。
