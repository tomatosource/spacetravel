import Cocoa
import ServiceManagement

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var tapManager: SpaceTapManager!
    private var keyCaptureWC: KeyCaptureWindowController?

    private var triggerKeyCode: CGKeyCode = 49
    private var triggerKeyName: String = "Space"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        loadTriggerKey()
        setupStatusItem()
        setupDefaultLaunchAtLogin()
        setupTapManager()
    }

    // MARK: - Trigger key persistence

    private func loadTriggerKey() {
        let saved = UserDefaults.standard.integer(forKey: "triggerKeyCode")
        if saved != 0 {
            triggerKeyCode = CGKeyCode(saved)
            triggerKeyName = UserDefaults.standard.string(forKey: "triggerKeyName")
                ?? KeyCaptureWindowController.displayName(for: triggerKeyCode)
        }
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "arrow.left.arrow.right", accessibilityDescription: "SpaceTravel")
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        // Status row — not clickable, just informational.
        let statusTitle = (tapManager?.isActive == true)
            ? "● Active"
            : "○ Waiting for Accessibility…"
        let tapStatusItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        tapStatusItem.isEnabled = false
        menu.addItem(tapStatusItem)

        menu.addItem(.separator())

        let keyItem = NSMenuItem(
            title: "Trigger Key: \(triggerKeyName)",
            action: #selector(changeTriggerKey),
            keyEquivalent: ""
        )
        keyItem.target = self
        menu.addItem(keyItem)

        menu.addItem(.separator())

        let launchItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        launchItem.target = self
        menu.addItem(launchItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit SpaceTravel", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Change trigger key

    @objc private func changeTriggerKey() {
        // Bring existing capture window to front if already open.
        if let wc = keyCaptureWC, wc.window?.isVisible == true {
            wc.window?.makeKeyAndOrderFront(nil)
            return
        }

        let wc = KeyCaptureWindowController(tapManager: tapManager)
        keyCaptureWC = wc
        wc.onKeySelected = { [weak self] code, name in
            guard let self else { return }
            self.triggerKeyCode = code
            self.triggerKeyName = name
            self.tapManager.triggerKeyCode = code
            UserDefaults.standard.set(Int(code), forKey: "triggerKeyCode")
            UserDefaults.standard.set(name, forKey: "triggerKeyName")
            self.rebuildMenu()
        }
        wc.show(currentKeyName: triggerKeyName)
    }

    // MARK: - Launch at login

    private func setupDefaultLaunchAtLogin() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "initialLaunchAtLoginSet") == nil else { return }
        do {
            try SMAppService.mainApp.register()
            defaults.set(true, forKey: "initialLaunchAtLoginSet")
        } catch {
            print("SpaceTravel: initial launch-at-login setup failed: \(error)")
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            print("SpaceTravel: toggle launch at login failed: \(error)")
        }
        rebuildMenu()
    }

    // MARK: - Tap manager

    private func setupTapManager() {
        tapManager = SpaceTapManager()
        tapManager.triggerKeyCode = triggerKeyCode
        tapManager.onLongPress = {
            AppSwitcher.switchApps()
        }
        tapManager.onActiveChanged = { [weak self] _ in
            DispatchQueue.main.async { self?.rebuildMenu() }
        }
        tapManager.start()
    }
}
