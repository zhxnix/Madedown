# Madedown 性能预算

Madedown 的功能准入以“打开即用”为前提。CI 会运行 `./Scripts/check_performance_budget.sh`，超过任一预算即失败。

| 指标 | 默认预算 | 测量方式 |
| --- | ---: | --- |
| Release 可执行文件 | 8 MiB | `.build/release/Madedown` 文件大小 |
| `.app` 包体积 | 12 MiB | `dist/Madedown.app` 磁盘占用 |
| 冷启动探针 | 750 ms | 新进程加载应用与本地会话存储所需时间 |
| 启动峰值 RSS | 80 MiB | macOS `/usr/bin/time -l` 最大常驻内存 |

预算可通过 `MADEDOWN_BINARY_BUDGET_BYTES`、`MADEDOWN_APP_BUDGET_KIB`、`MADEDOWN_STARTUP_BUDGET_MS` 和 `MADEDOWN_RSS_BUDGET_BYTES` 临时覆盖，用于诊断而不是绕过回归。

启动探针不会创建窗口、联网或读取正式文档；CI 使用独立临时会话路径。它用于发现趋势变化，真实用户体验仍需配合 Release App 界面验收。
