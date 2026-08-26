# P0 实机验收清单（2026-08-22 首版，当前 HEAD 446c2d7）

> 用法：逐项操作 → 对照「预期」打勾。全部通过后回复「P0 验收通过」，即解锁 P1 Liquid Glass。
> 验收环境要求：当前开发机即可（无 Apple Team 时 SSO/iCloud 走「无 entitlements 优雅降级」，属预期行为非缺陷）。
>
> ✅ **2026-08-24 周一验收环境就绪**：App 已重启（PID 98463，HARNESS_FRAME 定点内建屏，契约 v2 二进制 nm 核验），Ollama 0.32.15 + qwen3:4b 就绪（launchd 托管），UI 截图 /tmp/harness_monday.png（Composer 显示本地 qwen3:4b，项目/会话真实数据加载正常）；凌晨 03:38 环境侧外部终止（无崩溃报告，详见 QUALITY_REPORT §四 P2）已于 10:19 定点重启恢复。

> 🔄 **2026-08-24 10:54 用户实机走查启动（被动观察证据，不代替验收打勾）**：新会话首条消息「test」→ 标题自动派生 ✓；qwen3:4b 流式应答 + 事件落盘（5 事件 = 3 用户 + 2 助手，model=qwen3:4b，sessions.sqlite 只读核验）✓；新会话 cwd 正确路由 `agents/<sessionID>/`（P0.1.5 工作区路由实机核销，DB 证据）✓；生成中指示 + 停止按钮实时 ✓。⚠️ 模型对「今天星期几」答「今天是星期二」（今日实为周一 08-24）——本地 4B 模型自身事实幻觉，非 App 链路缺陷（流式/落盘/路由均正确；追求准确性请换更大模型或远程服务商）。

> 🔄 **2026-08-24 11:39 追加实机证据（4K 屏截图 /tmp/4k_check.png）**：会话「test」中模型自主调用 MCP 工具 `mcp_local_current_time {}` → **对话内出现可折叠工具行 + 绿色成功标记**（§五 全链路 + §六 工具回显示机核销）；随后回答「今天是星期二」仍误（工具已返回正确时间，4B 模型自行推导星期出错，P2 日期注入改进项继续有效）。

> 🔄 **2026-08-24 18:30 差距审计轮（被动证据，不代替验收打勾）**：P0 清单 §三~§六 逐项映射测试证据完成（业务逻辑层全覆盖；拖拽悬停高亮/快捷提示填充/模型下拉视觉项属纯 UI 走查项）；审计驱动发现并修复 2 处 P1 缺口（`7447179`）：① MCP 卸载后 Agent 工具注册表残留陈旧 mcp_* 工具（§五「卸载后工具即时移除」Agent 侧缺口，现已闭环 + 真实 stdio 服务器单测）② RAG 入库不落盘 → CLI 跨进程知识库丢失（e2e 实锤，已闭环）；RAG CLI e2e 跨进程实证：入库 → index.json 落盘 → 新进程检索溯源命中 → 正确回答；四门禁全绿 664/664（/tmp/ci_{pr,main,leaks,xcode}_ragfix.log）。

> ✅ **2026-08-26 验收环境重新就绪（本回合核验）**：Ollama 0.32.15 重启（launchd）+ qwen3:4b 在位；App 配置复核 = providerRaw local / qwen3:4b / http://localhost:11434/v1 / maxTokens 4096、theme=system（系统基准哨兵）；App 已从 HEAD `8ef7053` 启动（PID 70301，.build debug bundle，swift build 0 警告）；全量回归 **790/790（172 suites）全绿 @8ef7053**（/tmp/p0_test_0826.log）；插件状态：file-system/terminal/theme-sunset/theme-ocean（builtin, enabled）+ fs-test（localMCP, enabled）；镜像备份已同步 `8ef7053`。代码级复审（08-24 差距审计后三高风险域）：① 主题插件经 ThemeProviderPlugin 插件机制交付 + 来源消失自动回落 systemBaseline（ThemePluginManager L92-98）+ 三层测试 ② RealAppleSignInService 纯 AuthenticationServices（ASAuthorizationAppleIDProvider.createRequest / ASAuthorizationController，MainActor 隔离，官方 API 注记在案）③ iCloud 双根 WorkspaceRouter + KVS 元数据同步 + 权限探测/降级组件齐备（Account 包 6 文件）——均无新缺口。**剩余阻塞 = 用户侧**：实机视觉走查逐项打勾 + Apple Team ID（SSO/iCloud entitlement 项）。

