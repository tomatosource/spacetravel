import Cocoa

class SpaceTapManager {
    var onLongPress: (() -> Void)?
    var onActiveChanged: ((Bool) -> Void)?

    private(set) var isActive = false {
        didSet { if isActive != oldValue { onActiveChanged?(isActive) } }
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // MARK: - State

    // True while the trigger key is held and we haven't yet decided short vs long.
    private var isBuffering = false
    // True once the long-press threshold has fired (including during repeats).
    private var longPressDidFire = false
    // All events (including the trigger keydown itself) buffered during the hold window.
    private var eventQueue: [CGEvent] = []
    private var longPressTimer: Timer?

    var triggerKeyCode: CGKeyCode = 49
    var isSuspended = false

    private let longPressInitial: TimeInterval = 0.2
    private let longPressRepeat:  TimeInterval = 0.6

    // Stamp we write onto copies we post so the tap passes them through.
    private let syntheticMark: Int64 = 0x535400   // "ST\0"

    // MARK: - Start

    func start() { requestAccessibilityAndStart() }

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
        isActive = true
        print("SpaceTravel: event tap active.")
    }

    // MARK: - Event handling (main thread via main RunLoop)

    func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return nil
        }

        if isSuspended { return Unmanaged.passRetained(event) }

        // Pass through events we replayed.
        if event.getIntegerValueField(.eventSourceUserData) == syntheticMark {
            return Unmanaged.passRetained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        // While buffering, queue every non-trigger event so ordering is preserved
        // when we replay on short-press.
        if isBuffering && keyCode != triggerKeyCode {
            if let copy = event.copy() { eventQueue.append(copy) }
            return nil
        }

        guard keyCode == triggerKeyCode else {
            return Unmanaged.passRetained(event)
        }

        switch type {
        case .keyDown:
            let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
            if isRepeat {
                // Suppress repeats during buffering or after long press fired.
                return (isBuffering || longPressDidFire) ? nil : Unmanaged.passRetained(event)
            }

            // Fresh trigger keydown — start buffering everything.
            eventQueue = []
            if let copy = event.copy() { eventQueue.append(copy) }
            isBuffering = true
            longPressDidFire = false
            longPressTimer?.invalidate()
            longPressTimer = Timer.scheduledTimer(
                withTimeInterval: longPressInitial, repeats: false
            ) { [weak self] _ in self?.fireLongPress() }
            return nil

        case .keyUp:
            if isBuffering {
                // Short press: append the keyup and replay the whole queue in order.
                isBuffering = false
                longPressTimer?.invalidate()
                longPressTimer = nil
                if let copy = event.copy() { eventQueue.append(copy) }
                flushQueue()
            } else {
                // Long-press keyup: just clean up.
                longPressTimer?.invalidate()
                longPressTimer = nil
                longPressDidFire = false
            }
            return nil

        default:
            return Unmanaged.passRetained(event)
        }
    }

    // MARK: - Long press

    private func fireLongPress() {
        isBuffering = false
        longPressDidFire = true

        // Replay any non-trigger events that accumulated before the threshold fired
        // (user typed something else while holding the trigger).
        let spillover = eventQueue.filter {
            CGKeyCode($0.getIntegerValueField(.keyboardEventKeycode)) != triggerKeyCode
        }
        eventQueue = []
        if !spillover.isEmpty { replay(spillover) }

        onLongPress?()

        longPressTimer = Timer.scheduledTimer(
            withTimeInterval: longPressRepeat, repeats: false
        ) { [weak self] _ in self?.fireLongPress() }
    }

    // MARK: - Replay helpers

    private func flushQueue() {
        let q = eventQueue
        eventQueue = []
        replay(q)
    }

    private func replay(_ events: [CGEvent]) {
        for e in events {
            e.setIntegerValueField(.eventSourceUserData, value: syntheticMark)
            e.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Teardown

    deinit {
        longPressTimer?.invalidate()
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
    }
}

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
