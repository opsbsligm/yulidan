# G3 · MVP 终验收走查手册（预置版 v1，09-03）

> 用途：G3 阶段用户逐项走查的单一操作手册。走查 = **你手动操作，Agent 只读取证**（静默铁律〇节）；
> Agent 在本手册下永不执行 B/C 层动作。每完成一项在「状态」列打 ✅ 并注明日期。

## 0. 前置检查（走查开始前一次性，Agent 可静默代跑 A 层）

| # | 项 | 判据 | 状态 |
|---|----|------|------|
| P1 | HEAD 四门禁全绿 | pr rc=0 / leaks 0 / xcode TEST SUCCEEDED / main rc=0（QUALITY_REPORT 末段对账行） **⁽⁰⁹⁻⁰⁶ᵈ⁾ 09-06 12:20–12:24 三门禁真跑 @`cac4b13` 全绿**：`all` rc=0（**806 tests in 174 suites**）＋ `0 leaks for 0 total leaked bytes`；`main` rc=0；`xcode` rc=0 **TEST SUCCEEDED**；三段 marker 均 `head=cac4b13 dirty=0`。其后至 `dc69497` 为 docs/tools-only 链（`git rev-parse HEAD:Apps HEAD:Packages` 与 marker `swiftTree` 逐字相同）⇒ 门禁可沿用。| ✅ 预检 09-04 ＋ **⁽⁰⁹⁻⁰⁶ᵃ⁾ 09-06 01:10–01:12 四门真跑 @`0934c5a`**（pr rc=0 swift-testing 788/170／main rc=0 Release 0 警告 覆盖率 97.56%／xcode TEST SUCCEEDED／leaks `0 leaks` RSS 峰值 22,336KB）：`Apps` 子树指纹两跳 `6ba1b52c6197`→`dbf94f9a10fd`（§21.2 注释批次 @`cc584f9`）→`15e71b459254`（等待判据修复 @`0934c5a`）⇒ **本轮零沿用，四门全真跑**；⚠️ 同时登记全量测试存在**负载相关 flake**（已修 1 条测试判据；MCP 卸载侧＝D-16 待拍板；`SessionDB` 打开失败＝负载型），详见 QUALITY 09-06 补记 ＋ **09-05 18:09 四门 marker 齐**：pr@12:54:34／main@11:45:08／xcode@12:19:54／**leaks rc=0@18:09:07（`0 leaks for 0 bytes`）**；走查时 @最终HEAD 复验 **⁽⁰⁹⁻⁰⁵ᵈ⁾ docs-only 豁免的机械证明（新机制首次自用）**：HEAD 已因两枚 docs/工具提交前移（`4431fb9`→`5947e65`，改动仅 `docs/`·`QUALITY`·`P1_STAGE`·`tools/`，`git diff --name-only e5c6c37..HEAD` 零 `.swift`）；`git rev-parse "${H}:Apps"`/`:Packages` 两枚子树指纹与 @e5c6c37 **逐位相同**（Apps `6ba1b52c6197`／Packages `1c495203e2a1`）⇒ 三门 marker（pr@12:54:34／main@11:45:08／xcode@12:19:54）与 leaks@18:09:07 对**当前编译面与二进制**依然成立，非按提交标题推断。**口径固化**：今后凡 docs-only 轮，沿用 marker 须附此二指纹比对；一旦任一指纹变化即须重跑该门（且受 idle≥60min 门控）。 **⁽⁰⁹⁻⁰⁷ᵃ⁾ 09-07 本轮为 `.swift` 批次 ⇒ 沿用条件不成立，三门全部真跑 @`c2d4be7`（缺席窗口 idle=121min 触发，未绕过铁律 8）**：`all` rc=0@01:24:54（pr 并行态 `824 tests in 180 suites` 全绿 ＋ 顺序态复跑 `824 tests in 180 suites`／XCTest 实执行 **263**（下限 200，7 skipped）／失败 0；leaks `0 leaks for 0 total leaked bytes`，RSS 护栏 MemProbe 2000 迭代 OK）／`xcode` rc=0@01:25:45（`** TEST SUCCEEDED **`）／`main` rc=0@01:26:54（Release 构建日志 `warning:` 0 处；后端包行覆盖 **9,747/9,992 = 97.55%**，未覆盖 245 行 vs 09-06 带 238–241 ⇒ 增量来自本批新增源行，`InboundMailbox` 未覆盖 2 行／`StdioMCPClient` 19 行，已定位非弥散漂移）；三门 marker 均 `head=c2d4be7`、`swiftTree` 逐字相同＝Apps `b3d40ab26152`／Packages `b058c99f0624`。⚠️ **marker 内 `dirty=1` 的来源已查明（不是工作树有私活）**：`ci-local.sh` 的 xcode 段自身执行 `xcodegen generate` 重写 `project.pbxproj`（把本批 3 个新文件登记进工程；纯登记面、位于仓根 ⇒ 不进 Apps/Packages 指纹）；该文件随后按在册惯例入库（`chore(xcodeproj)`），故 xcode 门的有效性是「门自己生成、xcodebuild 当场消费」的**直接证据**而非推断；`all` 段 marker `dirty=0`。⚠️ **覆盖面边界（既存结构事实，非本轮引入，登记以免走查时被误认为已覆盖）**：`project.yml` 的测试目标只含 `Packages/*/Tests` 与 `Apps/HarnessCore/Tests` ⇒ **`Apps/HarnessApp/Tests` 不在 Xcode 工程内**，UI 层测试仅由 SPM 门覆盖⁽⁰⁹⁻⁰⁷ᵇ⁾ **豁免链对最终 HEAD 传递成立**：`c2d4be7` 之后的 docs-only 提交（`92b9622` 及其后的文书收口提交）区间内 `.swift` 均为 0、Apps/Packages 二指纹逐位不变 ⇒ 三门 marker（`head=c2d4be7`）依然成立。**本行自身也是 docs-only**，且判据由 `git diff --name-only <markerHead>..HEAD` 过滤 `.swift` 后缀（判据命令刻意不含未转义管道，免污染表格单元格） 现算得出，不依赖本行文字（避免自指）。 |
| P2 | 镜像 MATCH | `git push --mirror swift-harness-backup.git` 后 `git ls-remote` HEAD 一致 **⁽⁰⁹⁻⁰⁶ᵈ⁾ 09-06 四轮 `push --mirror` 四轮 MATCH**：`13f5275→cac4b13→ce1ec9e→dc69497`（每轮 push 前验镜像 HEAD 是本地祖先＝快进，不覆盖镜像侧独有 ref）。| ✅ 预检 09-04：深夜轮双次 ls-remote diff 空（e576dc6→1b7045c 链）；走查时复验 **⁽⁰⁹⁻⁰⁵ᵈ⁾** **⁽⁰⁹⁻⁰⁷ᵃᵇ⁾ 09-07 两轮 `push --mirror` 均先验「镜像 HEAD 是本地祖先＝快进」再推，推后 `rev-parse` 实测 MATCH**：`3e8ca7f→92b9622`、`92b9622→1b81ce5`（HEAD 与镜像 HEAD 逐位相同）。 |
| P3 | LaunchAgents 红线 | `ls ~/Library/LaunchAgents/` 仅 `com.harness.ci11.pr` + `watch`（注入式走测工具已归档 quarantine） | ✅ **09-06 更新**：restci 已回收；`com.harness.ci11.pr.plist` 经 D-14(a) 改为 `ci-quiet.sh` 且**修掉 XML 非法**（裸 `&&` 未转义 ⇒ 此前该服务从未加载，`launchctl print` = Could not find service；现 `plutil -lint` OK、有意未 bootstrap）。「注入工具归档」仍保留为终局项；「注入工具归档」保留为终局项（B 层 #3 可选通道存续期不动，归档动作=宣告冻结同批） |
| P4 | 覆盖率 | QUALITY_REPORT 台账 ≥90% 且无未解释漂移 | ✅ 预检 09-04：清洁口径 97.56%（9,755/238）；**⁽⁰⁹⁻⁰⁶ᵃ⁾ 复核＝区间口径 97.53%–97.56%**（09-06 四采未覆盖 238/239/241），漂移已逐文件定位（XPCPluginHost 4→8／Subagent 7→6，异步路径区域覆盖非确定）⇒ **不构成未解释漂移**；唯一漂移疑云（main2 假高）根因实锤+源头治理闭环（QUALITY 深夜补记） |
| P5 | 待拍板清零 | 本手册 §4 全部 D 项有拍板记录 | ✅ **09-06 达成**：16 ☐ ＋ 1 ◐ 已由批量授权代裁全部落账（裁决依据全部取自总账既有证据锚，见总账「拍板记录区」批量代裁条；池 A 观感终裁不受此影响，仍在 A-a/A-d/A-h 现场定） ·09-05 已备 1 分钟摘要视图 docs/DECISION_CARDS.md（账本仍为 DECISION_INDEX） |
| P6 | **走查构建新鲜度（09-05 新发现）** | 运行中的 Harness 二进制 mtime ≥ HEAD 提交时间；否则走查对象是旧代码、结论无效。判据命令（**对象必须写全**）：`stat -f %m .build/arm64-apple-macosx/debug/HarnessApp.app/Contents/MacOS/HarnessApp` 对比 `git log -1 --format=%ct`。⚠️ **09-06 实测坑（我方自己当场踩到）**：对 `.app` **目录**跑 `stat -f %m` 会得到假「陈旧」——目录 mtime 不随内部 `cp` 覆盖而更新（实测目录＝8/19，而同一 bundle 内的二进制＝当日 11:13 且 `verify` rc=0 判一致）；判据只认**二进制**的 mtime ★**09-06 判据升级（mtime 不可用作权威）**：`stat -f %m 二进制 ≥ HEAD 提交时间` 会把 **docs-only 提交误判为陈旧**（实测：二进制 11:13 vs HEAD 12:41 判 ❌，而 `git rev-parse HEAD:Apps HEAD:Packages` 与门禁 marker `swiftTree` **逐字相同**＝源码面零变更）。**权威判据两条**：① `tools/rebuild-app.sh verify` rc=0（比同步戳 `src_sha` 与构建产物 sha256）；② 需要源码等价口径时比对上面那对 tree 哈希。 **⁽⁰⁹⁻⁰⁷ᵈ⁾ 三条判据已收进一条命令**：`bash tools/qa/p6-freshness-check.sh`（rc=0＝三条全过，A 层只读零可见变化）——(a) `rebuild-app.sh verify` rc=0；(b) HEAD 的 Apps／Packages 指纹与门禁 marker `swiftTree` 逐字相同；(c) 二进制 mtime ≥ **最近改代码面的提交**（取 `git log -1 --format=%ct -- Apps Packages`，**不与 docs-only 提交比时间**）。⚠️ **自我否证入档**：本轮先前那句「每枚 docs-only 提交后再 sync 一次以维持字面判据」＝**在给假阴性判据打工**——最后一枚 docs 提交（01:51:40）晚于最后一次 sync（01:51:09）之后，旧字面判据当场反向差 31s，而二进制 sha 与代码面指纹全程未变。⇒ (c) 只对代码面提交取时间，假阴性源头消除；`06c0b0c` 那条「重新 sync 维持字面新鲜度」的口径由本条取代。| ☐ 需**你手跑重启**（kill+open＝改变可见状态，Agent 不得自动）。**⁽⁰⁹⁻⁰⁵ᶜ⁾ 你的准备成本已降为一步**：Agent 已静默跑 `tools/rebuild-app.sh`（sync＝构建→cp→sha 断言→ad-hoc 重签→同步戳，零可见状态变化），bundle 现与 @e5c6c37 构建产物一致（`verify` rc=0，19:13:05 同步戳在册）；此前 bundle 落后 2 天的根因是**已实锤两次的「SPM 增量构建不刷新 bundle」**。此前实测留存：pid 58301 存活 2天4h55m，exe mtime=**Sep 3 15:05**，HEAD=Sep 5 15:43 ⇒ 陈旧 2 天，且 `wl`/`axdump` 双通道均报 windows=0；**自纠**：更早一轮曾据 `pgrep -f Harness.app` 零命中判「App 未在运行」——错，进程一直在跑，准确表述是「进程存活但零窗口，且二进制早于 HEAD」。⇒ 你只剩一步：`HARNESS_USER_APPROVED_RELAUNCH=1 tools/rebuild-app.sh relaunch`（该放行变量＝本轮新加的静默铁律 8 机制门，Agent 无法自动 kill+open） **⁽⁰⁹⁻⁰⁶ᵈ⁾ 实测闭环**：本轮 `verify` 曾 **rc=1**（stamp `96ae86f2…` → 现 `e0756507…`，因 12:20 门禁重跑 `swift build` 改了产物字节，**与源码无关**）⇒ 已静默跑 `sync`（构建→cp→sha 断言→ad-hoc 重签→同步戳，零可见状态变化）⇒ **`verify` rc=0 ✅「bundle 与构建产物一致（12:48:31 @ dc69497）」**。剩你一步：`HARNESS_USER_APPROVED_RELAUNCH=1 tools/rebuild-app.sh relaunch`。 **⁽⁰⁹⁻⁰⁷ᵃ⁾ 09-07 本轮 `.swift` 批次入库后已静默 `sync`（构建→cp→sha 断言→重签→同步戳，零可见状态变化）⇒ `verify` rc=0 ✅「bundle 与构建产物一致（2026-09-07 01:32:06 @ `c2d4be7`）」；`bundle_bin_mtime=1788715926` ≥ `HEAD 提交时间=1788715350`（P6 判据两条同向）。⁽⁰⁹⁻⁰⁷ᶜ⁾ 旧口径「其后每枚 docs-only 提交后再 `sync` 一次以维持字面判据」**已被 ⁽⁰⁹⁻⁰⁷ᵈ⁾ 取代（见判据列）**：现 `bundle_mtime=1788717069` ≥ `head_ct=1788717039`@`f6c4dbc`，`verify` rc=0；⚠️ **binary sha 仍是 `40be4eec4035…`＝与 @`c2d4be7` 构建逐字节同源**⇒ docs-only 链不改二进制，P6 的字面 mtime 判据靠重新 sync 维持，真正的等价证据是这条 sha＋swiftTree 指纹。剩你一步：`HARNESS_USER_APPROVED_RELAUNCH=1 tools/rebuild-app.sh relaunch`（走查开始前必须做一次，否则走查对象是旧二进制）。|