> ✅ **2026-08-26 DSH CLI 后端全链路 e2e 复跑（HEAD `d2cb3fb`，无头，锁屏环境可执行）**：`dsh run` + local/qwen3:4b @localhost:11434 —— 真实流式 → Agent 主循环 **2 次工具调用**（write_file → read_file）→ 文件落盘 `e2e-check-0826.txt` 11 字节内容 `e2e-0826-ok`（md5 9b6a9d627c52a96aad4678a6f8251896，原件存档 /tmp/e2e-check-0826-verified.txt，仓库已清理）→ 最终回复引用读取结果，闭环正确；技能体系自动沉淀（write-file-weekend-ok，2 次相似任务触发）；MCP 测试服务器（fs-test/rm-test/dup）连接失败时 Agent 优雅降级不中断（与 08-22/08-23 历次 e2e 行为一致，属预期）。日志：/tmp/dsh_e2e_0826.log。

> 🔄 **2026-08-26 12:43 用户实机走查进行中（被动证据，不代替验收打勾）**：机器解锁后 App（PID 70301）置顶核验——左侧边栏渲染真实数据：导航五项（对话/多Agent/插件/技能/工具）+ 项目分组（工作演示 0 / test 1，含展开箭头与会话计数）+ 全局会话（test、帮我创建一个新项目，含相对时间戳）；设置面板打开于「插件管理」页（通用/模型服务/插件/插件管理/关于五页在列）；**归档管理 sheet 实测可见**：归档项目（1）「归档示例项目」+ 归档会话（1）「帮我创建一个新项目」，各带「恢复」按钮（§三 归档管理入口 + 取消归档实机证据）。截图 /tmp/p0_0826_app.png。

> ⚠️ **2026-08-26 13:2x DB 数据卫生修复（走查前清理，非代码缺陷）**：走查间隙读库发现「工作演示」项目存在 2 行——id 仅十六进制大小写不同（`771da037-…` vs `771DA037-…`，同一 16 字节 UUID），created_at 完全相同（整数秒 1787244917.0，与「归档示例项目」批量种子时间戳一致），无任何会话引用大写行。定性：**开发期演示数据种子的一次性残留**（正常 `createProject` 路径经 `UUID()` 生成，Apple 平台 uuidString 恒小写，现网代码不可复现）；但两行在内存中 UUID 值相等（firstIndex 命中不确定 + 重启后空项目复活风险，污染验收）→ 已清理：先备份整库 `/tmp/sessions_backup_0826_131839.sqlite`，再 DELETE 孤儿大写行，projects 表现 3 行（工作演示 / 归档示例项目[archived] / test），会话 4 行不变；App 干净重启（PID 92377）加载清理后 DB。防御性加固（loadProjectRows 按 UUID 值去重）记入 P2 待办，本轮不改代码（铁律 2：P0 验收前不扩范围）。

