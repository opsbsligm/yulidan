import Foundation

public struct SessionID: Sendable, Hashable, Codable {
    public let rawValue: UUID
    
    public init() {
        self.rawValue = UUID()
    }
    
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}
