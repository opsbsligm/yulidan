# 安全策略

## 本项目的安全设计
- API Key 仅存 macOS 钥匙串（Keychain），不落盘、不进 UserDefaults/代码
- `web_fetch` 工具：协议白名单 + 响应大小上限
- `exec_command` 工具：带超时保护，但**以当前用户身份执行 zsh**，具备真实系统操作能力
- 工具文件读写暂无路径白名单——按部署场景自行在 App 层约束

## 已知边界
- ad-hoc 签名未公证的 DMG 需右键→打开，请仅从本仓库 Releases 下载并核对 sha256
- 会话数据明文存于 `~/Library/Application Support/Harness/sessions.sqlite`，共享设备请自行加密

## 报告漏洞
请开 private security advisory（Security → Report a vulnerability），不要公开 issue。