> 🔧 **2026-08-26 22:0x P2 数据卫生加固核销：loadProjectRows 按 UUID 值去重（13:2x 事件跟进，@5638ef9）**：`SessionDB.loadProjectRows` 加载后经 `dedupProjectRowsByUUIDValue`（纯函数）按 UUID 值去重——不可解析为 UUID 的 id 原样保留（纯防御分支）；同一 UUID 值多行时优先保留 id 与平台规范形式（`uuid.uuidString`，即会话 metadata_json 编码 / 项目持久化 / 删除路径共用形式）一致的行；无规范形式行则保留排序最前一行。新增 4 测试（纯函数 3：大小写变体两种输入序均留规范行 / 无规范取首行 / 不同值+非 UUID id 不受影响；DB 级 1：TEXT 主键下大小写变体共存两行 → 仅留规范行）。⚠️ **平台实测发现（铁律 1 材料）**：本机 macOS 27.0 beta（26A5416b）/ Swift 6.3.3 下 `UUID().uuidString` 实测输出为**大写**（两次独立探针：新生成 `UUID()` 与 `UUID(uuidString:)` 往返均大写）——13:2x 条目所述「Apple 平台 uuidString 恒小写」在旧平台成立、本机新平台不成立；去重规则以系统 `uuidString` 实际输出为基准（平台自适应，不硬编码大小写），新旧平台行为均正确。门禁：ci-local pr 全绿（SwiftLint 0 违规 / SwiftFormat 0 文件 / 编译 0 警告 / Swift Testing **808/808（175 suites）** + SessionDBTests XCTest 23/23）。

> ✅ **2026-08-26 22:5x 无人值守四门禁复跑 @9a25771（机器锁屏）**：main（Release 0 警告 / 808/808 / 干净覆盖率 核心 14 包 98.87%（7059/7140，未覆盖 82→81）/ 18 包全量 96.24%（9655/10032））+ leaks **0** + xcode **TEST SUCCEEDED**（SessionTests 23/23 含 4 新去重测试）+ pr（22:0x）全绿，日志组 /tmp/ci_{main,leaks,xcode}_dedup.log；实测发现：锁屏态 CGWindowList 不含本 App 窗口（0 窗口）→ 窗口幻影 P2 被动探测待解锁执行；真实库只读复核去重零影响（4 行不同 UUID）。dsh 全链路 e2e 复跑 @9a25771（23:0x）：真实流式 → 2 次工具调用（write_file→read_file）→ `/tmp/e2e-check-0826-2301.txt` 16 字节 `e2e-0826-2301-ok` 读回一致（md5 8948713d1e80d8b7ce9d6698ddefb9dc），MCP 三测试服务器优雅降级（历次一致），日志 /tmp/dsh_e2e_0826_2301.log；22:17 重启后无新崩溃报告（用户+系统 DiagnosticReports 双查）。详见 QUALITY_REPORT 同日条目。

> ✅ **前置条件已解决（2026-08-22）**：对话类验收项（§二会话工作区 / §五全链路 / §六流式·停止生成·工具回显）所需 LLM 已就绪——Ollama 0.32.15（brew formula，launchd 托管 `brew services list | grep ollama`）已装并 `pull qwen3:4b`（2.5GB，Metal/M5，端点 `http://localhost:11434/v1` 实测可用）；App 配置已切 **local provider + qwen3:4b**（原配置 openai/o4-mini 无 key 不可用，已备份 /tmp/harness_llmconfig_old_readable.json，验收后可随时还原）；工具调用 e2e 实测：OpenAI 兼容请求正确返回 `write_file` tool_calls（与 App wire 格式一致，max_tokens 4096 足够含思考输出）；**DSHCLI 全链路 e2e 实跑（2026-08-22，`dsh run` + local/qwen3:4b）**：真实 LLM 流式 → Agent 主循环 2 次工具调用（write_file→read_file）→ 文件落盘 `ws-check` 8 字节核验一致 → 最终回复正确；MCP 测试服务器（/usr/bin/true×3）优雅降级不中断；记忆蒸馏落盘（无记忆价值任务正确判空）、技能进化观测在阈值下正确未误触发；**2026-08-23 周末无人值守复测**：`dsh run` 复跑（local/qwen3:4b）2 次工具调用（write_file→read_file）→ `weekend-check.txt` 10 字节（md5 dfcec55e…）落盘一致、MCP 测试服务器降级行为一致、最终回复正确（日志 /tmp/dsh_e2e_weekend.log）。若服务停止：`brew services restart ollama`。不依赖 LLM 的项（§三 全部 / §四 导航 / 会话重命名）仍可先行验收。

