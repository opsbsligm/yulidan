# 决策总账（D-INDEX）——DoD 首条的单一检查点

> 目的：v8 DoD「D-1~D-6 拍板记录齐（+后续新增项）」的**唯一权威账本**（铁律 3 单一文档源）。
> 每项拍板后由 Agent 记录「决定 + 日期 + 落点 HEAD」；G3 手册 §4 为速览副本，账本以本文件为准。

| ID | 议题 | 选项 | 状态 | 证据/来源锚 |
|----|------|------|------|-------------|
| **D-1** | morph 流体判定终裁（头号）**·09-05 决策重述** | (a) 目检 G3 A-a 1 分钟 ／ (b) 认可 A 层结构证据核销 ／ **(c) 新·推荐**：先做 §3-A1 根因改造（未选中 tile 亦常驻玻璃面，选中改 tint/前景区分），静默判据＝单测断言「native 态参与 morph 玻璃面数 == segments.count」，改造后你再 1 分钟目检「液体颈」；仍无融合则按 §1.14 终裁重估 `.matchedGeometry` 去留，morph 不可得即回落 F2/tint 强调并改判 P1 口径 | ☐ | **证据边界（09-05 实测钉住，勿再按旧口径读）**：① 本仓 A 层**无任何可捕获玻璃像素的通道**（§0 通道表首行即 `ImageRenderer` 离屏位图=**完全不渲染玻璃**，09-03 实测；另 `cacheDisplay` 0/96000、`displayIgnoringOpacity` 0/613、`CALayer.render` 0/611、`dataWithPDF` 不捕获内容、边界外窗+screencapture 挂起）⇒ v8 原文「用 ImageRenderer 像素帧判定流体融合」不可执行，**该判据 09-02 已由 QUALITY 纠偏过一次**（本轮 (c) 案是补执行路径，非首次发现）；② 8 项结构判据只能证明**API 用法合官方语义**，推不出**视觉上流体融合**，故 (b) 的有效边界=核销「实现合规」，不含「观感达标」；③ 源码实测容器内运行时**仅 1 个玻璃面**（`GlassMorphTabBar.swift` L225–239：`TileFaceMode.resolve` 非选中走 `.plain`，`.glassEffect` 全仓仅 L231 一处）⇒ §3-A1=❌根因 GAP 未修，此时目检 (a) 只能复现「淡变」已知结论，**不产生决策增益**。故选 (a)/(b) 请连同①②③的边界一并确认；选 (c) 则需同时裁 D-11（tint 作用域＝A1 选中区分的实现手段来源）与 A12 面数/性能护栏复测 |
| **D-2** | `interactive` 宣称口径 | 已半结：注释「材质自带」宣称已撤销（BENCHMARK §9）→ 残余=悬停反馈目检（归 G3 A-h） | ◐ | BENCHMARK §6/§9 |
| **D-3** | 设置页 C4 卡片归组 | 与 SETTINGS_IA_PROPOSAL **合并裁决**（IA_PROPOSAL L77：不必单列） | ☐ | docs/SETTINGS_IA_PROPOSAL.md |
| **D-4** | 主题 manifest 假参数（A6） | 显式拒绝不支持字段+提示 / 维持现状 | ☐ | BENCHMARK §3-A6/§6 |
| **D-7** | 设置容器形态（**09-05 补登**：此前只存在于 IA_PROPOSAL §七，账本漏登） | (a) 维持 sheet（现状，Esc/xmark 闭环已核销）/ (b) 独立 `Settings` 窗口 | ☐ | docs/SETTINGS_IA_PROPOSAL.md §七（提案内建议=a）；与 D-3 合并裁决 |
| **D-8** | 设置概览页去留（**09-05 补登**，同上） | 概览页保留 + 每行「编辑…」跳转（提案默认）/ 删概览页只留 6 编辑 pane | ☐ | docs/SETTINGS_IA_PROPOSAL.md §七 |
| **D-9** | 记忆/工作区可编辑性（**09-05 补登**，同上） | 升为可编辑 / 明确标为只读并在文案说明（IA-4 二选一） | ☐ | docs/SETTINGS_IA_PROPOSAL.md §七 |
| **D-5** | G4 层2（Cordis sidecar 跑社区插件） | 做 / 不做 | ✅ 09-04 = 做（G4c 启动） | CENSUS **四形态总表**；实施设计 docs/G4C_SIDECAR_DESIGN.md |
| **D-6** | 24 零事件会话处置 | 删（DB 写需明示+二次确认）/ 留 | ✅ 09-04 拍板 = 删；✅ **09-05 已执行**（26→2，三重校验通过） | QUALITY DB 只读复核（26=24+2）；Keychain 旧凭证为可选项 |
| **D-10** | 玻璃折射源修法（材质走向，**最重要**） | (a) 窗口透明底 / (b) backgroundExtensionEffect / (c) 接受扁平 | ✅ 09-04 = (a) | BENCHMARK §13-F4/§15-A15 根因链 |
| **D-11** | 主题 tint 作用域（A13） | 全局装饰 / 仅功能件（官方口径）/ 主题可声明 | ☐ | BENCHMARK §12/§14 |
| **D-12** | F5（撤 sheet 自铺底）+F6（rail 避让带）批次 | 做 / 延后 / 部分（修后各需 1 分钟目检或认可静态证据） | ☐ | BENCHMARK §14/§15；F6(b) overlay 落带官方沉默、终裁归 G3 A-b 目检（㊷） |
| **D-13** | **~~leaks 门禁在本机不可用~~ → 09-05 18:09 实测否证，自动闭环（不需你出场）** | 原三案全部作废（(a) 重启登录会话／(b) RSS 护栏降级口径／(c) 挂起待恢复）——第四门禁已 @当前HEAD 实跑 `rc=0`：`leaks --atExit -- .build/debug/MemProbe 500` = `0 leaks for 0 total leaked bytes`，marker `2026-09-05 18:09:07 mode=leaks rc=0`，整段 28s | ✅ 09-05 闭环（**前提不成立而自动关闭，非用户拍板**） | **否证对照（本轮实测，全 A 层零前台）**：`sample <sleep 金丝雀> 1 -file` rc=0/117 行／`sample 58301 1 -file` rc=0/1219 行（GUI 进程 attach 正常）／`leaks <金丝雀 pid>` rc=0／`leaks --atExit -- MemProbe 5` rc=0/1s ⇒ 三条依赖 task 端口的通道均可用。**诚实边界**：当时挂起有在册证据（MemProbe 停 T 态、ps 状态 `TN`），但原始日志未留存 ⇒ 真实失败模式不可反推，故改判「间歇性故障、病因未定、已不可复现」；「登录会话/调试通道退化」属未经对照支持的归因，**撤回**；门禁脚本内写死该归因的失败提示同步改为中性处置顺序（本轮提交） |
| **D-14** | launchd 重门禁静默化（新发现） | (a) `com.harness.ci11.pr` 的 `ProgramArguments` 改调 `tools/ci-quiet.sh pr`（登录不再立即抢占，等缺席窗口才跑，你回场即整组回收）／(b) 维持现状（登录即跑全量 pr）／(c) 卸载该 LaunchAgent，改由 Agent 在缺席窗口手跑 | ☐ 待批 | **实测现状**：`launchctl list` 显示该 job **已加载**，plist 为 `RunAtLoad=true`+`KeepAlive=false` ⇒ **每次登录/加载即在你必然到场时跑全量 pr 门禁**（Lint+Format+编译+788 测试）；全仓 `grep HIDIdleTime` 零命中 ⇒ 「重门禁只在缺席窗口跑」此前**纯靠人工判断、无任何守卫**。守卫工具已入仓（本轮），四路径实测 rc 正确。⚠️ 改 plist 需 `launchctl` 重载 = 动用户级守护进程，**必须你批准**，Agent 不擅自动手（与 D-13「绝不代用户动会话/守护进程」同源）。|
| **A14** | 减弱透明度语义（v8 手册补登记） | 保 solid 纯色（现状已验收）/ 增 frosted 中间态 | ☐ | BENCHMARK §12-A14 |
| **轴2** | Codex 界面取证方式 | (a) 你丢截图 / (b) 择时只读截观察窗 / (c) 延后 | ☐ | BENCHMARK §16 工作单；UI_CODEX_ALIGNMENT 重判节 |
| **RSS 可见态组** | 可见态性能基线 | 你开 App 自然用 ≥10 分钟（我后台只读）/ 免 | ☐ | PERFORMANCE 正式基线节 |
| **G1-SCOPE** | 双轴审计范围追认（DoD「范围经确认」条的正式落点） | 认可现行范围（轴1 A1–A19+材质提案 F3/F4 系列；轴2 W1–W8 观察窗清单）/ 或指出增删 | ✅ 09-04 追认 | BENCHMARK §2/§10/§12/§15/§16 全链在册；本轮补登记（发现 DoD 该条此前无正式确认载体） |

