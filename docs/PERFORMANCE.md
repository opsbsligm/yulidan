# 性能基线与优化记录

## 2026-08-18 — SessionDB 启动路径 N+1 修复

**问题**：`SessionDB.loadAll()` 对每个会话行额外发起一次事件查询（N+1），且启动时全量解码所有会话的全部事件。会话数增长后启动时间与内存随之线性恶化。

**修复**（提交 8064f1a）：
- `loadSessions()`：仅元数据，单条 SQL，启动侧边栏专用
- `load(_ id:)`：单会话含事件，按需加载（切换会话 / 选中首个会话）
- App 层切换选中统一走 `presentSession`：先取事件再切换，`selectedSession` 永不指向空事件记录，防止 persist 按 messages 重建时误清空 DB

**回归测试**：`SessionDBTests.testLoadSessionsFastOnLargeDataset` — 300 会话 × 80 事件，元数据加载 < 1s。

## MemProbe 基线（debug 构建，M5 Mac，macOS 27）

命令：`swift run MemProbe 300`

每次迭代 = 1 次会话保存 + `loadSessions` + `load`（选中会话）+ 每 20 次删除最旧会话（与 App 启动/切换路径同款调用）。

| 日期 | 迭代数 | 耗时 | 单次 |
|------|--------|------|------|
| 2026-08-18 | 300 | 1.06s | ≈3.5ms |

> 旧路径（loadAll 全量）对比未留档；N+1 修复的收益以单元测试回归为准。后续优化项提交时在此追加基线行。
