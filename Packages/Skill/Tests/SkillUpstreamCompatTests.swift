import Foundation
@testable import Skill
import XCTest

/// G4「拿来即用」技能形态实测（opt-in）：DSH 上游仓库 `.agents/skills/*/SKILL.md`
/// 真实技能包必须能被我方 `SkillStore.parse` 装载——「社区技能文件夹拿来放进目录即用」的
/// 代码级证明（与 MCP stdio 矩阵互补：那是工具插件，这是指令插件）。
///
/// 上游证据基线：/Users/liguangming/code/deepseek-harness @47f9438（铁律 7；实测 11 样本）。
/// 上游装载语义参照 packages/skill/skill-filesystem（YAML frontmatter，name/description）。
/// 静默合规：纯文件读 + 纯函数解析，零前台；opt-in（`HARNESS_G4_UPSTREAM=1`）保持门禁
/// 确定性——默认 skip，上游目录缺失时同样 skip 非失败。
final class SkillUpstreamCompatTests: XCTestCase {
    func testUpstreamCommunitySkillsParseViaOurStore() throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["HARNESS_G4_UPSTREAM"] == "1",
                          "opt-in：export HARNESS_G4_UPSTREAM=1（需本机上游检出，见 CENSUS 技能形态节）")
        let upstream = env["HARNESS_G4_DSH_UPSTREAM_DIR"] ?? "/Users/liguangming/code/deepseek-harness"
        let skillsRoot = (upstream as NSString).appendingPathComponent(".agents/skills")
        let fm = FileManager.default
        guard fm.fileExists(atPath: skillsRoot) else {
            throw XCTSkip("上游仓库不在此机：\(skillsRoot)")
        }
        let dirs = try fm.contentsOfDirectory(atPath: skillsRoot).filter {
            fm.fileExists(atPath: (skillsRoot as NSString).appendingPathComponent("\($0)/SKILL.md"))
        }
        XCTAssertGreaterThanOrEqual(dirs.count, 10, "上游技能样本应 ≥10（@47f9438 实测 11），实得 \(dirs.count)")

        var parsed = 0
        for dir in dirs {
            let path = (skillsRoot as NSString).appendingPathComponent("\(dir)/SKILL.md")
            let text = try String(contentsOfFile: path, encoding: .utf8)
            guard let skill = SkillStore.parse(text, source: path) else {
                XCTFail("上游技能解析失败（frontmatter 不兼容）：\(dir)")
                continue
            }
            parsed += 1
            XCTAssertEqual(skill.name, dir, "上游约定 name == 目录名：\(dir)")
            XCTAssertFalse(skill.description.isEmpty, "上游技能 description 不应为空：\(dir)")
            XCTAssertFalse(skill.instructions.isEmpty, "上游技能正文不应为空：\(dir)")
        }
        XCTAssertEqual(parsed, dirs.count, "全部上游技能必须解析成功（拿来即用无改写）")
    }

    /// 边界登记用例：YAML folded scalar（description: >）我方单行解析的真实行为。
    /// 上游 @47f9438 实测 0 例 folded——本用例固化「当前社区面不受影响」的证据边界，
    /// 并如实记录 folded 的降级行为（description 取标量符后内容，非崩溃）。
    func testFoldedScalarBehaviorIsGraceful() {
        let folded = """
        ---
        name: folded-sample
        description: >
          多行折叠描述第一行
          第二行
        ---
        正文
        """
        let skill = SkillStore.parse(folded, source: "test")
        XCTAssertNotNil(skill, "folded 不得导致解析失败（name 存在即应装载）")
        XCTAssertEqual(skill?.name, "folded-sample")
        XCTAssertEqual(skill?.instructions, "正文")
        // 如实登记：folded 首行语义下 description 为 ">"（或空），不苛求 YAML 完整语义
        XCTAssertNotNil(skill?.description)
    }
}
