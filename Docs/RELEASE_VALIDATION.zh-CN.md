# Madedown 1.3.1 发布验收

[English](RELEASE_VALIDATION.md) | **简体中文**

验收日期：2026-08-05

## 自动化检查

- `swift build`：通过
- `swift build -c release`：通过
- `swift run Madedown --self-test`：通过
- `.build/release/Madedown --self-test`：通过
- `swift run MadedownUpdaterHelper --self-test`：通过，覆盖临时签名 App 校验、原位替换与失败回滚
- `./Scripts/check_performance_budget.sh`：通过
- `plutil -lint Packaging/Info.plist dist/Madedown.app/Contents/Info.plist`：通过，App 版本为 `1.3.1`（build `8`）
- `./Scripts/audit_open_source.sh`：通过
- App 与内置 `MadedownUpdaterHelper` 的 ad-hoc 代码签名严格验证：通过
- `Madedown-1.3.1.dmg` 创建与校验：通过
- DMG SHA-256：`9e23b7d5c0940358c6d3bd0c3fb2c01d319edcebdb9ffc09db728db09a474e93`
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

## 真实 macOS UI 验收

使用真实 macOS 界面对 1.3.1 Release App 完成本次热修复路径回归。测试内容仅位于临时标签，结束后已直接丢弃。更完整的 1.3.0 界面验收仍保留在 [v1.3.0 验收记录](https://github.com/zhxnix/Madedown/blob/v1.3.0/Docs/RELEASE_VALIDATION.zh-CN.md)中。

- 在非空有序列表项后按回车，会正常生成下一编号
- 在空列表项再次按回车，会生成后续编号且不再卡死，窗口保持响应
- 在空有序列表标记后按退格，会删除标记并退出列表
- 随后输入文字和按回车均保持普通段落，不会自动生成列表标记

## 性能与内存

本次性能预算结果：

- Release 主可执行文件：`3,827,896 B`（预算 `8 MiB`）
- App 包（含独立更新助手）：`5,224 KiB`（预算 `12 MiB`）
- 启动探针：`10 ms`（预算 `750 ms`）
- 启动 RSS：`16,465,920 B`（预算 `80 MiB`）

更新功能按用户操作启动，不增加常驻后台进程。独立更新助手只在用户确认“安装并重新启动”后短暂运行；GitHub 请求与安装包下载使用系统 `URLSession`，下载完成后释放任务；标题栏 Logo 按实际显示尺寸解码。

以上数值用于发现回归，不代表所有 macOS 版本和屏幕配置下的固定占用。

## 隐私、更新与仓库内容

- 会话文件位于 `~/Library/Application Support/MarkdownNotepad/`，不在项目目录
- 语言选择独立保存在本机偏好中，不改变文档或会话格式
- 更新仅在用户手动触发时访问 GitHub API，文档内容不会进入请求
- 安装包下载地址必须使用批准的 GitHub HTTPS 域名，文件暂存在 `~/Library/Application Support/Madedown/Updates/`
- 下载后先校验应用，用户再次确认后才退出并安装
- 更新助手只替换当前启动路径；成功后删除回滚副本，失败则恢复旧版本
- 需要写入权限时使用 macOS 管理员授权，不会复制出第二份应用，也不会扫描其他目录中的同名 App
- UI 验收没有保存对用户正式文档的修改
- `.build`、`dist`、`.DS_Store`、环境文件和常见密钥格式均被忽略
- GitHub README、更新日志、更新公告、贡献指南、issue 模板和发布验收默认英文，并在适用位置链接完整中文版
