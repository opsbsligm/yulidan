# UI 对标 Codex 差距盘点（F7）

> 生成：2026-08-20 ｜ HEAD 基线：`171c881`（660 用例）
> 范围：用户 5 项 UI 要求中「布局对标 Codex」「按钮/面板布局对齐 Codex 交互」两项的逐项差距盘点。
> 方法：逐文件读当前实现（ContentView / SidebarView / ChatAreaView / ChatInputArea / WelcomeAreaView / SettingsView），与 Codex 桌面端布局/交互范式对照。

## 一、已对齐（现有实现，不再改动）

| # | 项 | 现状 |
|---|----|------|
| A1 | 左侧单栏侧边栏 | 品牌行（Harness ⌄ 菜单 + 搜索图标）→ 新对话（行尾 ⊕）→ 导航行（对话/多Agent/插件/技能/工具）→ 会话列表常显按日分组（今天/昨天/更早）→ 底栏头像+姓名+设置齿轮 |
| A2 | 顶栏 | 左=会话标题 / 右=模型 pill（提供商→模型级联 + 模型设置入口）+ ellipsis 溢出菜单（附件/派生子Agent/复制/导出/重命名/清空/删除） |
| A3 | Composer | 居中限宽 720、圆角 16 玻璃表面、聚焦 accent 描边、底行 = + 附件 / 模型名 / 实心圆↑发送·红■停止、提示行「Enter 发送 · Shift+Enter 换行」 |
| A4 | 消息区 | 用户右对齐气泡 / 助手小头像+纯文本 / 工具可折叠轨迹行 / 代码块+复制 / 上翻显示回到底部按钮 / 贴底自动跟随（上翻不打断） |
| A5 | 欢迎页 | hero 居中（图标+标题）+ 建议 chips + 底部 composer（Codex 式新任务页结构） |
| A6 | 设置 | 二级菜单 + 子页面导航（F1 闭环） |
| A7 | 表面系统 | WWDC26 Liquid Glass 三级降级（F6 闭环） |

## 二、差距清单（按优先级）

| # | 优先级 | 差距 | Codex 行为 | 处置 |
|---|--------|------|-----------|------|
| B1 | **P1** | 生成中切换/新建/删除会话污染消息流 | Codex 生成中任务状态锁定，切换不打断当前任务写入 | ✅ 已闭环 `171c881`：三入口拦截 + guardGenerationSession 防御 + 2 项场景测试 |
| B2 | P1 | 会话列表无在途生成状态指示 | Codex 活跃任务行显示运行中指示 | ✅ 已闭环 `171c881`：generatingSessionId 发布 + 列表行 spinner |
| B3 | P2 | 会话行无相对时间 | Codex 任务行显示「2h」「昨天」等相对时间 | ✅ 已闭环 `171c881`：RelativeTime.format 纯函数（3 组单测）+ 行尾时间 |
| B4 | P2 | 无全局键盘快捷键 | Codex：⌘N 新任务 / ⌘, 设置 / ⌘1-6 面板切换 | ✅ 已闭环 `171c881`：⌘N / ⌘, / ⌘1–⌘6（视觉验收待实机） |
| B5 | P2 | 侧边栏不可折叠 | Codex 支持折叠侧边栏释放主区宽度 | **登记待办**（需折叠态持久化 + 布局重构，下轮） |
| B6 | P2 | 无置顶会话 | Codex 支持 pinned 任务段 | **登记待办**（需 SessionMetadata 扩展 + DB 迁移，下轮） |
| B7 | P2 | SessionSidebarView.swift 死代码（仅自身 #Preview 引用，ContentView 已用 SidebarView） | — | ✅ 已闭环 `171c881`：删除（UI 层分母 -93 插桩行） |
| B8 | P3 | 用户消息为气泡样式 | Codex 用户消息为无气泡纯文本 | **登记待办**（视觉微调，随视觉验收一并对齐） |

## 三、本轮实施（B1/B2/B3/B4/B7）

- B1：`generatingSessionId` + 三入口拦截（toast 提示）+ performGeneration 防御校验
- B2：`SessionListItem(isGenerating:)` 行内 spinner
- B3：`RelativeTime.format(_:now:)` 纯函数（单测覆盖：刚刚/N分钟前/N小时前/昨天/N天前/日期）
- B4：ContentView 快捷键（⌘N / ⌘, / ⌘1–⌘6）
- B7：删除死代码文件
