import Cocoa

/// Intercepts Space key events via CGEventTap.
/// Short presses (< longPressDuration) are passed through transparently.
/// Long presses trigger `onLongPress` and suppress the key event.
class SpaceTapManager {
    var onLongPress: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var longPressTimer: Timer?
    private var pendingKeyDown: CGEvent?
    private var longPressDidFire = false

    // Counter of synthetic space events we posted; used to pass them through
    // without re-processing.
    private var syntheticEventsRemaining = 0

    var triggerKeyCode: CGKeyCode = 49
    var isSuspended = false
    private let longPressDuration: TimeInterval = 0.5

    func start() {
        requestAccessibilityAndStart()
    }

    // MARK: - Setup

    private func requestAccessibilityAndStart() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(opts) {
            startEventTap()
        } else {
            pollForAccessibility()
        }
    }

    private func pollForAccessibility() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            if AXIsProcessTrustedWithOptions(nil) {
                self?.startEventTap()
            } else {
                self?.pollForAccessibility()
            }
        }
    }

    private func startEventTap() {
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: spaceTapCallback,
            userInfo: selfPtr
        ) else {
            print("SpaceTravel: failed to create event tap — ensure Accessibility is granted.")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        print("SpaceTravel: event tap active.")
    }

    // MARK: - Event handling (called on main thread via main RunLoop)

    func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-arm if the system disabled our tap.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return nil
        }

        // Pass everything through while capturing a new key assignment.
        if isSuspended { return Unmanaged.passRetained(event) }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == triggerKeyCode else {
            return Unmanaged.passRetained(event)
        }

        // Pass through synthetic events we injected.
        if syntheticEventsRemaining > 0 {
            syntheticEventsRemaining -= 1
            return Unmanaged.passRetained(event)
        }

        switch type {
        case .keyDown:
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if isRepeat {
                // Suppress key-repeat during long-press window or after long press fired.
                return (longPressTimer != nil || longPressDidFire) ? nil : Unmanaged.passRetained(event)
            }

            // Fresh keydown: store and start timer.
            pendingKeyDown = event.copy()
            longPressDidFire = false
            longPressTimer?.invalidate()
            longPressTimer = Timer.scheduledTimer(withTimeInterval: longPressDuration, repeats: false) { [weak self] _ in
                self?.fireLongPress()
            }
            return nil // Consume; decision pending.

        case .keyUp:
            if !longPressDidFire, let timer = longPressTimer, timer.isValid {
                // Short press: cancel timer and replay both events.
                timer.invalidate()
                longPressTimer = nil
                let savedDown = pendingKeyDown
                pendingKeyDown = nil
                replayShortPress(keyDown: savedDown, keyUp: event)
                return nil // Consume original; we're replaying.
            } else {
                // Long press was handled; cancel any pending repeat timer.
                longPressTimer?.invalidate()
                longPressTimer = nil
                pendingKeyDown = nil
                longPressDidFire = false
                return nil
            }

        default:
            return Unmanaged.passRetained(event)
        }
    }

    // MARK: - Helpers

    private func fireLongPress() {
        longPressDidFire = true
        pendingKeyDown = nil
        onLongPress?()
        // Reschedule so the switch repeats while the key stays held.
        longPressTimer = Timer.scheduledTimer(withTimeInterval: longPressDuration, repeats: false) { [weak self] _ in
            self?.fireLongPress()
        }
    }

    private func replayShortPress(keyDown: CGEvent?, keyUp: CGEvent) {
        // Account for both events so the tap passes them through.
        syntheticEventsRemaining = (keyDown != nil ? 1 : 0) + 1
        keyDown?.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    deinit {
        longPressTimer?.invalidate()
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
    }
}

// C-compatible callback — cannot be a method or closure.
private func spaceTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passRetained(event) }
    let manager = Unmanaged<SpaceTapManager>.fromOpaque(refcon).takeUnretainedValue()
    return manager.handle(proxy: proxy, type: type, event: event)
}