## 拍板记录区（拍一条记一条）

- **D-6** ✅ = 删（24 零事件会话）2026-09-04：用户 chat 答复「1」，双位落位记录（列项首位 = D-6 × 选项首位 =「删」；如属误读一条 revert 即回退）。二次确认口径执行中：DB 只读复核 26=24+2 吻合在册 QUALITY 口径；24 清单 = 18 历史（08-20 16:32 ～ 09-02 22:42）+ 6 本轮副产（BB0112F7/8FF4EE09/618BB207/DF74B23A/6F012001/9191AD8D，09-03 12:02~12:29 登记在案），全部零事件、无标题、turn=0；备份就位（`/tmp/d6-backup/`：`sessions.sqlite.pre-D6` 整库快照 + `sessions_d6_rows.sql` 24 条行级 INSERT，另于执行前追加 `sessions.sqlite.pre-exec` 第三备份）。✅ **09-05 已执行**：用户 chat 答复「执行」= 末道二次确认消费，DELETE 落库；后置三重校验全过（sessions 26→2 / 剩余会话零事件数=0 / 孤儿事件=0），2 条有事件会话与 events/projects 表未动。Keychain 旧凭证 = 可选项，用户手动清理口径不变。

- **D-5** ✅ = 做（G4c 启动）2026-09-04：用户 chat 答复「1」，双位落位记录（blocked#6 报告后列项首位 = D-5 × 选项首位 =「做」；如属误读一条 revert 即回退，代码面尚未开跑、回退成本最低）。Agent 材料立场如实留档：层2 增量收益 ≈0（CENSUS 总表：形态①②层1 已成立、③④不适用），但用户历史立场（社区插件拿来即用）明确，**做=用户裁决非材料推导**。执行口径 = docs/G4C_SIDECAR_DESIGN.md（S-1~S-4 默认策略可否决；C0–C4 全 A 层验收；安全红线含「JS=任意代码执行」授权声明）。

