CSQLite modulemap 副本 — 来源：GRDB.swift v6.29.3 Sources/CSQLite/（字节级一致）

用途：Xcode 26 对 SPM systemLibrary target（GRDB 的 CSQLite）不会把
module.modulemap 传播到外部 project target，导致 explicit module build 下
编译 Session 等依赖 GRDB 的 target 时报
"unable to resolve module dependency: 'CSQLite'"。
project.yml 顶层 OTHER_SWIFT_FLAGS 通过 -Xcc -fmodule-map-file 显式注入本目录。

⚠️ 升级 GRDB 大版本时请检查 GRDB 仓库 CSQLite 目录是否有变更，如有则同步更新本副本。
