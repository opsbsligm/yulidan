import Foundation
@testable import HarnessApp
import Testing

// MARK: - UserProfile dscl 输出解析（纯函数三分支）＋展示名非空

@Suite("UserProfile JPEGPhoto 解析")
struct UserProfileTests {
    @Test func emptyAttrValueIsNil() {
        #expect(UserProfile.jpegData(fromDsclOutput: "JPEGPhoto:") == nil)
    }

    @Test func missingAttrIsNil() {
        #expect(UserProfile.jpegData(fromDsclOutput: "NFSHomeDirectory: /Users/x") == nil)
    }

    @Test func foldedBase64Decodes() {
        let img = Data([0xFF, 0xD8, 0x01])
        #expect(UserProfile.jpegData(fromDsclOutput: "JPEGPhoto:\n\t\(img.base64EncodedString())") == img)
    }

    @Test func sameLineValueDecodes() {
        let img = Data([0xFF, 0xD8, 0x01])
        #expect(UserProfile.jpegData(fromDsclOutput: "JPEGPhoto: \(img.base64EncodedString())") == img)
    }

    @Test func displayNameAndInitialNonEmpty() {
        #expect(!UserProfile.displayName.isEmpty)
        #expect(!UserProfile.initial.isEmpty)
    }
}
