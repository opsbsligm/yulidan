# R1 走测工具链（验收流程资产，v4.6）
- `r1loop2.sh`：解锁等待循环（plist `com.harness.r1loop` 托管，稳定路径 ~/harness-wt，解锁+权限自检后跑走测；Harness 未运行自动拉起；完成即证据快照冻结）
- `r1walk4.sh`：R1 §10.3 收尾走测（#3 右键[AXShowMenu(top) 兜底]/#6a 切换还原/#6b 社区包导入+自动卸载收尾/#7 noChange 拖拽悬停/#8 系统开关自动拨回双验证）
- `ax.swift/ev.swift/wl.swift/evtype.swift`：AX 驱动与事件工具源码（ax 支持 top|bottom|last 选择器：同名消歧/modal alert 树尾定位）
- 运行时目录 `~/harness-wt`（重启幸存；/tmp/wt 为旧临时位置已废弃）。二进制不入库，`swiftc -O <src> -o <bin>` 重建。
- 授权与口径：全自动走测经用户第七轮授权（rt 中止、失败即停、不写用户数据、DB 副作用入册）；关闭 sheet 一律 Esc（⌘. 与 cancelAction 实测不符，补记②）。
