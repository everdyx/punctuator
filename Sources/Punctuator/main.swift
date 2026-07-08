import AppKit
import ApplicationServices
import Carbon

private let rightShiftKeyCode: CGKeyCode = 60

private let punctuationMap: [String: String] = [
    "。": ".",
    "，": ",",
    "、": "\\",
    "？": "?",
    "！": "!",
    "：": ":",
    "；": ";",
    "（": "(",
    "）": ")",
    "【": "[",
    "】": "]",
    "《": "<",
    "》": ">",
    "“": "\"",
    "”": "\"",
    "‘": "'",
    "’": "'"
]

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let eventTap = RightShiftEventTap()
    private let replacer = PunctuationReplacer()
    private var statusMenuItem: NSMenuItem!
    private var lastActionMenuItem: NSMenuItem!
    private var pathMenuItem: NSMenuItem!
    private var bundleIDMenuItem: NSMenuItem!
    private var enabledMenuItem: NSMenuItem!
    private var retryTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()
        requestPermissionsIfNeeded()

        eventTap.onTrigger = { [weak self] in
            self?.replacer.replacePunctuationBeforeCursor()
        }
        replacer.onDiagnostic = { [weak self] message in
            self?.lastActionMenuItem.title = "Last Action: \(message)"
        }
        _ = eventTap.start()
        updatePermissionStatus()
        startRetryTimer()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "P."
        statusItem.button?.toolTip = "Punctuator"

        let menu = NSMenu()

        statusMenuItem = NSMenuItem(title: "Status: Starting", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        lastActionMenuItem = NSMenuItem(title: "Last Action: None", action: nil, keyEquivalent: "")
        lastActionMenuItem.isEnabled = false
        menu.addItem(lastActionMenuItem)

        pathMenuItem = NSMenuItem(title: "Running Path: Unknown", action: nil, keyEquivalent: "")
        pathMenuItem.isEnabled = false
        menu.addItem(pathMenuItem)

        bundleIDMenuItem = NSMenuItem(title: "Bundle ID: Unknown", action: nil, keyEquivalent: "")
        bundleIDMenuItem.isEnabled = false
        menu.addItem(bundleIDMenuItem)

        menu.addItem(.separator())

        enabledMenuItem = NSMenuItem(
            title: "Enabled",
            action: #selector(toggleEnabled),
            keyEquivalent: ""
        )
        enabledMenuItem.target = self
        enabledMenuItem.state = .on
        menu.addItem(enabledMenuItem)

        let retryItem = NSMenuItem(
            title: "Retry Permissions",
            action: #selector(retryPermissions),
            keyEquivalent: ""
        )
        retryItem.target = self
        menu.addItem(retryItem)

        let accessibilityItem = NSMenuItem(
            title: "Open Accessibility",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        let inputMonitoringItem = NSMenuItem(
            title: "Open Input Monitoring",
            action: #selector(openInputMonitoringSettings),
            keyEquivalent: ""
        )
        inputMonitoringItem.target = self
        menu.addItem(inputMonitoringItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func requestPermissionsIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }
    }

    private func startRetryTimer() {
        retryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self, self.eventTap.isEnabled, !self.eventTap.isRunning else {
                self?.updatePermissionStatus()
                return
            }

            _ = self.eventTap.start()
            self.updatePermissionStatus()
        }
    }

    private func updatePermissionStatus() {
        let hasAccessibility = AXIsProcessTrusted()
        let hasInputMonitoring = CGPreflightListenEventAccess()
        let isReady = hasAccessibility && hasInputMonitoring && eventTap.isRunning

        if isReady {
            statusMenuItem.title = "Status: Ready"
        } else {
            let accessibilityStatus = hasAccessibility ? "OK" : "Missing"
            let inputMonitoringStatus = hasInputMonitoring ? "OK" : "Missing"
            let tapStatus = eventTap.isRunning ? "OK" : "Waiting"
            statusMenuItem.title = "Accessibility: \(accessibilityStatus), Input Monitoring: \(inputMonitoringStatus), Event Tap: \(tapStatus)"
        }

        pathMenuItem.title = "Running Path: \(Bundle.main.bundlePath)"
        bundleIDMenuItem.title = "Bundle ID: \(Bundle.main.bundleIdentifier ?? "Unknown")"
        statusItem.button?.title = eventTap.isEnabled ? (isReady ? "P." : "P?") : "P-"
    }

    @objc private func toggleEnabled() {
        eventTap.isEnabled.toggle()
        enabledMenuItem.state = eventTap.isEnabled ? .on : .off
        updatePermissionStatus()
    }

    @objc private func retryPermissions() {
        requestPermissionsIfNeeded()
        _ = eventTap.start()
        updatePermissionStatus()
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    @objc private func quit() {
        retryTimer?.invalidate()
        NSApp.terminate(nil)
    }
}

