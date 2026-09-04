# 决策总账（D-INDEX）——DoD 首条的单一检查点

> 目的：v8 DoD「D-1~D-6 拍板记录齐（+后续新增项）」的**唯一权威账本**（铁律 3 单一文档源）。
> 每项拍板后由 Agent 记录「决定 + 日期 + 落点 HEAD」；G3 手册 §4 为速览副本，账本以本文件为准。

| ID | 议题 | 选项 | 状态 | 证据/来源锚 |
|----|------|------|------|-------------|
| **D-1** | morph 流体判定终裁（头号） | (a) 目检 G3 A-a 1 分钟 / (b) 认可 A 层结构证据核销 | ☐ | P1 终版表 D-1 证据索引节；BENCHMARK §9（F1/F2 已修，8 项结构判据在册） |
| **D-2** | `interactive` 宣称口径 | 已半结：注释「材质自带」宣称已撤销（BENCHMARK §9）→ 残余=悬停反馈目检（归 G3 A-h） | ◐ | BENCHMARK §6/§9 |
| **D-3** | 设置页 C4 卡片归组 | 与 SETTINGS_IA_PROPOSAL **合并裁决**（IA_PROPOSAL L77：不必单列） | ☐ | docs/SETTINGS_IA_PROPOSAL.md |
| **D-4** | 主题 manifest 假参数（A6） | 显式拒绝不支持字段+提示 / 维持现状 | ☐ | BENCHMARK §3-A6/§6 |
| **D-5** | G4 层2（Cordis sidecar 跑社区插件） | 做 / 不做 | ☐ | CENSUS **四形态总表**（层1/1.5 双形态证据齐；③④结构性不适用论证在册）——材料已足 |
| **D-6** | 24 零事件会话处置 | 删（DB 写需明示+二次确认）/ 留 | ☐ | QUALITY DB 只读复核（26=24+2）；Keychain 旧凭证为可选项 |
| **D-10** | 玻璃折射源修法（材质走向，**最重要**） | (a) 窗口透明底 / (b) backgroundExtensionEffect / (c) 接受扁平 | ✅ 09-04 = (a) | BENCHMARK §13-F4/§15-A15 根因链 |
| **D-11** | 主题 tint 作用域（A13） | 全局装饰 / 仅功能件（官方口径）/ 主题可声明 | ☐ | BENCHMARK §12/§14 |
| **D-12** | F5（撤 sheet 自铺底）+F6（rail 避让带）批次 | 做 / 延后 / 部分（修后各需 1 分钟目检或认可静态证据） | ☐ | BENCHMARK §14/§15；F6(b) overlay 落带官方沉默、终裁归 G3 A-b 目检（㊷） |
| **A14** | 减弱透明度语义（v8 手册补登记） | 保 solid 纯色（现状已验收）/ 增 frosted 中间态 | ☐ | BENCHMARK §12-A14 |
| **轴2** | Codex 界面取证方式 | (a) 你丢截图 / (b) 择时只读截观察窗 / (c) 延后 | ☐ | BENCHMARK §16 工作单；UI_CODEX_ALIGNMENT 重判节 |
| **RSS 可见态组** | 可见态性能基线 | 你开 App 自然用 ≥10 分钟（我后台只读）/ 免 | ☐ | PERFORMANCE 正式基线节 |
| **G1-SCOPE** | 双轴审计范围追认（DoD「范围经确认」条的正式落点） | 认可现行范围（轴1 A1–A19+材质提案 F3/F4 系列；轴2 W1–W8 观察窗清单）/ 或指出增删 | ✅ 09-04 追认 | BENCHMARK §2/§10/§12/§15/§16 全链在册；本轮补登记（发现 DoD 该条此前无正式确认载体） |

## 拍板记录区（拍一条记一条）

- **G1-SCOPE** ✅ 2026-09-04：用户追认现行双轴审计范围（轴1 A1–A19 + 材质提案 F3/F4 系列；轴2 W1–W8 观察窗清单），无增删。拍板载体：chat 答复「1」（对应 Agent 列项「认可池 B + G1-SCOPE」）。DoD「范围经确认」条闭合。
- **池 B（R1 #3/#6a/#6b/#7/#8 真机视觉帧补证，㉔ 二选一）** ✅ 2026-09-04：用户选第二项=「认可 A 层进程内证据即满足该子句」→ 静默核销（证据：#3 源码共享+溢出 10 项实测；#6a ThemeLiveRenderTests；#6b FileThemePackageTests；#7 SidebarDropHighlightRenderTests+noChange 单测；#8 GlassSurfaceTests 降级链+测试缝——均在册含 02:26 xcresult 867 项）。#7「用户手动拖一次」子句按 ㉓ 第二分支（认可在册）闭环，A-f 转 G3 可选观察项。**R1 八项全 ✅**。落点 HEAD：本提交（tag `g0-baseline-20260904`）。

- **D-10** ✅ = (a) 窗口透明底 2026-09-04：用户 chat 答复「1」，双位落位记录（G0 收口报告「下一步」第 1 项 = D-10 × 其选项首位 = (a) 透明窗底案；如属误读一条 revert 即回退）。执行=@`ee1da43` 三处联动（makeWindow 透明装配测试缝 / 实底只贴主区 / 侧栏 GlassSurface(.regular) 底）+ WindowGlassSamplingTests 结构测试。**透窗采样实况终裁 = G3 A-d 目检**（㊹ 风险注记：官方无透窗采样明文，锚定 legacy behindWindow 在册能力）；F5（sheet 自铺底）归 D-12 未拍不动，已知其同窗下仍挡 sheet 区折射。