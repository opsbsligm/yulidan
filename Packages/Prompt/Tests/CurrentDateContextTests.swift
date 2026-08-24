import Foundation
@testable import Prompt
import Testing

/// P2 日期注入回归：固定日历 + 固定时区，星期判定确定性可测
struct CurrentDateContextTests {
    private func fixedCalendar() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return cal
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, cal: Calendar) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    @Test func lineFormatsDateAndWeekday() {
        let cal = fixedCalendar()
        // 2026-08-24 = 星期一；2026-08-23 = 星期日（验收现场：模型把周一答成周二，本测试锚定正确值）
        #expect(CurrentDateContext.line(for: date(2026, 8, 24, cal: cal), calendar: cal)
            == "当前时间：2026-08-24（星期一）")
        #expect(CurrentDateContext.line(for: date(2026, 8, 23, cal: cal), calendar: cal)
            == "当前时间：2026-08-23（星期日）")
    }

    @Test func injectAppendsLineToPrompt() {
        let cal = fixedCalendar()
        let out = CurrentDateContext.inject(into: "你是 Harness。", now: date(2026, 8, 24, cal: cal), calendar: cal)
        #expect(out == "你是 Harness。\n当前时间：2026-08-24（星期一）")
    }

    @Test func injectIntoEmptyPrompt() {
        let cal = fixedCalendar()
        let out = CurrentDateContext.inject(into: "", now: date(2026, 8, 24, cal: cal), calendar: cal)
        #expect(out == "当前时间：2026-08-24（星期一）")
    }

    @Test func injectIsIdempotentAcrossTurns() {
        let cal = fixedCalendar()
        let once = CurrentDateContext.inject(into: "你是 Harness。", now: date(2026, 8, 24, cal: cal), calendar: cal)
        let twice = CurrentDateContext.inject(into: once, now: date(2026, 8, 25, cal: cal), calendar: cal)
        // 跨轮重注入：旧日期行被替换，不叠加
        #expect(twice == "你是 Harness。\n当前时间：2026-08-25（星期二）")
    }

    @Test func injectPreservesMultiLinePrompt() {
        let cal = fixedCalendar()
        let out = CurrentDateContext.inject(into: "第一行\n第二行", now: date(2026, 8, 24, cal: cal), calendar: cal)
        #expect(out == "第一行\n第二行\n当前时间：2026-08-24（星期一）")
    }
}
