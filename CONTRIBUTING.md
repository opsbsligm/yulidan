# 贡献指南

## 工程结构
- `Packages/`：业务模块（每个含 Sources/ + Tests/，SPM target 在 `Package.swift` 注册）
- `Apps/`：HarnessApp（GUI）/ HarnessCore（组装层）/ DSHCLI / MemProbe
- 依赖方向：`ServiceContainer ← (Session/LLM/Tools/Agent) ← HarnessCore ← App/CLI`，禁止反向依赖

## 提交前必做（本仓库四门禁口径）
1. `swift build && swift test` 全绿（测试期望值必须实测获取，禁止凭记忆硬编码）
2. 新增/删除源文件后：`xcodegen generate`，并把重新生成的 `swift-harness.xcodeproj/project.pbxproj` 一并提交
3. GUI 改动跑一次 `tools/rebuild-app.sh`（SPM 增量构建不刷新 bundle，历史实锤两次）
4. 字符串替换脚本改动后必须 `bash -n` / build 验证（三引号/heredoc 吞尾引号是本项目已踩之坑）

## 品牌与代号
用户可见品牌 = 鱼利丹，统一走 `AppBrand.displayName` 单点；工程代号 Harness 保留在目录/模块/bundle id/数据路径，勿改。

## 测试
新增能力必须带 Swift Testing 用例；涉及外部 I/O 用 mock（参考 LLM 包 HTTP mock 模式）。
