import XCTest
import AppKit
@testable import Punctuator

final class TriggerTests: XCTestCase {
    func testOptionTriggersOnceOnReleaseAndLeavesOtherKeysAlone() {
        let tap = TriggerEventTap()
        tap.triggerKey = .rightOption
        var count = 0
        tap.onTrigger = { count += 1 }
        XCTAssertFalse(tap.handleModifier(keyCode: 60, flags: .maskShift))
        XCTAssertFalse(tap.handleModifier(keyCode: 58, flags: .maskAlternate))
        XCTAssertTrue(tap.handleModifier(keyCode: 61, flags: CGEventFlags(rawValue: 0x40)))
        XCTAssertEqual(count, 0)
        XCTAssertTrue(tap.handleModifier(keyCode: 61, flags: []))
        XCTAssertTrue(tap.handleModifier(keyCode: 61, flags: []))
        let drained = expectation(description: "main queue callbacks")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
        XCTAssertEqual(count, 1)
    }

    func testChangingKeyOrDisablingClearsPendingPress() {
        let tap = TriggerEventTap()
        var count = 0
        tap.onTrigger = { count += 1 }
        tap.handleModifier(keyCode: 60, flags: CGEventFlags(rawValue: 0x4))
        tap.triggerKey = .rightOption
        tap.handleModifier(keyCode: 61, flags: [])
        tap.handleModifier(keyCode: 61, flags: CGEventFlags(rawValue: 0x40))
        tap.isEnabled = false
        XCTAssertFalse(tap.handleModifier(keyCode: 61, flags: []))
        tap.isEnabled = true
        tap.handleModifier(keyCode: 61, flags: [])
        let drained = expectation(description: "main queue callbacks")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
        XCTAssertEqual(count, 0)
    }

    func testSettingsWindowPassThroughClearsHeldKey() {
        let tap = TriggerEventTap()
        tap.handleModifier(keyCode: 60, flags: CGEventFlags(rawValue: 0x4))
        tap.shouldPassThrough = { true }
        XCTAssertFalse(tap.handleModifier(keyCode: 60, flags: []))
        tap.shouldPassThrough = { false }
        var count = 0
        tap.onTrigger = { count += 1 }
        tap.handleModifier(keyCode: 60, flags: [])
        let drained = expectation(description: "main queue callbacks")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 1)
        XCTAssertEqual(count, 0)
    }

    func testLeftOptionHeldDoesNotPreventRightOptionRelease() {
        let tap = TriggerEventTap()
        tap.triggerKey = .rightOption
        let triggered = expectation(description: "right option release")
        tap.onTrigger = { triggered.fulfill() }
        tap.handleModifier(keyCode: 61, flags: CGEventFlags(rawValue: 0x40 | 0x20 | CGEventFlags.maskAlternate.rawValue))
        tap.handleModifier(keyCode: 61, flags: CGEventFlags(rawValue: 0x20 | CGEventFlags.maskAlternate.rawValue))
        wait(for: [triggered], timeout: 1)
    }
}
