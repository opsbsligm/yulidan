# P0 实机验收清单（2026-08-22 首版，当前 HEAD 446c2d7）

> 用法：逐项操作 → 对照「预期」打勾。全部通过后回复「P0 验收通过」，即解锁 P1 Liquid Glass。
> 验收环境要求：当前开发机即可（无 Apple Team 时 SSO/iCloud 走「无 entitlements 优雅降级」，属预期行为非缺陷）。
>
> ✅ **2026-08-24 周一验收环境就绪**：App 已重启（PID 98463，HARNESS_FRAME 定点内建屏，契约 v2 二进制 nm 核验），Ollama 0.32.15 + qwen3:4b 就绪（launchd 托管），UI 截图 /tmp/harness_monday.png（Composer 显示本地 qwen3:4b，项目/会话真实数据加载正常）；凌晨 03:38 环境侧外部终止（无崩溃报告，详见 QUALITY_REPORT §四 P2）已于 10:19 定点重启恢复。

> 🔄 **2026-08-24 10:54 用户实机走查启动（被动观察证据，不代替验收打勾）**：新会话首条消息「test」→ 标题自动派生 ✓；qwen3:4b 流式应答 + 事件落盘（5 事件 = 3 用户 + 2 助手，model=qwen3:4b，sessions.sqlite 只读核验）✓；新会话 cwd 正确路由 `agents/<sessionID>/`（P0.1.5 工作区路由实机核销，DB 证据）✓；生成中指示 + 停止按钮实时 ✓。⚠️ 模型对「今天星期几」答「今天是星期二」（今日实为周一 08-24）——本地 4B 模型自身事实幻觉，非 App 链路缺陷（流式/落盘/路由均正确；追求准确性请换更大模型或远程服务商）。

> 🔄 **2026-08-24 11:39 追加实机证据（4K 屏截图 /tmp/4k_check.png）**：会话「test」中模型自主调用 MCP 工具 `mcp_local_current_time {}` → **对话内出现可折叠工具行 + 绿色成功标记**（§五 全链路 + §六 工具回显示机核销）；随后回答「今天是星期二」仍误（工具已返回正确时间，4B 模型自行推导星期出错，P2 日期注入改进项继续有效）。

> ✅ **前置条件已解决（2026-08-22）**：对话类验收项（§二会话工作区 / §五全链路 / §六流式·停止生成·工具回显）所需 LLM 已就绪——Ollama 0.32.15（brew formula，launchd 托管 `brew services list | grep ollama`）已装并 `pull qwen3:4b`（2.5GB，Metal/M5，端点 `http://localhost:11434/v1` 实测可用）；App 配置已切 **local provider + qwen3:4b**（原配置 openai/o4-mini 无 key 不可用，已备份 /tmp/harness_llmconfig_old_readable.json，验收后可随时还原）；工具调用 e2e 实测：OpenAI 兼容请求正确返回 `write_file` tool_calls（与 App wire 格式一致，max_tokens 4096 足够含思考输出）；**DSHCLI 全链路 e2e 实跑（2026-08-22，`dsh run` + local/qwen3:4b）**：真实 LLM 流式 → Agent 主循环 2 次工具调用（write_file→read_file）→ 文件落盘 `ws-check` 8 字节核验一致 → 最终回复正确；MCP 测试服务器（/usr/bin/true×3）优雅降级不中断；记忆蒸馏落盘（无记忆价值任务正确判空）、技能进化观测在阈值下正确未误触发；**2026-08-23 周末无人值守复测**：`dsh run` 复跑（local/qwen3:4b）2 次工具调用（write_file→read_file）→ `weekend-check.txt` 10 字节（md5 dfcec55e…）落盘一致、MCP 测试服务器降级行为一致、最终回复正确（日志 /tmp/dsh_e2e_weekend.log）。若服务停止：`brew services restart ollama`。不依赖 LLM 的项（§三 全部 / §四 导航 / 会话重命名）仍可先行验收。

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
- **当前基线（2026-08-24 P2 日期注入轮，四门禁复跑全绿 @4a28a5d）**：pr 门禁 658/658（138 suites，/tmp/ci_pr_cli_date.log）+ main 门禁（Release + 全量 658/658 + 覆盖率：14 核心包 94.06% 均 ≥90% / 18 包全量 92.56% / MemoryEngine 95.17%，/tmp/ci_main_cli_date.log）+ leaks 门禁（MemProbe 500 → **0 leaks**，/tmp/ci_leaks_cli_date.log）+ xcode 门禁（**TEST SUCCEEDED**，/tmp/ci_xcode_cli_date.log）；编译 0 警告 / SwiftLint 0 违规 / SwiftFormat 0 改动；覆盖详见 QUALITY_REPORT §三/§四；前轮基线：653/653（契约 v2 轮 /tmp/ci_pr_memv2.log，2026-08-23 周末复跑 /tmp/ci_pr_weekend.log）/ 649/649（watchdog 修复轮）/ 645/645（P2 ① 联动取消轮）
- 本地镜像备份：`/Users/liguangming/code/swift-harness-backup.git`（每次提交后 mirror 同步）