> 🐛 **2026-08-26 15:30 用户报障闭环：二级页面无返回途径 + 假关闭按钮（实机定位 + 修复 + 实机验证，@4b5b29b）**：
> - **假「关闭」按钮（实锤）**：归档管理 sheet 的「关闭」是空闭包 `Button("关闭") {}`（macOS sheet 无下滑手势 → 用户点按钮无反应，只能 Esc 或误以为 App 卡死）→ 改 `@Environment(\.dismiss)` 自关闭。实机验证：顶栏归档图标 → sheet 弹出（归档项目1+归档会话1）→ 点「关闭」→ **sheet 真实关闭**（截图 /tmp/harness_v2_archsheet.png → /tmp/harness_v2_archclosed.png）。
> - **设置页无返回途径（实锤，根因两层）**：① 展开态侧边栏**源码无底栏**（08-24 脏工作区构建的二进制带底栏但「设置」行无选中态、点击不返回；用户运行的即该版本——源码后回退造成版本漂移，截图 /tmp/harness_ui_0826_1510.png 实锤用户卡于设置内）；② 即使有底栏，设置是内容 tab，唯一「回去」动作是点其他导航行（最自然的「新对话」行有创建新会话副作用）→ 用户感知无路可退。修复：a) 展开态底栏恢复（设置行 ⌘, + **选中态高亮** + 头像行，与折叠 rail 对齐）；b) **设置页头部新增「关闭设置」X 按钮**：进入设置记录来源 tab（`AppViewModel.settingsReturnTab`，selectedTab.didSet 跟踪；离开设置更新为当前 tab；重复选中不变），点 X 回原位；c) ⌘6 死码清除，settings 统一 macOS 标准 ⌘,。
> - **实机验证闭环（最小可逆操作）**：⌘, → 进设置（底栏「设置」行高亮 ✓ + 头部 X ✓，/tmp/harness_v2_settings.png）→ 点 X → **回对话 tab** ✓（/tmp/harness_v2_back2.png）；连接测试失败消息现干净单前缀「连接失败：无法完成到服务器的连接…」——用户截图所见「连接失败：连接失败：连接失败」三重嵌套定性为**旧脏构建残留**（现源码全仓 grep 无该嵌套串，LLM 包仅单处包装 @SettingsSubPages:390），/tmp/harness_v2_conntest.png。
> - **门禁**：swift build 0 警告 + SPM 全量 **796/796（173 suites）全绿 @4b5b29b**（790 基线 + 6 新 settingsReturnTab 单测：默认对话/对话进入/工具进入/设置内切换/重复选中/连续切换）。
> - **⚠️ 流程教训（记 P2 观察）**：SPM 增量构建**不更新 .app bundle 内可执行文件**（bundle 停留在 08-24 旧二进制，sha 不一致实锤）——本轮已手动 `cp` 可执行文件 + ad-hoc 重签（entitlements get-task-allow）+ nm 新符号核验（settingsHover×7）后启动。后续每次「启动 App 验证」前必须先核验 bundle 二进制版本（nm/sha 对拍），杜绝「源码已修、旧二进制在跑」的调查绕路。

