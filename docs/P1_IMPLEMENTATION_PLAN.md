# P1 Liquid Glass 实施计划（验收通过后按此顺序开工）

> 状态：计划稿（P1 未解锁，铁律 2 前不写视觉代码；本文为纯计划）
> 依据：`docs/P1_GLASS_API_VERIFICATION.md`（SDK 签名 + 官方文档行为语义，均已核验）

## 0. 开工前置（验收通过后先确认 2 个设计决策）
1. **模糊/曲率/高光参数口径**：原生 `Glass` 只有预设 + tint + interactive，无这三项数值参数（禁手写模拟）。预案：`ThemeSpec.blurIntensity/highlightIntensity` 保留为语义占位，UI 明示「材质档位」（regular/clear 两档可选 + tint），缺失参数 fallback `.regular`（目标 P1 §4 已要求 fallback）。
2. **GlassSurface legacy 分支去留**：部署目标 26.0 + 放弃旧系统兼容 → `resolveMode` 的 `.legacy` 分支理论不可达；保留（防御）或删（降复杂度）——倾向**保留**（reduceTransparency 的 solid 分支仍需，legacy 成本一行）。

**决策影响矩阵（2026-08-24 无人值守补充，供用户一键拍板；两个推荐默认可整体确认）**：

| 决策 | 选项 A（推荐默认） | 选项 B | 对 P1 实施的影响 |
|---|---|---|---|
| ① 模糊/曲率/高光口径 | 材质档位（regular/clear）+ tint；`ThemeSpec` 三字段保留语义占位，UI 明示「材质档位」 | 等 SDK 开放数值参数（P1 不实现） | A：P1.4 打通「档位 + tint」下发链，manifest 另 2 字段占位化（UI 不承诺功能）；B：P1.4 缩小为 tint 单通道，档位 UI 不做。A 落地面小且 UI 表述诚实，B 在 P1 §4 验收留缺口。**推荐 A** |
| ② legacy 分支去留 | 保留（~1 行防御） | 删除（简化 resolveMode） | 实现量无差（reduceTransparency 的 solid 分支两者都必须保留），差异仅在不可达 `.legacy` 分支存废；未来部署目标回退时 A 零成本。**推荐保留** |

## 1. 现状盘点（P0 资产，P1 直接复用）
- `GlassSurface.swift`：三层降级链已就位；**native 分支已调 `glassEffect(.regular[.tint(t)], in: shape)`**；`glassSurface(_ level:cornerRadius:tint:)` 修饰器已被 6 处消费（SidebarView / ChatInputArea / SettingsView / SettingsSubPages / HarnessTheme）
- `ThemeSpec.glassTintHex/blurIntensity/highlightIntensity` 字段已预留（Theme.swift:25-29）
- 主题插件管线（ThemePluginManager / 设置 Picker / 切换即时生效 / 卸载回落）P0 已闭环 → tint 实时下发只需在现有「主题切换即时生效」链路上补 tint 提取
- 现有 segmented 控件：PluginListView:89 / SettingsView:385（`.pickerStyle(.segmented)`，原生系统控件）

## 2. 实施阶段（每阶段独立提交 + 门禁 + 阶段报告）

### P1.1 全局玻璃容器化（目标 P1 §1）
- 新增 `glassSurfaceContainer` 修饰器：`GlassEffectContainer(spacing:)` 包裹同区域玻璃组件组（侧栏组件组 / composer 面板组 / 设置面板组）
- 逐面接入：侧边栏（SidebarView + 项目分区）、输入框面板（ChatInputArea）、弹窗/sheet/卡片（SettingsView + 各 sheet）、按钮（玻璃按钮风格 `.glass`/`.glassProminent` 仅用于主操作按钮）
- 约束：同区域必须同一 container（官方语义：光学采样一致 + 渲染性能）；间距 spacing 按视觉稿调（融合提前量）
- 降级：reduceTransparency 时 container 内走 solid 表面（复用 resolveMode）

### P1.2 Tab 分段 Morph 容器（目标 P1 §2，核心件）
- 新建 `GlassMorphTabContainer`（Views/）：`@Namespace` + 分段面 `.glassEffect(_:in:)` + `glassEffectID(id:in:)`（分段身份）+ `glassEffectUnion(id:namespace:)`（并集）+ `GlassEffectContainer` 包裹
- 切换：`withAnimation(.smooth)` + `.glassEffectTransition(.materialize)`；**禁 ZStack 滑块位移模拟**（铁律 4）
- 官方约束（已核验）：并集融合要求同 shape + 同 Glass 变体 → 分段面统一同型 shape 与同变体
- 落点决策（验收时与用户确认）：优先承载「侧边栏功能切换」（新对话/对话/多Agent/插件/技能/工具 六分区头）或设置子页切换；现有 `.segmented` 两处不动（系统控件合规）
- 主题参数：该组件接受 `Glass`（tint）注入，主题切换实时更新（走现有主题管线）