- **G1-SCOPE** ✅ 2026-09-04：用户追认现行双轴审计范围（轴1 A1–A19 + 材质提案 F3/F4 系列；轴2 W1–W8 观察窗清单），无增删。拍板载体：chat 答复「1」（对应 Agent 列项「认可池 B + G1-SCOPE」）。DoD「范围经确认」条闭合。
- **DoD「G1 双轴 checklist 入册且范围经确认」格 · 双口径核销（09-05）**：**字面 ✅**（轴1 checklist=BENCHMARK §2 A1–A19 全册；轴2 checklist=§16 W1–W8 观察窗清单；范围=G1-SCOPE 09-04 追认）；**实质 ⏳**（W1–W8 的「Codex 侧观察」列全空，缺你截图 ⇒ `UI_CODEX_ALIGNMENT` 无法刷新，该项挂在 DoD 的 G3 格上）。⇒ 申报口径：**G1 格勾，但不得据此宣称「Codex 对标已完成」**——与 G4「DoD 达成≠诉求达成」同一处理规则。
- **池 B（R1 #3/#6a/#6b/#7/#8 真机视觉帧补证，㉔ 二选一）** ✅ 2026-09-04：用户选第二项=「认可 A 层进程内证据即满足该子句」→ 静默核销（证据：#3 源码共享+溢出 10 项实测；#6a ThemeLiveRenderTests；#6b FileThemePackageTests；#7 SidebarDropHighlightRenderTests+noChange 单测；#8 GlassSurfaceTests 降级链+测试缝——均在册含 02:26 xcresult 867 项）。#7「用户手动拖一次」子句按 ㉓ 第二分支（认可在册）闭环，A-f 转 G3 可选观察项。**R1 八项全 ✅**。落点 HEAD：本提交（tag `g0-baseline-20260904`）。