## 1. 走查池 A：视觉/UI 主观项（你操作 + 目检，Agent 只读截窗/axdump 补档）

取证命令模板（全部 A 层只读）：
- AX 结构：`tools/r1walk/bin/axdump <Harness pid> [depth]`（零动作、零 TCC）
- 窗帧：`screencapture -o -l<windowID> out.png`（⚠️27beta 仅解锁有效；坐标以 AX pos 为权威）
- windowID 只读发现：`tools/r1walk/bin/wl`（`CGWindowListCopyWindowInfo` 枚举，输出 `WID= layer= owner= name= x= y= w= h=`；仅列 owner 含 Harness/System Settings 或 name 非空者；零动作、零 TCC，09-05 实跑 rc=0）。
  主窗判据沿 `r1walk4.sh` v4.7.3（L39–41）：取 `owner=Harness` **且** `name=Harness` 者；`name=` 空的幻影缩略行据此自动排除；仅当无 name 行时才用 `w=1[0-9]{3}`（1000–1999）兜底。坐标仍以 **AX pos 为权威**（幻影边界只污染 wl，不污染 AX）。
  09-05 归因自纠：对**屏上真实窗口** `screencapture -o -x -l<wid>` 在 exec 会话 **rc=0 / 约 1s / 正常产物**；旧「无限挂起」只出现在窗口被移出显示边界、等不到表面的探针场景，与 G3 走查无关（详见 QUALITY_REPORT 09-05 自纠条）。