final class RightShiftEventTap {
    var onTrigger: (() -> Void)?
    var isEnabled = true

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var rightShiftIsDown = false
    private(set) var isRunning = false

    func start() -> Bool {
        if isRunning {
            return true
        }

        let mask = (1 << CGEventType.flagsChanged.rawValue)

        eventTap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            isRunning = false
            return false
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        isRunning = true
        return true
    }

    fileprivate func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard isEnabled else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        if type == .flagsChanged, keyCode == rightShiftKeyCode {
            if rightShiftIsDown {
                rightShiftIsDown = false
                DispatchQueue.main.async { [onTrigger] in
                    onTrigger?()
                }
            } else {
                rightShiftIsDown = true
            }
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

}

private let eventTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let tap = Unmanaged<RightShiftEventTap>.fromOpaque(userInfo).takeUnretainedValue()
    return tap.handle(proxy: proxy, type: type, event: event)
}

final class PunctuationReplacer {
    var onDiagnostic: ((String) -> Void)?

    private let pasteboard = NSPasteboard.general

    func replacePunctuationBeforeCursor() {
        let savedPasteboard = PasteboardSnapshot(pasteboard: pasteboard)

        selectPreviousCharacter()
        Thread.sleep(forTimeInterval: 0.12)

        let usedAccessibilityRead: Bool
        let accessibilityText = readSelectedTextWithAccessibility()?.nilIfEmpty
        let selectedText: String
        if let accessibilityText {
            selectedText = accessibilityText
            usedAccessibilityRead = true
        } else {
            copySelection()
            Thread.sleep(forTimeInterval: 0.18)
            selectedText = pasteboard.string(forType: .string) ?? ""
            usedAccessibilityRead = false
        }

        guard selectedText.count == 1, let replacement = punctuationMap[selectedText] else {
            onDiagnostic?("Read \(debugText(selectedText)); no mapping")
            restoreSelectionToCaret()
            savedPasteboard.restore(to: pasteboard)
            return
        }

        if replaceSelectedRangeValueWithAccessibility(replacement, originalText: selectedText) {
            let readPath = usedAccessibilityRead ? "AX" : "Copy fallback"
            onDiagnostic?("\(readPath) read; AX range replaced \(debugText(selectedText)) -> \(debugText(replacement))")
            savedPasteboard.restore(to: pasteboard)
            return
        }

        let readPath = usedAccessibilityRead ? "AX" : "Copy fallback"
        onDiagnostic?("\(readPath) read; paste fallback \(debugText(selectedText)) -> \(debugText(replacement))")
        pasteReplacement(replacement)
        Thread.sleep(forTimeInterval: 0.6)
        savedPasteboard.restore(to: pasteboard)
    }

    private func selectPreviousCharacter() {
        keyStroke(keyCode: UInt16(kVK_LeftArrow), flags: .maskShift)
    }

    private func copySelection() {
        keyStroke(keyCode: UInt16(kVK_ANSI_C), flags: .maskCommand)
    }

    private func pasteReplacement(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        Thread.sleep(forTimeInterval: 0.12)
        commandKeyStroke(keyCode: UInt16(kVK_ANSI_V), tap: .cgSessionEventTap)
    }

    private func readSelectedTextWithAccessibility() -> String? {
        guard let focusedElement = focusedAccessibilityElement() else {
            return nil
        }

        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextAttribute as CFString,
            &value
        )

        guard result == .success else {
            return nil
        }

