import XCTest
@testable import Punctuator

final class SettingsTests: XCTestCase {
    func testDefaultSettingsPreserveOriginalBehavior() {
        let settings = AppSettings()
        XCTAssertEqual(settings.triggerKey, .rightShift)
        XCTAssertEqual(settings.mappings.count, 17)
        XCTAssertEqual(settings.punctuationMap["、"], "\\")
        XCTAssertNil(settings.validationError)
    }

    func testSettingsSurviveReload() throws {
        let suite = "PunctuatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        let settings = AppSettings(triggerKey: .rightOption, mappings: [
            SymbolMapping(source: "。", replacement: "..."),
            SymbolMapping(source: "！", replacement: "!")
        ])
        try store.save(settings)
        XCTAssertEqual(SettingsStore(defaults: defaults).current, settings)
    }

    func testInvalidMappingsAreRejectedWithoutChangingSavedSettings() throws {
        let suite = "PunctuatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        let original = store.current
        for mappings in [
            [SymbolMapping(source: "", replacement: ".")],
            [SymbolMapping(source: "ab", replacement: ".")],
            [SymbolMapping(source: "。", replacement: "")],
            [SymbolMapping(source: "。", replacement: "\n")],
            [SymbolMapping(source: "。", replacement: "."), SymbolMapping(source: "。", replacement: "!")]
        ] {
            XCTAssertThrowsError(try store.save(AppSettings(mappings: mappings)))
            XCTAssertEqual(store.current, original)
        }
    }

    func testCorruptSettingsFallBackToDefaults() throws {
        let suite = "PunctuatorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("invalid".utf8), forKey: "punctuator.settings.v1")
        XCTAssertEqual(SettingsStore(defaults: defaults).current, AppSettings())
    }

    func testEmptyMappingListDisablesConversions() {
        let settings = AppSettings(mappings: [])
        XCTAssertNil(settings.validationError)
        XCTAssertTrue(settings.punctuationMap.isEmpty)
    }

    func testTriggerKeysHaveDistinctHardwareCodesAndMasks() {
        XCTAssertEqual(TriggerKey.rightOption.keyCode, 61)
        XCTAssertEqual(TriggerKey.rightOption.deviceMask, UInt64(NX_DEVICERALTKEYMASK))
        XCTAssertEqual(TriggerKey.rightShift.deviceMask, UInt64(NX_DEVICERSHIFTKEYMASK))
        XCTAssertEqual(TriggerKey.rightControl.deviceMask, UInt64(NX_DEVICERCTLKEYMASK))
    }
}
