# Madedown（玛德蛋）

[![CI](https://github.com/zhxnix/Madedown/actions/workflows/ci.yml/badge.svg)](https://github.com/zhxnix/Madedown/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/zhxnix/Madedown)](https://github.com/zhxnix/Madedown/releases/latest)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

<p align="center">
  <img src="Assets/Logo/madedown-wordmark-transparent.png" alt="Madedown" width="420">
</p>

一个轻量、免费、开源的原生 macOS Markdown 编辑器。默认提供可直接编辑的实时渲染界面，也可以一键切换到 Markdown 源码。

> 名字读作 **“玛德蛋”**（Madedown），不是“美德蛋”。这是项目的正式中文读音。

## 为什么做 Madedown

在 macOS 上，我一直怀念 Windows 11 自带文本编辑器那种简单、直接、打开就写的感觉，却没有找到一款同时满足“顺手、轻量、免费”的 Markdown 编辑器。于是我把心里那款小工具交给 AI 实现，并决定将它完整开源。

> 本项目完全由 AI 编码，我只是个一个搬运工。

Madedown 不想成为庞大的知识库或项目管理系统。它只专注一件事：让你在 Mac 上快速打开一个 Markdown 文件，然后舒服地写下去。

## 亮点

- 原生 Swift / AppKit / SwiftUI，启动快、占用克制
- 默认实时渲染编辑，也可切换 Markdown 源码
- 多标签页、新建、打开、保存、另存为和会话恢复
- 行首输入 `/` 弹出 Markdown 格式菜单
  - 双列展示，支持正文、1–6 级标题、粗体、斜体、删除线、行内代码和链接
  - 支持无序/有序/任务列表、引用、代码块、表格、分割线和图片
  - 菜单打开时按一次退格，只关闭菜单并保留 `/`，方便输入普通斜杠
  - 支持上下左右方向键选择、回车确认、Esc 关闭
- 文本区域左上角悬浮标题目录
  - 自动识别 H1–H6，点击标题即可快速跳转
  - 一键收起为小按钮，需要时再展开
- 插入图片后直接显示
  - 点击工具栏“图片”、按 `⇧⌘I`，或在 `/` 菜单选择“图片”
  - 未保存文档也能直接插入；首次保存时自动整理附件，无需先走保存流程
  - 图片副本保存在 Markdown 文件旁的 `<文件名>.assets` 目录
  - 文档使用相对路径，移动或分享时只需连同附件目录一起带走
- CommonMark 与常见 GitHub Flavored Markdown
  - 标题、粗体、斜体、删除线、链接、引用、代码和分割线
  - 有序/无序列表、任务列表
  - 原生富文本表格及行列增删控件
- 窗口置顶、左右半屏、紧凑窗口、最大化、全宽/阅读宽度切换
- 未保存标签关闭提醒，降低误删风险

## 安装与运行

### 直接安装

从 [GitHub Releases](https://github.com/zhxnix/Madedown/releases/latest) 下载最新 DMG，将 `Madedown.app` 拖入“应用程序”。

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
| 插入图片 | `⇧⌘I` |
| 行首格式菜单 | `/` |

## 性能设计

Madedown 的目标是保持“小而快”：

- 会话快照采用短延迟合并写入，避免每次按键都进行磁盘写入
- 标签页切换复用现有编辑器实例，不再销毁重建整套文本视图
- 编辑时仅刷新受影响的文本行，而不是反复遍历整篇文档
- 图片由 ImageIO 直接按显示尺寸解码，并使用 32 MiB 上限的内存缓存，避免先完整解码大图
- 图片使用相对文件引用，不使用会明显放大文档和内存的 Base64
- Release 构建使用 Swift 编译优化

## 隐私与开源安全

仓库不会包含你的编辑内容、最近打开的文件或会话数据。

- 会话仅保存在本机：`~/Library/Application Support/MarkdownNotepad/session.json`
- 构建缓存、应用包、DMG、`.DS_Store`、环境变量文件和常见密钥文件均由 `.gitignore` 排除
- 插入到个人文档的图片保存在该文档旁边，不会自动复制到 Madedown 源码仓库
- 应用没有埋点、账号系统或遥测，不会上传文档内容
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
./Scripts/audit_open_source.sh
```

版本发布前的自动化、真实 UI 和性能验收记录见 [Docs/RELEASE_VALIDATION.md](Docs/RELEASE_VALIDATION.md)。

## 参与贡献

欢迎提交 Issue 和 Pull Request。开始前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)；安全问题请按 [SECURITY.md](SECURITY.md) 中的方式报告。

## 许可证

Madedown 使用 [MIT License](LICENSE) 开源。
