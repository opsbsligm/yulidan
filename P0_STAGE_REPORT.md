# P0 业务 MVP — 阶段报告

> 报告时间: 2026-08-28 12:05
> HEAD: `9ea840b`（镜像 swift-harness-backup.git 双端同步）
> 状态: **代码侧全部闭环，待用户验收**（P1 受铁律 2 门禁：P0 验收通过前不写视觉代码）

## 一、模块完成矩阵

| Goal 模块 | 状态 | 证据索引 |
|---|---|---|
| P0.1 Apple SSO + iCloud 工作区漫游 | ✅ 代码闭环（业务逻辑层测试全覆盖；entitlements 依赖的实机项待 Team，无 entitlements 优雅降级已实现） | `P0_ACCEPTANCE_CHECKLIST.md` §二；AccountServiceTests 19 / WorkspaceRoutingTests 16 + E2E / MetadataSyncTests 8 / WorkspaceRootTests 6 / AppViewModelSyncConflictTests 5 |
| P0.2 侧边栏【项目】模块 | ✅ | §三：CRUD/删除二选一/拖拽悬停高亮/重命名/归档/搜索/持久化（单测 + 实机截图） |
| P0.3 侧边栏导航零假 UI | ✅ | §四：6 导航项全真实对接 + 加载三态（loading/loaded/failed + 重试） |
| P0.4 MCP 插件完整闭环 | ✅ | §五：导入-启用-对话调用-结果回显全链路 / 日志 / 重启 / 卸载 / 权限门禁 / 依赖缺失 / 主题插件（三源聚合 + 自动回落 + 真实 stdio e2e）/ 社区主题包 |
| P0.5 对话主界面对接后端 | ✅ | §六：流式输出 / 停止生成联动中断 / 工具回显 ToolTraceRow / 快捷提示填充输入框 / 模型两级下拉 / 加号插件工具入口 |
| 用户报障 4 批（08-26～08-27） | ✅ 全部闭环 | 二级页返回途径 + 假关闭按钮（实机回归 6/6）/ maxTokens 128–1M 直输+预设 / 提供商全字段（API 地址+钥匙串+思考等级+系统提示词）/ 设置排版重复标签 / 账号与同步诚实化（真 AS + 真 iCloud 探测/降级/冲突裁决） |

## 二、质量基线（最新轮 @9ea840b，四门禁全绿）

- **PR 门禁**：SwiftLint strict 0 违规 / SwiftFormat 0/254 文件 / 构建 0 警告 / **XCTest 257（2 skip = 两个 opt-in 实机集成测试，无环境变量整类跳过）+ Swift Testing 810（175 suites）合计 1067，0 失败**（/tmp/ci_pr_cfgchain_full.log）
- **leaks 门禁**：0 leaks
- **main 门禁**：Release + 全量 + 覆盖率 **后端 Sources 90 文件 10,557 行 96.13%**（<90% 仅 4 文件，其中 AppleSignInService 15.86% 属 entitlements 依赖不可单测区，已标注）
- **xcode 门禁**：BUILD SUCCEEDED / TEST SUCCEEDED
- **App 浸泡**：bundle sha `5320b066`，08-27 18:12 启动 → 08-28 上午用户手动退出，**16h+ 零崩溃**（DiagnosticReports 两次核查零 crash 记录；etime 15:58:08 复测在案）

## 三、核心缺口示例：「上下文大小」四层证据链

08-27 实锤 v1 为假配置（兼容端点不受理 options，runner 仍 `-c 4096`）→ 重构 Ollama 原生 API 后四层证据闭环：

| 层 | 证据 | 复跑方式 |
|---|---|---|
| ① wire 契约 | 桩单测 ×12（路由 / options.num_ctx 在体 / 兼容路径不下发 / tool_name） | `swift test --filter OllamaNativeChatTests,LocalAdapterEngineRoutingTests` |
| ② 服务端 | curl 原生端点 → llama-server 进程参数 `-c 32768`（与 15:34 兼容端点 `-c 4096` 对照） | 证据 /tmp/llama_evidence_c32768.txt |
| ③ 生产路径 | 集成测试（LocalAdapter 起步 → 真实 Ollama → /api/ps `context_length: 32768` 官方字段） | `HARNESS_INTEGRATION=1 swift test --filter OllamaNativeIntegrationTests` |
| ④ 配置持久化 | 集成测试（UI 保存契约 LLMConfig.save → load 往返 → App 同款适配器构造 → 服务端铁证） | `HARNESS_INTEGRATION=1 swift test --filter ConfigPersistenceIntegrationTests` |

**剩余 = 像素级点击自查（用户项 ④，约 10 秒）**：打开 App → 设置 → 请求参数 → 点 32K → 保存 → 发一条消息。

## 四、剩余项（全部用户侧）

1. **Apple Developer Team ID**（10 位付费）→ entitlements + 重签（代码零改动）；到位后 SSO+iCloud 实机验收（清单 §二「有 Team 时」各行）
2. **验收**：走查 `P0_ACCEPTANCE_CHECKLIST.md` → 回复「**P0 验收通过**」→ 解锁 P1
3. **两个 P1 决策**（无意见按推荐执行）：
   - 主题插件可改玻璃参数范围 = **材质档位 + tint**（模糊/曲率归系统管理，不暴露给插件）
   - **保留 GlassSurface legacy** 包装（P1 渐进迁移既有调用点，不破坏性重写）
4. **10 秒自查**（可选，§三）

## 五、P1 解锁条件（铁律 2）

- 必要条件：用户回复「P0 验收通过」
- 不阻塞项：Team ID 到位与否不阻塞 P1 视觉代码（仅阻塞 SSO/iCloud 实机验收）
- P1 范围（按 goal）：全局 glassEffect 玻璃化（GlassEffectContainer 同区域采样一致）/ Tab Morph 流动玻璃（@Namespace + glassEffectID，禁 ZStack 模拟）/ 全局 glassEffectTransition 动效 / 主题插件玻璃参数打通（缺失参数 fallback 系统默认）/ Tahoe 窗口规范
