import Foundation
import Testing
@testable import GravitySDK

extension SDKSingletonTests {
    struct NotificationPermissionConcurrencyTests {
        @Test @MainActor func permissionUpdatesReachRequestDevices() {
            let fixture = TemporarySDKFixture()
            let sdk = fixture.initialize()
            let deviceUtils = DeviceUtils()
            #expect(deviceUtils.getDevice().permission == .unknown)
            for status in [NotificationPermissionStatus.granted, .denied, .unknown] {
                sdk.setNotificationPermissionStatus(status: status)
                #expect(sdk.notificationPermissionStatus == status)
                #expect(deviceUtils.getDevice().permission == status)
            }
        }

        // This exercises real concurrent API writes and request-builder reads.
        // Without TSan it checks progress/values, not the absence of a data race.
        @Test @MainActor func concurrentPermissionUpdatesAndRequestReadsComplete() {
            let fixture = TemporarySDKFixture()
            // Only permission access is shared; initialization and teardown stay
            // on the main actor, outside the concurrent workload.
            nonisolated(unsafe) let sdk = fixture.initialize()
            nonisolated(unsafe) let deviceUtils = DeviceUtils()
            let ready = DispatchGroup()
            let finished = DispatchGroup()
            let start = DispatchSemaphore(value: 0)
            let count = 8
            for worker in 0..<count {
                ready.enter()
                finished.enter()
                Thread.detachNewThread {
                    defer { finished.leave() }
                    ready.leave()
                    start.wait()
                    var invalidReads = 0
                    for iteration in 0..<1_000 {
                        let status: NotificationPermissionStatus = (worker + iteration).isMultiple(of: 2) ? .granted : .denied
                        sdk.setNotificationPermissionStatus(status: status)
                        let direct = sdk.notificationPermissionStatus.rawValue
                        let device = deviceUtils.getDevice().permission?.rawValue
                        if !["granted", "denied"].contains(direct) { invalidReads += 1 }
                        if device != "granted" && device != "denied" { invalidReads += 1 }
                    }
                    #expect(invalidReads == 0)
                }
            }
            #expect(ready.wait(timeout: .now() + 5) == .success)
            for _ in 0..<count { start.signal() }
            let completion = finished.wait(timeout: .now() + 15)
            #expect(completion == .success)
            guard completion == .success else { return }
            sdk.setNotificationPermissionStatus(status: .unknown)
            #expect(deviceUtils.getDevice().permission == .unknown)
        }
    }
}