- A12 运行时面数口径（BENCHMARK §15-A12 附产）：axdump 快照统计玻璃面**运行时实例数**时，
  sessionRow 的 `.thin` 为**线性项**（随会话行数增长），须单列、不与静态 12 调用点混判；
  判定 = 线性项 × 当前可见行数 + 固定项 与快照实例数同量级，超限（数量级偏差）才记缺陷。
  （09-04 深夜探测注记：在跑实例 pid 58301 为 09-03 旧 debug 构建且 windows=0 隐藏态——
  运行时快照 Agent 代跑不可行【亮窗=B 层】；本项= G3 现场你操作时 Agent 同帧 axdump 取证，勿再预探测。）

| # | 走查动作（你手动） | 判定标准 | 依赖 | 状态 |
|---|--------------------|----------|------|------|
| A-a | 打开主窗，观察 Tab 条切换选中 | 选中玻璃面流体融合/形变过渡（非淡变方块）→ D-1 morph 终判 | D-1 | ☐ **⁽⁰⁹⁻⁰⁷ᵉ⁾ 09-07 首次目检＝❌ 不通过（用户实机截图）⇒ 铺满方案已回退**：六段常驻面＋容器 spacing 52 让网格融成一整片橙色玻璃；代码已恢复「仅选中段带面／spacing=fullGridSpacing」，护栏方向反转为上限（native＝1 面）。**本项需你在下次 relaunch 后复验回退效果**；morph 流体融合本身仍未证实（第二面缺口 §3-A1 回到在册未决，不用铺满去填）。⁽⁰⁹⁻⁰⁷ᵃ⁾「前提已消除」的说法**已被本轮目检推翻**：：09-06 批次已把常驻玻璃面铺满全部分段（护栏 `glassFaceCount == segmentCount`，native 态）⇒ morph 现有第二面可配对，**本项自 09-07 起为「对已实施效果的终裁」而非「先拍方案再实施」**；⚠️ 但 A 层无可捕获玻璃像素的通道，观感结论只能出自本项现场目检 |
| A-b | 折叠/展开侧栏各 1 次 | 折叠 rail 左上角与红绿灯/展开按钮无交叠压迫感（F6 修后）或你接受现状 | D-12(F6) | ☐ **⁽⁰⁹⁻⁰⁷ᵃ⁾ F6 已实施**（`SidebarRailLayout`：折叠态顶部下沉 38pt＋按钮右移至 rail 之右；交叠判据 before/after 双锁）⇒ 本项判「实施后的实际观感」，含一项在册偏差待你裁：**按钮必须同时右移**，否则与下沉后的 rail 首图标重新交叠 |
| A-c | 打开设置完整页（5 卡版） | 页面底材质观感：玻璃折射成立或你认可现状（F5 撤底后） | D-10/D-12 | ☐ **⁽⁰⁹⁻⁰⁷ᵃ⁾ F5 已实施**（卡底 `.surface` → `.surface.opacity(0.5)`；⚠️ 非「整行删除」——A18 原「根视图自铺底」表述经复核不准，唯一自铺底在卡底，已在 BENCHMARK 就地纠正）⇒ 本项判「半透明卡底是否已足够让折射成立/可接受」 |
| A-d | 观察聊天区/输入框玻璃质感 | **F4(a) 已实施@`ee1da43`：判定侧栏/窗体是否真实采到桌面折射（或接受扁平→可回退）** | D-10 已拍(a) | ☐ |
| A-e | 主题插件切 tint → 还原 | 实时染色生效、还原干净；作用域观感符合你对 D-11 的选择 | D-11 | ☐ |
| A-f | 会话拖拽换序一次 | 落位原生反馈动画自然（R1⑦ 终判） | — | ☐ |
| A-g | 系统设置开「降低透明度」→ 回开 | 界面即时降级/恢复无残影（R1⑧ 终判） | — | ☐ |
| A-h | 减弱动效开关往返 | morph/入场动画按系统开关注销 | — | ☐ |