> 🐛 **2026-08-26 20:12 用户报障闭环（第 4 批）：maxTokens 上限 / 模型配置字段缺失 / 设置排版混乱 / 账号同步假登录（@75997e9）**：
> - **maxTokens 上限太低（实锤）**：原滑块 256–8192（step 256），无法满足 256K/1M 长上下文模型 → 直输 + 预设按钮（8K/128K/256K/1M），范围 128–1,048,576 保存时校验（非整数/越界 → 红字提示且该项不写入，其余字段照常保存）；**连带实锤「最大 Token 数」此前从未下发 wire**（AgentLoop 构造 LLMRequest 漏传 maxTokens/temperature 同坑未碰）→ LLMRequest 补参 + AgentLoop 跨轮 setTurnContext 下发（不重建循环、wire 历史不丢）。
> - **提供商/模型配置太简陋（实锤）**：原仅 API Key + 本地服务地址（仅 local 显示）→ 「API 地址」行全提供商可用（留空=官方默认，占位显示默认值；生效规则：local→本地服务地址，其他→覆盖值优先）；「思考等级」off/low/medium/high 新增并真实下发 `reasoning_effort`（官方文档查证：DeepSeek chat API `reasoning_effort` low/high/max·medium 映射 high / Ollama OpenAI 兼容层 high/medium/low/max/none / OpenAI o1/o3/o4/gpt-5 系受理——非推理模型下发会 400，适配器按模型名门控静默剥离 + UI 同款提示 / Anthropic 独立 thinking 机制不接入并 UI 标注）；连接测试与真实调用统一走「覆盖值优先」生效地址（此前测试走官方默认地址，覆盖配置测了个寂寞）。
> - **设置「偏好」排版文字混乱（实锤，截图 c32b3b0d）**：「主题插件 主题插件 [⌄]」「正文字号 正文字号:15pt —slider— 15pt」= 控件自绘 label（menu Picker/Slider label 闭包）与显式 Text 叠加 → 三控件 `.labelsHidden()`（主题 segmented 一并处理）。
> - **账号与同步「假的」（实锤，截图 8ceb6c6b）**：点「使用 Apple 登录」→ 红字 AS AuthorizationError **error 1000**（ad-hoc 签名无 `com.apple.developer.applesignin` entitlement——CI entitlements 文件注释自证「不含 team 级能力」；错误码官方未公开，Apple Developer Forums 社区共识指向 entitlement/签名配置缺失，定性标注待 Apple 官方口径）→ **重新评估结论（需求可行，代码侧已解耦）**：iCloud 同步走 NSUbiquitousKeyValueStore + iCloud Documents 容器 = **系统级 Mac Apple ID 登录** + 容器 entitlement，**不需要** SSO 按钮；SSO 是应用层身份（可选叠加，需付费 Developer Team）。修复：`retryICloud`/`restore` 去掉 SSO 凭证硬前置（容器探测路径独立），「启用 iCloud 跨设备同步」按钮恒走探测；SSO 按钮保留但诚实标注「需付费 Team + capability，当前 ad-hoc 不可用」；error 1000 映射友好文案（不再裸抛英文系统错误）。
> - **门禁**：swift build 0 警告 + swiftlint --strict 0 违规（247 文件）+ swiftformat 0/235 + SPM 全量 **805/805（174 suites）全绿 @75997e9**（Swift Testing 口径 796 基线 + 10 新 − 1 改写 = 净 +9：LLMConfig 解码/钳制/生效地址/往返 5 + 画像门控 3 + Account 解耦 2（无 SSO 探测启用/无容器降级；原「请先登录」断言按新语义改写）；XCTest 另 +6：reasoning_effort wire 门控，含 OpenAI 模型名剥离/Anthropic 恒不下发/流式携带）。
> - **⚠️ 实机验证待办（bundle 同步后）**：偏好页排版 / 模型参数页新字段 / 账号与同步页新文案 三处截图核验（见 QUALITY_REPORT 08-26 20:12 条目）。

## 一、基线
| 项 | 操作 | 预期 |
|---|---|---|
| 最低 macOS Tahoe | 直接运行 App（部署目标 26.0，双清单统一 `com.deepseek.harness`） | 正常启动，无兼容提示 |