### P1.3 全局动效过渡（目标 P1 §3）
- 弹窗/sheet 出入场：`.glassEffectTransition(.materialize)`（配 withAnimation）
- 侧边栏展开/折叠、项目分组展开/收起：`.glassEffectTransition(.matchedGeometry)`（identity 配对）
- 拖拽（会话/项目）：拖起时玻璃面 `glassEffectID` 跟随、落位 morph 回归属区（同 P1.2 机制，复用 namespace）

### P1.4 主题插件玻璃参数打通（目标 P1 §4）
- 主题插件 theme manifest → `ThemeSpec.glassTintHex` → `Color` → 全局 `Glass.regular.tint(...)` 下发（P1.1/P1.2 组件统一从主题上下文取 Glass，不散落调用点）
- 缺失参数 fallback `.regular`（目标已要求）；实时切换无重启（现有管线能力）
- 纯函数可测点：tint hex 解析已有（Color(hex:) 已测）；新增「ThemeSpec → Glass 解析 + fallback」纯函数单测

### P1.5 Tahoe 系统规范对齐（目标 P1 §5）
- 窗口/标题栏/sheet/popover 逐项对照系统规范走查（标题栏 toolbar 玻璃与内容玻璃的层级关系、popover 系统自带玻璃不重复套）
- 走查记录入 QUALITY_REPORT（不新增代码除非发现违规）

## 3. 测试策略
- 可单测（纯函数/逻辑）：Glass 参数解析与 fallback（P1.4）、Morph 容器状态机（分段选择→identity 映射纯函数）、resolveMode 既有矩阵扩展
- 结构性不可测（先例：Notifications UN 包装层 / AppleSignInService 对话框）：玻璃渲染本体 = 实机走查验收（截图对照 + 悬停/morph 手验）；不计入 90% 行覆盖基线，报告单列说明
- 门禁：零警告 + SwiftLint + 全量单测 + leaks 不变；每阶段 PR 门禁绿再进下一阶段

## 4. 验收口径（目标「强制 MVP 验收清单」Liquid Glass 行 ↔ 方法）
| 验收点 | 方法 |
|---|---|
| 全部组件系统原生 API | 代码审查（grep 无手写 blur/opacity 模拟玻璃）+ 无 GlassEffectContainer 外的自绘模糊 |
| Tab Morph 流体玻璃 | 实机：切换分段观察折射高光连续融合（非位移滑块） |
| 主题可控玻璃参数 | 装/切/卸主题插件 → tint 实时变 / 卸载回落 |
| Tahoe 系统控件规范 | P1.5 走查 + 实机截图对照系统 App |

## 5. 风险与对策
| 风险 | 对策 |
|---|---|
| 官方文档未细化 hover 行为细节 | 以 SDK 实测为准（interactive(_:) 开关实验），文档点已列；不脑补行为 |
| 并集融合在异材质变体下不生效（官方明言同变体才合并） | P1.2 约束同变体；若业务需要异变体 → 拆容器（不违反铁律） |
| beta 窗口服务器幻影影响玻璃渲染观察 | 既有看门狗缓解；morph 观察以应用侧日志 + 用户实机为准 |
| 每阶段 UI 变更影响既有交互回归 | 每阶段跑全量测试套件（当前基线 658/658，138 suites，@11725a7 四门禁全绿）+ 侧边栏/项目/拖拽既有场景 |

## 6. 开工 Runbook（P0 验收通过后的首小时流程，2026-08-24 无人值守补充）
1. **用户回复「P0 验收通过」**（剩余走查项：停止生成 / 项目拖拽三向迁移 + 悬停高亮 / 归档回落 / 搜索（全局+限定项目）/ 插件页全链路 / 技能·工具页 / 主题包导入切换回落（`demos/community-theme-demo/spec.json`）/ 加号菜单 / 快捷提示填充 / 模型下拉，详见 `P0_ACCEPTANCE_CHECKLIST.md`）
2. **定点重启 App**（使 `82f3f30`/`4a28a5d` 日期注入在 App 内生效；HARNESS_FRAME 定点重启流程 + 重启前截图确认窗口所在屏——4K 外接屏 2026-08-24 14:02 已断开，窗口已回落内建屏，周一重接 4K 后按当时环境定重启时机）→ **日期问答实机一键验证**（「今天星期几」→ 期望答「星期一」类正确星期）
3. **用户拍板 §0 两决策**（推荐默认：① 材质档位 + tint ② 保留 legacy）；无明确异议即按推荐默认执行
4. **开工 P1.1**（全局玻璃容器化，按 §2 顺序；每阶段独立提交 + 四门禁 + 阶段报告四项）；P1.2（Morph 核心件）待 P1.1 门禁绿后启动
5. **铁律 2 解锁留痕**：开工提交在 QUALITY_REPORT §六 提交链注明「P0 验收通过 + 两决策=<用户拍板结果>，P1 解锁 @<commit>」
