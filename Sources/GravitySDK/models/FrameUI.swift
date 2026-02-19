import Foundation

public struct FrameUI: Decodable {
    public let container: Container
    public let close: Close?
    
    public init(
        container: Container,
        close: Close? = nil
    ) {
        self.container = container
        self.close = close
    }
}