## 二、Apple SSO + iCloud 工作区漫游
| 项 | 操作 | 预期 |
|---|---|---|
| 原生登录 | 设置 →「账号与同步」→ Sign in with Apple | AuthenticationServices 原生弹窗（非网页）；无描述文件时显示「需配置 entitlement/描述文件」+ 重新申请入口（优雅降级，非缺陷） |
| 双模式隔离 | 本地模式正常使用后（若有 Team）切 iCloud 再切回 | 两套根严格隔离，数据互不污染、不自动迁移（WorkspaceRouter 双根） |
| iCloud 存储分工 | （有 Team 时）iCloud 模式新建会话 / 触发 RAG 入库 / 导入插件 | Agent 产出→容器 agents/<sessionID>；RAG 索引→容器 rag/index.json；插件元数据→容器 plugins-meta/installed.json |
| 会话工作区（P0.1.5 消费端） | 新建会话 → 对话中让 Agent 用 write_file 写**相对路径**文件（如「把内容 ws-check 写入 check.txt」）→ 检查文件系统 | 文件落 `agents/<会话ID>/check.txt`（本地模式在本地根；iCloud 模式在容器内）；read_file/list_files 相对路径同目录可读；exec `pwd` = 会话工作区；`../` 越界相对路径被沙箱拒绝（outside_sandbox） |
| 离线优先 | iCloud 模式断网操作 | 完整可用，本地优先落盘 |
| 冲突 UI | （有 Team 时）双设备改同一元数据 | 冲突挂起 + 设置页裁决卡（本地/云端双栏 + 保留本地/保留云端） |
| 权限降级 | 拒绝 iCloud 权限 | 自动降级本地模式 + 设置页显示原因 +「重新申请 iCloud 权限」按钮 |
| MCP 二进制不同步 | （有 Team 时）iCloud 模式导入 MCP 服务器后在第二设备查看 | 第二设备仅恢复元数据；二进制缺失 → 插件页橙色「待重新导入」横幅 |

## 三、侧边栏【项目】模块
| 项 | 操作 | 预期 |
|---|---|---|
| 项目 CRUD | 新建（多个）/ 重命名 / 删除 | 无上限；删除弹二选一（删除全部内部会话 / 释放至全局） |
| 展开/收起 | 点击项目分组头 | 折叠/展开，状态持久化（重启保持） |
| 会话拖拽 | 全局会话拖入项目 / 项目内拖出 / A→B 迁移 | **拖拽悬停时目标位置高亮**（accent 0.14 背景）；放置后归属立即变更 + DB 持久化 |
| 会话重命名 | 对话页右上 ⋯ 菜单 →「重命名对话…」 | 弹窗确认后侧边栏名称立即更新；纯空白名被拦截（toast）；重启后保持（同入口含导出 Markdown/清空/删除，均带确认） |
| 归档 | 项目/会话归档 | 主侧边栏消失；归档管理入口可查看、取消归档；取消归档优先回原项目，原项目已删回落全局 |
| 搜索 | 侧边栏顶部搜索框 | 全局搜会话；限定项目内搜索；点击结果直接跳转会话 |
| iCloud 同步 | （有 Team 时）A 设备建项目 → B 设备查看 | 项目/归属/归档经 KVS 同步（按字段合并，无冲突挂起） |

## 四、侧边栏导航（零假 UI）
| 项 | 操作 | 预期 |
|---|---|---|
| 新对话 | 点击 | 创建全新会话实例 |
| 对话 | 点击 | 加载真实会话列表（GRDB）；空态/失败态有真实反馈 |
| 多 Agent | 点击 | 子母 Agent 实例管理（创建/销毁子 Agent） |
| 插件 | 点击 | 真实 MCP 插件列表（内置+导入）；运行/未运行状态真实 |
| 技能 | 点击 | 真实 Skill 库（内置+用户目录）；目录被文件占用 → failed 横幅 + 重试（内置技能保留） |
| 工具 | 点击 | 真实注册表工具列表，**顺序稳定**（分类序：文件→终端→MCP→网络→代理→技能→通用，组内按名）；可面板执行 + 结果回显 |