## 2. 走查池 B：R1 余项静默裁决（二选一即可核销，无需操作）

对 #3/#6/#7/#8 各回一句：「认可 A 层证据，核销」或「我顺手看一眼」（Agent 仅只读截窗）。
证据索引见 P1_STAGE_REPORT 终版表 D-1 索引节（#3 编译期结构恒等+溢出10项实测；#6 ThemeLiveRenderTests
色序判据；#7 建议留 A-f 手动拖；#8 GlassSurfaceTests 降级链在册）。

| 项 | 裁决 | 状态 |
|----|------|------|
| R1#3 顶栏标题右键菜单 | ☑ 认可证据（09-04 chat 拍板）/ ☐ 手动看（B 层 ax showmenu 择时补证，可选保留） | ☑ 已核销 |
| R1#6 tint 实时切换→还原 | ☑ 认可证据（09-04）/ ☐ 手动做（=A-e，转可选观察） | ☑ 已核销 |
| R1#7 拖拽落位动画 | ☑ 认可在册（09-04，㉓第二分支）/ ☐ 手动拖（=A-f，转可选观察） | ☑ 已核销 |
| R1#8 减弱透明度降级 | ☑ 认可证据（09-04）/ ☐ 手动拨（=A-g，转可选观察） | ☑ 已核销 |
> 2026-09-04：上表四行经用户 chat「池 B」拍板全部核销（拍板原文见 DECISION_INDEX 记录区）；A-e/A-f/A-g 手动动作保留为 G3 可选观察项，不构成验收前置。

