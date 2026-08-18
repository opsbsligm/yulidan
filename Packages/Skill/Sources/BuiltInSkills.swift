import Foundation

// MARK: - 内置技能（App 与 CLI 共享）

/// 内置技能：随版本发布的常用指令集
public enum BuiltInSkills {
    public static func makeAll() -> [Skill] {
        [gitCommit, codeReview, opsTroubleshoot]
    }

    private static let gitCommit = Skill(
        name: "git-commit",
        description: "按约定式提交（Conventional Commits）撰写 commit message",
        instructions: """
        撰写 commit message 时遵循以下约定：

        1. 标题行（≤72 字符）：`<type>(<scope>): <祈使句摘要>`
           - type 取值：feat / fix / perf / refactor / test / docs / chore / ci
           - scope 可选，用模块或包名（如 subagent、mcp、app）
        2. 正文（可选）：换行后用列表说明动机与关键改动；只写"为什么"和"改了什么"，不写流水账。
        3. 破坏性变更：在正文加 `BREAKING CHANGE:` 段，说明影响与迁移方式。
        4. 禁止：无意义标题（"更新"、"修改"）、把 diff 内容复述一遍、夹带个人待办。
        """,
        tags: ["git", "commit", "规范"],
        source: "builtin"
    )

    private static let codeReview = Skill(
        name: "code-review",
        description: "代码评审清单：正确性 / 并发 / 错误处理 / 安全 / 可读性",
        instructions: """
        评审代码时按以下顺序逐项检查，发现问题按 P0(阻断) / P1(应修) / P2(建议) 分级：

        1. 正确性：边界条件（空集合、零、负数、超长）、off-by-one、状态机闭环。
        2. 并发安全（Swift）：actor 隔离是否被绕过（nonisolated(unsafe) 必须说明理由）、
           共享可变状态、Task 取消与 continuation 是否都会恢复、weak self 防泄漏。
        3. 错误处理：catch 后是否吞掉错误、错误信息是否可定位、重试是否幂等。
        4. 安全：敏感信息（Key/Token）是否落盘或进日志、路径拼接是否可越界（沙箱）、
           外部输入是否校验。
        5. 可读性与约束：函数体 ≤60 行、圈复杂度 ≤10、命名自解释、注释解释"为什么"而非"是什么"。
        6. 测试：新增逻辑是否有对应测试；测试是否依赖真实网络/全局状态（应可注入 mock）。
        """,
        tags: ["review", "swift", "质量"],
        source: "builtin"
    )

    private static let opsTroubleshoot = Skill(
        name: "ops-troubleshoot",
        description: "运维故障排查流程：定位 → 证据 → 最小变更 → 可回退",
        instructions: """
        排查生产/运维故障时遵循以下流程，禁止凭猜测直接执行变更：

        1. 定位现象：收集报错原文、时间戳、影响范围（单节点/集群/业务），先复述现象再下结论。
        2. 收集证据：查日志（journalctl / 应用日志）、资源（top/free/df -h）、网络（ss/ip）、
           最近变更（git log、部署记录）——变更前后 24h 内的改动优先怀疑。
        3. 假设验证：一次只验证一个假设，用只读命令验证；证据不足就明说"信息不足"，不编造结论。
        4. 最小变更：给出影响面最小的操作方案，并明确【回退方案】；无回退方案不给执行命令。
        5. 高危操作（重启服务/改网络/清数据）：先列风险点、确认执行对象与环境，再执行；执行后验证恢复。
        6. 收尾：记录根因、处理过程、后续预防措施，形成简短复盘。
        """,
        tags: ["ops", "troubleshoot", "运维"],
        source: "builtin"
    )
}
