import Foundation

public struct ContentActionModel: Decodable {
    public let action: Action
    
    public init(action: Action) {
        self.action = action
    }
}
