# 为 Madedown 贡献代码

感谢你愿意改进 Madedown（读作“玛德蛋”）。

## 开始之前

1. 先搜索已有 Issue，避免重复工作。
2. 功能改动建议先开 Issue 说明目标和交互。
3. 每个 Pull Request 尽量只解决一个清晰问题。

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

涉及 UI 的改动请参考 [Docs/RELEASE_VALIDATION.md](Docs/RELEASE_VALIDATION.md) 中的真实界面检查项进行回归。

## 代码要求

- 支持 macOS 13 及以上版本。
- 优先使用系统框架，谨慎增加第三方依赖。
- 不在主线程执行网络请求或持续的大文件 I/O。
- 新功能应补充 `--self-test` 覆盖，或在 Pull Request 中写明手工验证方法。
- 不提交个人文档、会话文件、密钥、构建缓存、应用包或 DMG。

## Pull Request

请说明：

- 改了什么、为什么改
- 用户可见影响
- 验证方式和结果
- 如有 UI 变化，请附截图或录屏

提交即表示你同意按项目的 MIT License 授权你的贡献。
