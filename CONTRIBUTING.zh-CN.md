# 为 Madedown 贡献代码

[English](CONTRIBUTING.md) | **简体中文**

感谢你愿意改进 Madedown。

## 开始之前

1. 先搜索已有 Issue，避免重复工作。
2. 功能改动建议先开 Issue 说明目标和交互。
3. 每个 Pull Request 尽量只解决一个清晰问题。

### 语言规则

- 新 Issue 和 Pull Request 使用英文标题、英文优先正文。
- 欢迎在 `<details><summary>简体中文</summary>…</details>` 折叠区域中附上完整简体中文翻译。
- 面向用户的仓库文档默认英文，并链接到对应的 `.zh-CN.md` 中文版。
- 这项规则兼顾公共项目的可访问性和完整的中文文档体验。

## 本地开发

```bash
swift build
swift run Madedown --self-test
swift run Madedown
```

提交前请同时运行：

```bash
./Scripts/audit_open_source.sh
```

涉及 UI 的改动请参考[发布验收](Docs/RELEASE_VALIDATION.zh-CN.md)中的真实界面检查项。

## 代码要求

- 支持 macOS 13 及以上版本。
- 优先使用系统框架，谨慎增加第三方依赖。
- 不在主线程执行网络请求或持续的大文件 I/O。
- 新功能应补充 `--self-test` 覆盖，或在 Pull Request 中写明手工验证方法。
- 不提交个人文档、会话文件、密钥、构建缓存、应用包或 DMG。
- 修改本地化界面时，保持英文和简体中文用户可见文本含义一致。
- 修改 GitHub 面向用户的文档时，同步维护英文和 `.zh-CN.md` 文件。

## Pull Request

请说明：

- 改了什么、为什么改
- 用户可见影响
- 验证方式和结果
- 如有 UI 变化，请附截图或录屏

提交即表示你同意按项目的 MIT License 授权你的贡献。
