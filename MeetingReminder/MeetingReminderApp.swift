import AppKit
import SwiftUI

@MainActor
final class MeetingReminderAppDelegate: NSObject, NSApplicationDelegate {
    weak var controller: AppController?

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let item = NSMenuItem(
            title: "Show Quick Menu",
            action: #selector(showQuickMenu),
            keyEquivalent: ""
        )
        item.target = self
        menu.addItem(item)
        return menu
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showQuickMenu()
        return true
    }

    @objc private func showQuickMenu() {
        controller?.openQuickMenuWindow()
    }
}

@main
struct MeetingReminderApp: App {
    @NSApplicationDelegateAdaptor(MeetingReminderAppDelegate.self) private var appDelegate
    private let controller = AppController()

    init() {
        appDelegate.controller = controller
    }

    var body: some Scene {
        // Menu bar remains the primary surface; the Dock menu is a fallback when the menu bar is crowded.
        MenuBarExtra {
            MenuBarView()
                .environmentObject(controller)
        } label: {
            Image("menubar")
        }
        .menuBarExtraStyle(.window)
    }
}