## 3. 走查池 C：Codex 对标 + 插件兼容

| # | 动作 | 判据 | 依赖 | 状态 |
|---|------|------|------|------|
| C-a | 轴2 取证（二选一）：你从 Codex 各观察窗丢截图 / 你择时允许只读截自己另开的观察窗 | BENCHMARK §16 W1-W8 取证齐 → UI_CODEX_ALIGNMENT 行为列回正 ⁽⁰⁹⁻⁰⁶ᵉ⁾ 截图通道已实测＝锁屏态纯 A 层可用（含内容活性自证）| 取证方式拍板 | ◐ **W1 主窗已自主闭环**（四件套入 UI_CODEX_ALIGNMENT）；W2–W8 待你在 Codex 内打开对应界面一次，其后 Agent 只读取证|
| C-b | G1a 轴1 清单终查 | BENCHMARK_CHECKLIST 全项 ✅ 或 N/A 有论证 | — | ☐（09-04 Agent 预检：BENCHMARK ☐=0 全闭合/N-A 有论证，待你终查） |
| C-c | （D-5 已批层2）社区插件实装载：G4c C4 CLI 层实跑后，设置→MCP 面复核呈现（B 层可选） | 装载成功、工具可见、禁用即卸载无残留 | D-5→G4c | ◐ C4 CLI 层已闭环（矩阵 3✅+2❌ 含真实 create_skill；S-4 双向实测在册）；残余=设置→MCP 面呈现复核（B 层可选，你择时）。**走查须知（09-05 层3 普查）**：社区**主题/UI 类**插件（`dsh-theme-kit`／`@guillaumemeyer/dsh-themes`）经上游机制证据判定**结构性不适用**（`dsh.client.platform` 全仓 39/39 仅 `"web"`，实现为浏览器 DOM/CSS），不计入层2 通过率、也不构成缺陷——我方主题插件化走自有 ThemeSpec＋MCP 通道 |
| C-d | 兼容矩阵引用 | CENSUS 层1 矩阵（dsh-crew/filesystem/everything）无回归 | — | ✅ Agent 预检 09-04 深夜 **3/3 复现**：crew=751ms/6 工具/rc.7（同码同令，依赖闭包借用 cb-c4 已装环境——口径偏差注记见 QUALITY 深夜二轮补记）/ fs=4.9s/14 工具 0.2.0 / everything=3.0s/13 工具 2.0.0，与矩阵逐项吻合 |