        return value as? String
    }

    private func replaceSelectedRangeValueWithAccessibility(_ text: String, originalText: String) -> Bool {
        guard
            let focusedElement = focusedAccessibilityElement(),
            let selectedRange = selectedTextRange(in: focusedElement),
            selectedRange.length > 0,
            let currentValue = textValue(in: focusedElement)
        else {
            return false
        }

        let nsValue = currentValue as NSString
        let nsRange = NSRange(location: selectedRange.location, length: selectedRange.length)
        guard NSMaxRange(nsRange) <= nsValue.length else {
            return false
        }

        let updatedValue = nsValue.replacingCharacters(in: nsRange, with: text)
        let valueResult = AXUIElementSetAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            updatedValue as CFString
        )

        guard valueResult == .success else {
            return false
        }

        let caretLocation = selectedRange.location + (text as NSString).length
        moveCaret(in: focusedElement, to: caretLocation)

        Thread.sleep(forTimeInterval: 0.06)
        return didReplaceText(
            in: focusedElement,
            originalValue: currentValue,
            updatedValue: updatedValue,
            originalText: originalText
        )
    }

    private func didReplaceText(
        in element: AXUIElement,
        originalValue: String,
        updatedValue: String,
        originalText: String
    ) -> Bool {
        if let currentValue = textValue(in: element) {
            return currentValue == updatedValue && currentValue != originalValue
        }

        if let selectedText = readSelectedTextWithAccessibility() {
            return selectedText != originalText
        }

        return false
    }

    private func moveCaret(in element: AXUIElement, to location: CFIndex) {
        for attempt in 0..<5 {
            if attempt > 0 {
                Thread.sleep(forTimeInterval: 0.025)
            }

            var caretRange = CFRange(location: location, length: 0)
            guard let caretValue = AXValueCreate(.cfRange, &caretRange) else {
                return
            }

            let result = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                caretValue
            )

            if result == .success, selectedTextRange(in: element)?.location == location {
                return
            }
        }
    }

    private func selectedTextRange(in element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        )

        guard
            result == .success,
            let axValue = value,
            CFGetTypeID(axValue) == AXValueGetTypeID(),
            AXValueGetType(axValue as! AXValue) == .cfRange
        else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(axValue as! AXValue, .cfRange, &range) else {
            return nil
        }

        return range
    }

    private func textValue(in element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        )

        guard result == .success else {
            return nil
        }

        return value as? String
    }

    private func focusedAccessibilityElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )

        guard result == .success else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private func debugText(_ text: String) -> String {
        if text.isEmpty {
            return "<empty>"
        }

        let escaped = text
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    private func restoreSelectionToCaret() {
        keyStroke(keyCode: UInt16(kVK_RightArrow), flags: [])
    }

    private func keyStroke(keyCode: UInt16, flags: CGEventFlags) {
        guard
            let source = CGEventSource(stateID: .combinedSessionState),
            let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            return
        }

        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func commandKeyStroke(keyCode: UInt16, tap: CGEventTapLocation = .cghidEventTap) {
        guard
            let source = CGEventSource(stateID: .hidSystemState),
            let commandDown = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_Command), keyDown: true),
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false),
            let commandUp = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_Command), keyDown: false)
        else {
            return
        }

        commandDown.flags = .maskCommand
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        commandUp.flags = []

        commandDown.post(tap: tap)
        Thread.sleep(forTimeInterval: 0.015)
        keyDown.post(tap: tap)
        keyUp.post(tap: tap)
        Thread.sleep(forTimeInterval: 0.015)
        commandUp.post(tap: tap)
    }

}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(pasteboard: NSPasteboard) {
        items = pasteboard.pasteboardItems?.map { item in
            var itemData: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    itemData[type] = data
                }
            }
            return itemData
        } ?? []
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()

        let restoredItems = items.map { itemData in
            let item = NSPasteboardItem()
            for (type, data) in itemData {
                item.setData(data, forType: type)
            }
            return item
        }

        if !restoredItems.isEmpty {
            pasteboard.writeObjects(restoredItems)
        }
    }
}

@main
enum PunctuatorApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
