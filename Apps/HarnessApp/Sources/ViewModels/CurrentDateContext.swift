import Foundation

/// 系统提示词「当前日期 + 星期」动态注入（P2：本地小模型日期幻觉治理）
///
/// 背景：本地 4B 级模型无实时日期上下文时自推星期出错（2026-08-24 验收观察：
/// 问「今天星期几」答「星期二」，实为周一）。每轮系统提示词末尾注入
/// 「当前时间：YYYY-MM-DD（星期X）」，使日期类问答有确定上下文。
///
/// 设计：纯函数、`now` 参数化（可测试、无隐式 now 依赖）；
/// 注入幂等——已存在「当前时间：」行时先剥离再追加（跨轮不叠加）。
enum CurrentDateContext {
    /// 中文星期名，下标 = Calendar.component(.weekday) - 1（1=周日）
    static let weekdayNames = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]

    /// 注入行前缀（幂等剥离用）
    static let linePrefix = "当前时间："

    /// 将 `now` 格式化为「当前时间：2026-08-24（星期一）」
    static func line(for now: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        let weekday = weekdayNames[calendar.component(.weekday, from: now) - 1]
        return "\(linePrefix)\(formatter.string(from: now))（\(weekday)）"
    }

    /// 追加到系统提示词末尾（幂等：旧「当前时间：」行被替换，不叠加）
    static func inject(into systemPrompt: String, now: Date = Date(), calendar: Calendar = .current) -> String {
        let line = line(for: now, calendar: calendar)
        let stripped = systemPrompt
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.hasPrefix(linePrefix) }
            .joined(separator: "\n")
        guard !stripped.isEmpty else { return line }
        let base = stripped.hasSuffix("\n") ? stripped : stripped + "\n"
        return base + line
    }
}
