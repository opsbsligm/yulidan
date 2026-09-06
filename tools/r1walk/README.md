# R1 走测工具链（验收流程资产，v4.7.3 → **归档口径 v8**）

> ## ⛔ 归档标注 2026-09-06（G3 清理项落地，优先级高于本文件其余一切内容）
> **本目录内所有「注入式」工具——`bin/ev`、`bin/evtype`、`bin/ax` 的动作用法（press/showmenu/setattr）——
> 一律「仅用户手动、当场授权」运行。任何 Agent 不得自动触发，也不得经 heartbeat／automation／
> launchd／crontab 等任何自动化载体间接触发。**（依据：v8 项目目标 §〇 C 层「永久禁止自动触发」＋铁律 8 静默验收）
>
> **本文件下方 v4.7「锁屏预案」中「heartbeat 自动化轮询…即在 exec 全权会话跑 `SKIP_N=1 SKIP_45=1 zsh r1walk4.sh 30`」
> 这一条口径已被 v8 取代并作废**——它把含 C 层注入的脚本挂在自动化载体上，与上述禁令直接冲突。
> 原文保留仅作历史沿革，**不得照做**；`r1walk4.sh` 现仅可在用户当场授权下手动单次运行。
>
> ## ⛔⛔ 2026-09-06 二次升级：从纸面标注到**机器闸门**（本节优先级仍高于本文件其余一切内容）
> 上一条标注落地后复查发现：`bin/ev`／`bin/evtype` 二进制**自身零闸门**，且 `r1walk4.sh` 用法行还写着
> 「Agent 代跑无 tty 自动继续」——纸面承诺与可执行现实相反，等于禁令可被无意绕过。现已改为不可绕过判定：
>
> | 层 | 工具 | 闸门（双条件，缺一即 `exit 78`） | 放行前缀（用户本人键入） |
> |---|---|---|---|
> | C | `bin/ev`／`bin/evtype`／`r1walk4.sh` | ① 环境变量逐字声明 ＋ ② stdin 为 TTY | `HARNESS_WALK_MANUAL=I-AM-HUMAN` |
> | B | `bin/ax` 的 `press`/`showmenu`（真身 `bin/ax.bin`） | 同上两条，独立 token 以便审计区分 B/C 层 | `HARNESS_AX_ACTION=I-APPROVED-AX-ACTION` |
> | A | `bin/axdump`、`bin/ax … dump`、`bin/wl`、`bin/lockprobe2` | **不加限**（纯只读取证，锁屏可跑） | — |
>
> 每次**放行**都向 `~/harness-wt/walk-audit.log` 追加一行（时刻＋pid/ppid＋工具＋动作），使"没被自动触发"可事后核查。
> 两档闸门都带**零动作/零注入自证子命令**（`ev guard-check`、`ax <pid> guard-check`），使闸门本身可被验证而不是只能被声明：
> 无 token 无 TTY ⇒ `GUARD_DENY`（rc 78）；有 token 有 TTY ⇒ `GUARD_WOULD_ALLOW`（rc 0，仍不执行任何注入）。
> 重建：`zsh tools/r1walk/build.sh`（`bin/ax.bin` 无源，闸门在其 wrapper 里）。
>
> **载体核查（每次改这类工具后重跑，非纸面承诺）**：`bash tools/qa/c-layer-carrier-audit.sh`（rc=0＝无任何自动化载体挂载注入式工具）。
> `~/.codex/automations/` 无任何 automation 定义（目录空）／`~/Library/LaunchAgents/*.plist`
> 无一处引用 `r1walk`/`r1loop`/`ev`/`ax`／`crontab -l` = no crontab／`launchctl list` 内 harness
> 仅 App 本体。⇒ 不存在自动化挂载 C 层的既成事实。
>
> **Agent 侧仍可用的静默取证（A 层，不在此禁令内）**：`bin/axdump`（纯只读 AX 树导出）、
> 进程内单测、测试缝注入、只读 dump。B 层（`ax` 的 press/showmenu）会改变 App 可见状态，
> 须用户当场择时同意后方可用。

- **v4.7.3（09-03 补记㉔）**：① 27 beta 文案「减弱透明度」→「降低透明度」同步；② WID 认 name=Harness 行 + WINX 以 AX pos 为权威（幻影缩略图只污染 wl）；③ **用户在线禁令：C 层注入（ev activate/key/drag + System Events）永不自动触发，仅限用户离键盘时手动运行**——静默优先：A 层 ImageRenderer/测试缝证据已在册，B 层 ax press/showmenu 无键鼠占用但可弹窗、需用户择时。
- `r1loop2.sh`：解锁等待循环（历史载体，v4.7 起退役，见下「锁屏预案」）
- `r1walk4.sh`：R1 §10.3 收尾走测 v4.7——**#6 主题闭环改「先导后切」**（themes 目录空→旧 6a「深海蓝」前提不成立已废弃；统一走社区包 Tahoe Teal：导入→设置取证→切换/还原实渲染→自动卸载还原）；解锁后 `caffeinate -disu -w $$` 走测窗口临时防自动锁中断（不改系统设置，退出即释放）；`.done_v43` 防重跑守卫（FORCE=1 可越）。**v4.7.1**：#8 拨「减弱透明度」后登记 EXIT trap 兜底还原（正常拨回 V2=0 才 `_TB_DONE=1; trap - EXIT` 双保险解除；zsh 解除语法必须 `trap -` 带空格，连写 `trap-` 实测非法）。
- `ax.swift/ev.swift/wl.swift/evtype.swift`：AX 驱动与事件工具源码（ax 支持 top|bottom|last 选择器：同名消歧/modal alert 树尾定位）
- `axdump.swift/bin/axdump`（09-03 静默轮新增，源码在仓）：**纯只读** AX 树导出（A 层取证主力）——
  默认导窗口子树（走 `kAXWindowsAttribute`，修复老 `bin/ax dump` 截断于菜单栏的缺陷·补记㉙）、
  零动作/零 setAttribute/零 TCC 弹窗（仅 `AXIsProcessTrusted()` 静默探测）、全局 4000 节点预算。
  用法 `bin/axdump <pid> [maxdepth] [--menubar]`；未受信任 exit 2、AXWindows 空 exit 3（App 隐藏时如实报空）。
  G3 走查取证 = 用户操作 + 本工具只读快照。`bin/ax` 保持原样（历史注入式走测工具，仅用户手动）。
- **锁屏预案（v4.7 口径）**：实测 launchd plist 上下文 TCC 零权（screencapture 空/AX 不送达），而 Agent exec 会话全权但不可持久 → 触发载体从「launchd r1loop 守解锁」改为 **heartbeat 自动化轮询**（解锁+App 存活+无 .done_v43 三条件满足即在 exec 全权会话跑 `SKIP_N=1 SKIP_45=1 zsh r1walk4.sh 30`），走测窗口 caffeinate 防自动锁。r1loop plist 退役防双跑打架。
- 二进制策略修正（v4.7）：`bin/` 收录编译产物（ax 源文件历史遗失仅存二进制，单份丢失风险>入库成本；ev/wl/evtype 有源可重建，入库为双保险）。运行时目录 `~/harness-wt`（重启幸存）。
- 授权与口径：全自动走测经用户第七轮授权（rt 中止、失败即停、不写用户数据、DB 副作用入册）；关闭 sheet 一律 Esc（⌘. 与 cancelAction 实测不符，补记②）。
