import XCTest
@testable import Ping_Island

final class NotchTimingSettingsTests: XCTestCase {

    @MainActor
    func testNotchHoverActivationDelayDefaultsAndPersists() {
        let key = AppSettingsDefaultKeys.notchHoverActivationDelay
        let suiteName = "test-\(key)-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }

        let store = AppSettingsStore(defaults: suite, bridgeRuntimeConfigWriter: { _ in })

        XCTAssertEqual(store.notchHoverActivationDelay, 0.24)
        store.notchHoverActivationDelay = 0.6
        XCTAssertEqual(suite.double(forKey: key), 0.6)
    }

    @MainActor
    func testNotchOpenAnimationDurationDefaultsAndPersists() {
        let key = AppSettingsDefaultKeys.notchOpenAnimationDuration
        let suiteName = "test-\(key)-\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        defer { suite.removePersistentDomain(forName: suiteName) }

        let store = AppSettingsStore(defaults: suite, bridgeRuntimeConfigWriter: { _ in })

        XCTAssertEqual(store.notchOpenAnimationDuration, 0.42)
        store.notchOpenAnimationDuration = 0.6
        XCTAssertEqual(suite.double(forKey: key), 0.6)
    }
}
