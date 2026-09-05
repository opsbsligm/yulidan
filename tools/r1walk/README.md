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
> **本轮实测的载体核查（证明"禁令未被绕过"，非纸面承诺）**：
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
