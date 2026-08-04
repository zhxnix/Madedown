# Madedown 1.3.2 发布验收

[English](RELEASE_VALIDATION.md) | **简体中文**

验收日期：2026-08-05

## 自动化检查

- `swift build`：通过
- `swift build -c release`：通过
- `swift run Madedown --self-test`：通过
- `.build/release/Madedown --self-test`：通过
- `.build/release/Madedown --dmg-self-test dist/Madedown-1.3.2.dmg`：通过；暂存 App 校验成功，提取后的挂载目录为空
- `swift run MadedownUpdaterHelper --self-test`：通过，覆盖临时签名 App 校验、原位替换与失败回滚
- `./Scripts/check_performance_budget.sh`：通过
- `plutil -lint Packaging/Info.plist dist/Madedown.app/Contents/Info.plist`：通过，App 版本为 `1.3.2`（build `9`）
- `./Scripts/audit_open_source.sh`：通过
- App 与内置 `MadedownUpdaterHelper` 的 ad-hoc 代码签名严格验证：通过
- `Madedown-1.3.2.dmg` 创建与校验：通过
- DMG SHA-256：`c2281735de0125f347535fe3fbcdf9c91edda1333836fe10b9cd42af323978e8`
- `git diff --check`：通过

自测继续覆盖标题、软换行、列表、引用、代码、任务列表、图片、HTML/PDF 导出、会话、标签视口、标题目录和 GFM 表格，并保留以下 1.3.0 回归：

- Markdown 粘贴识别：标题、列表、表格、行内格式与普通文本误报
- Markdown 粘贴转换：标题和列表插入后仍可正确序列化
- `⌘B` 加粗和 `⇧⌘X` 删除线的添加/取消
- 无语言偏好时默认英文、独立偏好域中的语言持久化，以及代表性的中英文界面和斜杠菜单翻译
- 表格段落终止符保留同一 `NSTextTableBlock` 和 table ID
- 两列两行表格生成 3 条连续纵向边界和 3 条连续横向边界，且边界严格递增
- 连续覆盖层直接使用原生表格边框区域，不再重复扣除 16 pt 外部间距
- 标签视口持久化顶部可见字符锚点和像素偏移，旧会话缺少字段时仍能解码
- 语义版本数字比较与稳定版/预发布版优先级
- Release 资产优先选择 DMG，并拒绝非 HTTPS、非 GitHub 下载地址
- 更新助手校验 Bundle ID、版本、主程序与代码签名；损坏 App 被拒绝
- 更新助手完成“旧版本备份 → 新版本原位替换 → 目标再校验 → 删除备份”事务，失败可回滚

1.3.1 热修复新增覆盖：

- 扫描“只有编号标记的有序列表项 + 换行”能够结束，且不会改变序列化后的 Markdown
- 空有序列表标记退格后会清除继承的列表输入状态
- 退出有序列表后继续输入文字或按回车，仍保持普通段落

1.3.2 热修复新增覆盖：

- 更新 Sheet 仍挂在窗口上时，安装流程保持等待状态
- 只有在更新 Sheet 完全脱离后才启动更新助手
- 更新助手失败时展示捕获到的错误并清理准备目录，不再停留在无限安装状态
- 卸载 DMG 前释放目录枚举资源，并提供常规重试与强制卸载兜底

## 真实 macOS UI 验收

首先在已安装的 1.3.0 中复现失败：点击“安装并重新启动”后，主进程仍然存活，更新助手等待 30 秒后消失；AppKit 日志明确记录 `App termination blocked by modal sheet`，随后终止流程被放弃。

随后在临时应用目录中使用修复后的 Release 构建完成真实在线升级。临时 App 使用修正后的控制器但报告版本 1.3.0，再在线下载并安装正式的 1.3.1 Release 资产。

- 请求退出前，更新 Sheet 已先关闭
- 原进程正常退出，AppKit 不再记录模态 Sheet 拒绝终止
- 暂存 App 精确替换临时目标路径，目标版本变为 1.3.1
- 替换后的应用使用新进程 ID 自动重启
- 启动验证成功后，回滚副本被删除
- 已有会话内容原样恢复；测试过程不编辑文档内容

同时重新执行了 1.3.1 的有序列表界面回归。更完整的 1.3.0 界面验收仍保留在 [v1.3.0 验收记录](https://github.com/zhxnix/Madedown/blob/v1.3.0/Docs/RELEASE_VALIDATION.zh-CN.md)中。

- 在非空有序列表项后按回车，会正常生成下一编号
- 在空列表项再次按回车，会生成后续编号且不再卡死，窗口保持响应
- 在空有序列表标记后按退格，会删除标记并退出列表
- 随后输入文字和按回车均保持普通段落，不会自动生成列表标记

## 性能与内存

本次性能预算结果：

- Release 主可执行文件：`3,834,696 B`（预算 `8 MiB`）
- App 包（含独立更新助手）：`5,232 KiB`（预算 `12 MiB`）
- 启动探针：`30 ms`（预算 `750 ms`）
- 启动 RSS：`16,416,768 B`（预算 `80 MiB`）

更新功能按用户操作启动，不增加常驻后台进程。独立更新助手只在用户确认“安装并重新启动”后短暂运行；GitHub 请求与安装包下载使用系统 `URLSession`，下载完成后释放任务；标题栏 Logo 按实际显示尺寸解码。

以上数值用于发现回归，不代表所有 macOS 版本和屏幕配置下的固定占用。

## 隐私、更新与仓库内容

- 会话文件位于 `~/Library/Application Support/MarkdownNotepad/`，不在项目目录
- 语言选择独立保存在本机偏好中，不改变文档或会话格式
- 更新仅在用户手动触发时访问 GitHub API，文档内容不会进入请求
- 安装包下载地址必须使用批准的 GitHub HTTPS 域名，文件暂存在 `~/Library/Application Support/Madedown/Updates/`
- 下载后先校验应用，用户再次确认后才退出并安装
- 只有在模态更新 Sheet 完全脱离后，才启动更新助手并请求 AppKit 退出
- 如果原应用仍存活，更新助手失败会被捕获并展示
- 更新助手只替换当前启动路径；成功后删除回滚副本，失败则恢复旧版本
- 需要写入权限时使用 macOS 管理员授权，不会复制出第二份应用，也不会扫描其他目录中的同名 App
- UI 验收没有保存对用户正式文档的修改
- `.build`、`dist`、`.DS_Store`、环境文件和常见密钥格式均被忽略
- GitHub README、更新日志、更新公告、贡献指南、issue 模板和发布验收默认英文，并在适用位置链接完整中文版
