# Madedown 1.3.3 发布验收

[English](RELEASE_VALIDATION.md) | **简体中文**

验收日期：2026-10-18。版本：**1.3.3（build 10）**。

## 功能检查

- Debug、Release 构建及应用功能自测通过。
- 有序列表连续回车时应用保持响应，光标留在最新列表项，编号正常递增。
- 文首空行、连续段落空行、列表项间距及文末回车经过反复渲染和保存后仍保留。
- 图片、表格、标题、代码块等已有功能检查继续通过。

## 原生 macOS 窗口验证

- 在独立测试文档中输入空行和文末回车，切换到另一标签再返回：可见换行保持一致。
- 切换到源码模式再返回，保存文件并与输入内容比较：文件内容一致。
- 退出并重新打开应用：文档和空行正确恢复。
- 在第一条有序列表后连续按四次回车：正常生成第 2 至第 5 项，并可继续在第 5 项输入，没有卡死。
- 将已安装应用替换为 1.3.3 并重新启动：原有文档内容及当前标签保留。

## 构建环境

使用 Swift 6.4 和本机已安装的 macOS 26.5 SDK，构建 Apple Silicon 版本。本机默认的 macOS 27 命令行 SDK 缺少 SwiftUI 宏插件，因此打包时设置了 `MADEDOWN_SDK_PATH=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`。

打包脚本现在从 Swift 查询实际可执行文件目录，并支持 `MADEDOWN_SDK_PATH`，避免构建引擎改变输出位置后误打包旧缓存程序。

此前更新器的验证记录保留在 [1.3.2 源码快照](https://github.com/zhxnix/Madedown/blob/71f3499/Docs/RELEASE_VALIDATION.zh-CN.md)。