## 五、MCP 插件闭环
| 项 | 操作 | 预期 |
|---|---|---|
| 导入-启用 | 导入本地 MCP 服务器 → 启用 | 工具自动注册进工具页；同名导入=更新（id 不变） |
| 全链路 | 对话中让 Agent 调用已导入插件的工具 | Agent 主循环真实调用 → **对话内出现可折叠工具行（入参/输出）** + 助手回复引用结果 |
| 运行日志/重启/卸载 | 插件详情页 | stderr 等宽回显；故障服务器可重启；卸载后工具即时移除 |
| 权限门禁 | 导入 medium/high 权限服务器 | 待裁决横幅，显式授予/拒绝 |
| 依赖缺失 | 导入依赖 terminal 的演示插件 terminal-plus | 缺依赖红提示 + 安装禁用；装齐后满足度实时变绿 |
| 主题插件 | 导入/安装 MCP 主题服务器 | 设置主题 Picker 出现新主题；切换即时生效；**卸载在用主题 → 自动回落系统基准 + toast** |
| 社区主题包（P0.4.3） | 插件页「导入主题包…」选择 `demos/community-theme-demo/spec.json`（或其父目录） | 导入成功 → 主题出现在设置列表（「Tahoe Teal（社区样例）」）→ 切换即时生效（青绿强调色 + 深绿气泡）→ 插件停用后主题目录删除 + 回落 |
| iCloud 元数据 | （有 Team 时）iCloud 模式导入插件/主题包 | 元数据入容器 installed.json；第二设备自动对账恢复（二进制缺失→待重导横幅） |

## 六、对话主界面
| 项 | 操作 | 预期 |
|---|---|---|
| 流式输出 | 发送消息（配置可用模型后） | Harness Agent 主循环流式输出 |
| 停止生成（P2 ①） | 生成中点「停止」 | 即时停止：在途模型请求被**联动中断**（不再后台跑完浪费配额）；无错误消息残留、无半成品回答入会话；再发消息正常继续（wire 历史不被丢弃响应污染） |
| 工具回显 | 触发工具调用 | 对话内每调用一条可折叠 .tool 行（ToolTraceRow） |
| 快捷提示 | 点击 chips | **填充输入框**（可编辑）+ 聚焦，非直接发送 |
| 模型下拉 | composer 右下角模型名 | 提供商→模型两级下拉，切换即时生效 |
| 加号菜单 | 输入框 + | 文件附件 + 插件工具入口（按 category 分组，选中插入 @toolName） |

## 七、质量基线（已实测，供核对）
- **当前基线（2026-08-26 轮 18 P2 修复，四门禁全绿 @0991eab）**：pr 门禁 SPM 790/790（Swift Testing 172 suites，0 违规，/tmp/ci_pr_agent18.log）+ xcode 7-bundle swift-testing 353 + XCTest 131（per-bundle 口径，/tmp/ci_xcode_agent18.log）+ main 门禁（Release + 全量 + 覆盖率，干净口径：核心 14 包 98.85%（7035/7117）/ 18 包全量 96.35%（9600/9964）/ Agent 100%，/tmp/ci_main_agent18.log）+ leaks 门禁（**0 leaks**，/tmp/ci_leaks_agent18.log）+ xcode 门禁（**TEST SUCCEEDED** 7 bundle，/tmp/ci_xcode_agent18.log）；前轮基线：四门禁 @c49c6e6（轮 17）/ 968/968（轮 16 /tmp/ci_pr_agent16.log）
- 本地镜像备份：`/Users/liguangming/code/swift-harness-backup.git`（每次提交后 mirror 同步）
