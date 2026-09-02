# R1 走测工具链（验收流程资产，v4.7）
- `r1loop2.sh`：解锁等待循环（历史载体，v4.7 起退役，见下「锁屏预案」）
- `r1walk4.sh`：R1 §10.3 收尾走测 v4.7——**#6 主题闭环改「先导后切」**（themes 目录空→旧 6a「深海蓝」前提不成立已废弃；统一走社区包 Tahoe Teal：导入→设置取证→切换/还原实渲染→自动卸载还原）；解锁后 `caffeinate -disu -w $$` 走测窗口临时防自动锁中断（不改系统设置，退出即释放）；`.done_v43` 防重跑守卫（FORCE=1 可越）。
- `ax.swift/ev.swift/wl.swift/evtype.swift`：AX 驱动与事件工具源码（ax 支持 top|bottom|last 选择器：同名消歧/modal alert 树尾定位）
- `lockprobe2.swift`：锁屏探针（CGSessionCopyCurrentDictionary，ScreenIsLocked -1=已解锁）
- **锁屏预案（v4.7 口径）**：实测 launchd plist 上下文 TCC 零权（screencapture 空/AX 不送达），而 Agent exec 会话全权但不可持久 → 触发载体从「launchd r1loop 守解锁」改为 **heartbeat 自动化轮询**（解锁+App 存活+无 .done_v43 三条件满足即在 exec 全权会话跑 `SKIP_N=1 SKIP_45=1 zsh r1walk4.sh 30`），走测窗口 caffeinate 防自动锁。r1loop plist 退役防双跑打架。
- 二进制策略修正（v4.7）：`bin/` 收录编译产物（ax 源文件历史遗失仅存二进制，单份丢失风险>入库成本；ev/wl/evtype 有源可重建，入库为双保险）。运行时目录 `~/harness-wt`（重启幸存）。
- 授权与口径：全自动走测经用户第七轮授权（rt 中止、失败即停、不写用户数据、DB 副作用入册）；关闭 sheet 一律 Esc（⌘. 与 cancelAction 实测不符，补记②）。