- **D-10** ✅ = (a) 窗口透明底 2026-09-04：用户 chat 答复「1」，双位落位记录（G0 收口报告「下一步」第 1 项 = D-10 × 其选项首位 = (a) 透明窗底案；如属误读一条 revert 即回退）。执行=@`ee1da43` 三处联动（makeWindow 透明装配测试缝 / 实底只贴主区 / 侧栏 GlassSurface(.regular) 底）+ WindowGlassSamplingTests 结构测试。**透窗采样实况终裁 = G3 A-d 目检**（㊹ 风险注记：官方无透窗采样明文，锚定 legacy behindWindow 在册能力）；F5（sheet 自铺底）归 D-12 未拍不动，已知其同窗下仍挡 sheet 区折射。

- **账本完整性补登 09-05**：全量 ID 扫描（`docs/*.md` + P1/QUALITY 交叉比对）发现 **D-7/D-8/D-9 三项被 BENCHMARK/SETTINGS_IA_PROPOSAL 引用却从未入本账本**——后果是 G3 手册 §0 P5「§4 全部 D 项有拍板记录」按副本走查会整组漏掉设置页决策簇（D-3 + D-7/8/9）。已补齐三行并同步 G3 §4 副本；**口径重申**：任何文档新设 D-x/A-x 编号，必须同批写入本账本，否则视为未登记。
- **D-13 背景（09-05）**：门禁清偿轮实测 `leaks --atExit` 使 MemProbe 停在 **T 态**后自身死锁（`ps` 状态 `TN`）；`leaks <pid>` 亦 90s 无返回；同一时间窗内 `lldb -b -o run` 与 `sample <pid>` 亦无输出——三条依赖 task 端口的工具同时失效，而 MemProbe 直跑 2s/rc=0，故**不是被测代码问题**。09-04 21:20 该门曾 rc=0 ⇒ 属本机登录会话/调试通道状态退化（首要嫌疑：本人以 SIGKILL 打断 lldb attach；未证实）。**门禁脚本已改为有界+显式失败（rc=142 并清理 T 态孤儿）**，绝不静默放行；RSS 峰值护栏仅作补充证据、不替代 leaks 判据（口径不可自审自批，故立 D-13 请你拍板）。 **【09-05 18:09 否证与撤回】**上列通道级归因不成立：本轮以「同命令 × 两类目标」对照实测，`sample` 对无关进程与被测 GUI 进程均 rc=0，`leaks` 对金丝雀 attach 与 `--atExit` 双路径均 rc=0，且 `tools/ci-local.sh leaks` @当前HEAD 整段 rc=0 ⇒ 第四门禁已真实通过，无需任何环境恢复动作。教训：归因前必须做对照并自证命令语法正确（`sample` 参数误用会瞬时 rc=255 打印 usage，易被记成「无输出」）。
