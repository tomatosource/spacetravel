import Cocoa

struct AppSwitcher {
    private static let slackBundleIDs: Set<String> = [
        "com.tinyspeck.slackmacgap",
        "com.slack.Slack",
    ]
    private static let itermBundleIDs: Set<String> = [
        "com.googlecode.iterm2",
    ]

    static func switchApps() {
        let workspace = NSWorkspace.shared
        let running = workspace.runningApplications

        let slackApp = running.first { slackBundleIDs.contains($0.bundleIdentifier ?? "") }
        let itermApp = running.first { itermBundleIDs.contains($0.bundleIdentifier ?? "") }

        let frontID = workspace.frontmostApplication?.bundleIdentifier ?? ""

        if slackBundleIDs.contains(frontID) {
            // Slack is focused → switch to iTerm2
            if let iterm = itermApp { activate(iterm) }
        } else if itermBundleIDs.contains(frontID) {
            // iTerm2 is focused → switch to Slack
            if let slack = slackApp { activate(slack) }
        } else {
            // Neither focused → prefer Slack, then iTerm2, else noop
            if let slack = slackApp {
                activate(slack)
            } else if let iterm = itermApp {
                activate(iterm)
            }
        }
    }

    private static func activate(_ app: NSRunningApplication) {
        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: .activateIgnoringOtherApps)
        }
    }
}
