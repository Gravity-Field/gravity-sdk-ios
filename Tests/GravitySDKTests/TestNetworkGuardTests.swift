import XCTest
import NetworkTestGuard
final class TestNetworkGuardTests: XCTestCase {
    func testDefaultSessionCannotReachDiagnosticsOrOtherNonLocalHosts() async throws {
        // Referencing the class also ensures its object file and +load are linked into the test bundle.
        let configuration = URLSessionConfiguration.default
        guard configuration.protocolClasses?.contains(where: { $0 == GravityTestNetworkGuard.self }) == true else {
            XCTFail("Every default session must install the test network guard"); return
        }
        let before = GravityTestNetworkGuard.violations().count
        let (_, response) = try await URLSession(configuration: configuration).data(from: URL(string: "https://sdk-sentry.gravityfield.ai/error")!)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        do {
            _ = try await URLSession(configuration: configuration).data(from: URL(string: "https://must-never-connect.invalid/test")!)
            XCTFail("External hosts must be blocked")
        } catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
        XCTAssertEqual(Array(GravityTestNetworkGuard.violations().dropFirst(before)),
            ["sdk-sentry.gravityfield.ai", "must-never-connect.invalid"])
    }
}
