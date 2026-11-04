import Foundation
import Testing
@testable import GravitySDK

/// Uses real preferences, but holds each captured first read until the other
/// readers arrive. A bounded wait also lets a correctly serialized reader finish.
private final class DeviceIdDefaults: UserDefaults {
    private let condition = NSCondition()
    private var reads = 0
    private var gateOpen = false
    private(set) var deviceWrites = 0
    private(set) var synchronizations = 0
    var concurrentReaders = 0

    private func holdRead() {
        condition.lock()
        defer { condition.unlock() }
        guard concurrentReaders > 0, !gateOpen else { return }
        reads += 1
        if reads == concurrentReaders {
            gateOpen = true
            condition.broadcast()
        }
        let deadline = Date(timeIntervalSinceNow: 0.5)
        while !gateOpen {
            if !condition.wait(until: deadline) {
                gateOpen = true
                condition.broadcast()
            }
        }
    }

    override func object(forKey defaultName: String) -> Any? {
        let value = super.object(forKey: defaultName)
        if defaultName == "gravity_device_id" { holdRead() }
        return value
    }

    override func string(forKey defaultName: String) -> String? {
        let value = super.string(forKey: defaultName)
        if defaultName == "gravity_device_id" { holdRead() }
        return value
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        condition.lock()
        if defaultName == "gravity_device_id" { deviceWrites += 1 }
        condition.unlock()
        super.set(value, forKey: defaultName)
    }

    override func synchronize() -> Bool {
        condition.lock()
        synchronizations += 1
        condition.unlock()
        return super.synchronize()
    }
}

private final class DeviceIdResults {
    private let lock = NSLock()
    private var values: [String] = []

    func append(_ value: String?) {
        lock.lock()
        defer { lock.unlock() }
        values.append(value ?? "<missing>")
    }

    var ids: [String] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

extension SDKSingletonTests {
    struct DeviceIdConcurrencyTests {
        @Test @MainActor func concurrentFirstRequestsCreateOneDeviceId() throws {
            try checkConcurrentRequests(initialValue: nil)
        }

        @Test @MainActor func concurrentRequestsReplaceNumericDeviceIdOnce() throws {
            try checkConcurrentRequests(initialValue: 42)
        }

        @MainActor private func checkConcurrentRequests(initialValue: Any?) throws {
            let name = "GravitySDK.device-id-test.\(UUID())"
            let defaults = try #require(DeviceIdDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            // Seed through a separate instance so the write count covers SDK work only.
            let seed = try #require(UserDefaults(suiteName: name))
            seed.set(initialValue, forKey: "gravity_device_id")
            seed.set("preserved", forKey: "unrelated")
            let deviceUtils = DeviceUtils(prefs: Prefs(userDefaults: defaults))
            _ = GravitySDK.instance
            let count = 16
            defaults.concurrentReaders = count
            let results = DeviceIdResults()
            let ready = DispatchGroup()
            let finished = DispatchGroup()
            let start = DispatchSemaphore(value: 0)
            for _ in 0..<count {
                ready.enter()
                finished.enter()
                Thread.detachNewThread {
                    ready.leave()
                    start.wait()
                    results.append(deviceUtils.getDevice().id)
                    finished.leave()
                }
            }
            #expect(ready.wait(timeout: .now() + 5) == .success)
            for _ in 0..<count { start.signal() }
            let completion = finished.wait(timeout: .now() + 10)
            #expect(completion == .success)
            guard completion == .success else { return }
            let ids = results.ids
            #expect(ids.count == count)
            #expect(Set(ids).count == 1, "Concurrent requests must use the same device ID")
            let id = try #require(ids.first)
            #expect(UUID(uuidString: id) != nil)
            #expect(seed.string(forKey: "gravity_device_id") == id)
            #expect(defaults.deviceWrites == 1, "Only the first request may write the device ID")
            #expect(defaults.synchronizations == 0)
            #expect(seed.string(forKey: "unrelated") == "preserved")
        }

        @Test @MainActor func nonStringDeviceIdsAreReplaced() throws {
            let name = "GravitySDK.device-id-test.\(UUID())"
            let defaults = try #require(DeviceIdDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let seed = try #require(UserDefaults(suiteName: name))
            let deviceUtils = DeviceUtils(prefs: Prefs(userDefaults: defaults))
            for value: Any in [42, true, ["invalid"], ["invalid": "value"], Data([1, 2])] {
                seed.set(value, forKey: "gravity_device_id")
                let writes = defaults.deviceWrites
                let id = try #require(deviceUtils.getDevice().id)
                #expect(UUID(uuidString: id) != nil)
                #expect(seed.object(forKey: "gravity_device_id") as? String == id)
                #expect(defaults.deviceWrites == writes + 1)
            }
        }

        @Test @MainActor func storedStringIsReusedWithoutWritingOrCaching() throws {
            let name = "GravitySDK.device-id-test.\(UUID())"
            let defaults = try #require(DeviceIdDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let seed = try #require(UserDefaults(suiteName: name))
            let deviceUtils = DeviceUtils(prefs: Prefs(userDefaults: defaults))
            // Existing string IDs remain compatible; UUID validation is not added.
            for value in ["existing-device", "", "changed-device"] {
                seed.set(value, forKey: "gravity_device_id")
                #expect(deviceUtils.getDevice().id == value)
                #expect(DeviceUtils(prefs: Prefs(userDefaults: defaults)).getDevice().id == value)
            }
            #expect(defaults.deviceWrites == 0)
            #expect(defaults.synchronizations == 0)
        }
    }
}