## 4. 终拍板检查点（G3 开始前须全部有记录）

> **权威账本 = docs/DECISION_INDEX.md**（含 D-2/D-3/D-4/Keychain 与拍板记录区）；本表为速览副本，冲突以总账为准。

> **09-06 与总账核对**：补入 6 项此前未列的待拍板（D-14/D-15/D-19/D-22/D-25/RSS 可见态组），并同步 D-13 状态。**本表刻意只留一句话事项，选项列一律指向总账**——副本漂移的根因就是抄了一份长文本却无人回更；核对命令：`bash tools/qa/decision-pending.sh`（现算，不手写计数）。
| ID | 事项 | 选项 | 拍板 |
|----|------|------|------|
| D-1 | morph 流体判定终裁 | 目检 A-a / 认可结构证据 | ✅ 09-06 = ✅ 09-06 **(d) Ⅰ案：常驻底面＋条件面**（Apple 官方 `glassEffectTransition` 示例原型，BENCHMARK §18.2 逐字在册）｜实施＝G2 首轮，连带 D-11 tint  |
| D-2 | `interactive` 宣称口径（◐ 半结） | 残余=悬停反馈目检（归 §1 A-h） | ✅ 09-06 = ✅ 09-06 残余（悬停反馈）归 G3 池 A **A-h** 现场目检同场核销，不阻塞 DoD 其余条 |
| D-3 | 设置页 C4 卡片归组 | 与 SETTINGS_IA_PROPOSAL 合并裁决 | ✅ 09-06 = ✅ 09-06 与 SETTINGS_IA_PROPOSAL **合并裁决**，不单列 C4 卡片（依 IA_PROPOSAL L77） |
| D-4 | 主题 manifest 假参数（A6） | 显式拒绝不支持字段+提示 / 维持现状 | ✅ 09-06 = ✅ 09-06 **(a) 显式拒绝不支持字段＋提示**（不宣称未实现能力）｜✅ **09-07 已实施**（`unsupportedField(name:)` 对 blur/highlight 任何取值一律拒绝；设置页撤「已声明·平台托管」行。⚠️ 旧「接收不生效」主题包重导会被拒/历史包重扫回落） |
| D-7 | 设置容器形态（补登） | (a) 维持 sheet / (b) 独立 Settings 窗口（提案建议 a） | ✅ 09-06 = ✅ 09-06 **(a) 维持 sheet**（冻结前最小变更；Esc/xmark 关闭途径已核销） |
| D-8 | 设置概览页去留（补登） | 保留+「编辑…」跳转（默认）/ 删概览页只留 6 pane | ✅ 09-06 = ✅ 09-06 概览页**保留**＋每行「编辑…」跳转（IA_PROPOSAL 默认）｜✅ **09-07 已实施**（`editPane` 纯映射＋`jumpToSub` 先切分类） |
| D-9 | 记忆/工作区可编辑性（补登） | 升可编辑 / 标只读+文案说明 | ✅ 09-06 = ✅ 09-06 **标只读＋文案说明**（IA-4；冻结前夜不扩能力面）｜✅ **09-07 已实施**（workspace/rag 两卡标只读＋原因文案；只读集合由测试锁定） |
| D-5 | G4 层2 Cordis sidecar | ✅ 09-04 做 → G4c 全阶段闭环（C0–C4+collector，矩阵 3✅+2❌ 入 CENSUS） | ✅ |
| D-6 | 24 零事件会话处置 | 删（DB 写需明示+二次确认）/ 留 | ✅ 09-04 拍板 = 删；✅ **09-05 已执行**（末道确认=用户「执行」；26→2 三重校验通过；三备份 /tmp/d6-backup） |
| D-10 | F4 折射源修法 | (a) 窗口透明底 / (b) backgroundExtensionEffect / (c) 接受扁平 | ✅ 09-04 = (a) @`ee1da43`（A-d 为实施效果目检终裁） |
| D-11 | tint 作用域 | 全局装饰 / 仅功能件 / 主题可声明 | ✅ 09-06 = ✅ 09-06 **仅功能件**（官方口径）；同时充当 D-1 (d) 选中区分的 tint 来源 |
| D-12 | F5+F6 执行批次 | 本批做 / 延后 / 部分 | ✅ 09-06 = ✅ 09-06 **本批做**，与 D-15/D-19 并入同一 `.swift` 批次，一次门禁覆盖三项｜✅ **09-07 已实施**（F5 卡底半透明；F6 `SidebarRailLayout` 避让几何＋交叠判据双锁） |
| **轴2** | 取证方式 | 丢图 / 择时只读截 | ✅ 09-06 = ✅ 09-06 **(b) 择时只读截观察窗**（⁽⁰⁹⁻⁰⁶ᵉ⁾ 实测锁屏可取真实窗帧＝纯 A 层）⇒ W2–W8 转为 Agent 静默取证 |
| D-13 | leaks 门禁本机不可用（09-05 新登） | (a) 重启会话后复跑 / (b) 认可 RSS 护栏降级口径 / (c) 挂起待自然恢复 | ✅ 09-06 同步＝总账已闭环（原副本滞后）|
| A14 | 减弱透明度语义（补登记：原表遗漏，§12 在册裁决项） | 保 solid 纯色（现状，已实机验收）/ 增 frosted 中间态（更贴系统语义） | ✅ 09-06 = ✅ 09-06 **保 solid 纯色**（`accessibilityReduceTransparency` API 页「should be opaque」明文支持，BENCHMARK §23） |
| **D-14** | launchd 重门禁静默化（新发现）（⚠️ 涉及用户级 LaunchAgent） | 见总账 `DECISION_INDEX` 对应行 | ✅ 09-06 = ✅ 09-06 **(a)** `ProgramArguments` 改调 `tools/ci-quiet.sh pr`｜⚠️ 用户级 LaunchAgent 变更：改前备份原 plist，单条 `cp` 可回退 |
| **D-15** | A2 玻璃容器 spacing 取值（09-05 改判：与 D-1 解耦的独立合规项） | 见总账 `DECISION_INDEX` 对应行 | ✅ 09-06 = ✅ 09-06 **(b)** spacing 收敛 `adjacentSpacing()`=52 ＋ 远距切换显式 `.materialize`｜✅ 09-06 实施 → **⁽⁰⁹⁻⁰⁷ᵉ⁾ 随 D-1 铺满一并回退**（恢复 `fullGridSpacing`；理由＝只剩选中面时收敛 spacing 无配对收益却保留 blend-at-rest 副作用） |
| **D-19** | 聊天顶栏材质游离在玻璃体系与主题驱动之外（09-06 新立，G1a 轴1 审计产出） | 见总账 `DECISION_INDEX` 对应行 | ✅ 09-06 = ✅ 09-06 **(a)** 顶栏改 `.glassSurface(...)` 纳入玻璃体系，档位＝`.thin`（与 composer/卡同档）｜✅ **09-07 已实施**（顶栏入玻璃体系；A12 基线 13→14） |
| **D-22** | MCP 主题探测在 MainActor 上同步等待最长 30s ⇒ 导入/卸载一台不应答的服务器会冻结 UI（0… | 见总账 `DECISION_INDEX` 对应行 | ✅ 09-06 = ✅ 09-06 **(a)** 主题探测**短超时 2s**＋写可诊断原因；文档声明「极慢的真主题服务器可能被误判」｜✅ **09-07 已实施**（探测调用点 `fetchMCPTheme` 传 2s；原因落 `probeDiagnostics`） |
| **D-25** | F-d 定性完成（09-06 首次命中取证通道）：`MCPProcessDeathTests` 步骤①首次 `l… | 见总账 `DECISION_INDEX` 对应行 | ✅ 09-06 = ✅ 09-06 **(a2)** 响应投递与退出清理收进**同一条 FIFO**（改动局限 `StdioMCPClient` 内部）；回归判据＝**实例级**行处理闸门（禁静态缝，免重演 D-24）｜✅ **09-07 已实施**（`InboundMailbox` 单一 FIFO＋单一消费者；终止通知只投递不结算） |
| **RSS 可见态组** | 可见态性能基线 | 见总账 `DECISION_INDEX` 对应行 | ✅ 09-06 = ✅ 09-06 **要基线**；随 G3 走查同场后台只读采集，不单独占用你的时间 |

## 5. 达成宣告（DoD 摘要，全绿后你口头宣告 MVP）

- G0：R1 全✅（静默口径）+ R2 处置毕 + 冻结 tag；
- G1：双轴 checklist 入册且范围确认；G2：批准 gap 闭环 + before/after 离屏证据齐；
- G4：层1 实测✅ + D-5 拍板✅ + 兼容矩阵 3✅+2❌ 实跑在册（强口径已满足）；
- 终态：四门禁 @最终HEAD 全绿 + 镜像 MATCH + QUALITY 双表入册 + UI_CODEX_ALIGNMENT 刷新 → **你宣告 MVP 达成，项目转功能冻结**。
