import Cocoa
import SwiftUI
import UserNotifications

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var settingsWindow: NSWindow?
    private let monitor = QuotaMonitor.shared
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)
        
        // Request Notification Permission
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                AppLogger.log("Notification authorization failed: \(error.localizedDescription)")
            }
        }
        
        // Setup status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        // Bind monitor update to refresh icon
        monitor.onIconUpdate = { [weak self] in
            self?.updateMenuBarIcon()
        }
        
        // Initial icon setup
        updateMenuBarIcon()
    }
    
    @objc func statusItemClicked(_ sender: AnyObject?) {
        rebuildMenu()
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Reset menu so next click triggers action again
        statusItem.menu = nil
    }
    
    private func rebuildMenu() {
        menu = NSMenu()
        menu.minimumWidth = 330
        
        // Account cards
        for account in monitor.config.accounts {
            let item = NSMenuItem()
            let hostingView = NSHostingView(rootView:
                MenuAccountRowView(
                    accountId: account.id,
                    onSelect: { [weak self] in
                        self?.monitor.selectAccount(id: account.id)
                    }
                )
                .frame(width: 306)
            )
            hostingView.frame = NSRect(x: 0, y: 0, width: 330, height: hostingView.fittingSize.height)
            item.view = hostingView
            menu.addItem(item)
        }
        
        menu.addItem(NSMenuItem.separator())
        
        // Refresh
        let refreshItem = NSMenuItem(title: "Refresh All", action: #selector(refreshAll), keyEquivalent: "r")
        refreshItem.target = self
        refreshItem.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
        menu.addItem(refreshItem)
        
        // Settings
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Settings")
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }
    
    @objc func refreshAll() {
        Task {
            await monitor.refreshAll()
        }
    }
    
    @objc func openSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let settingsView = SettingsWindowView()
            .environmentObject(monitor)
        
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "LimitBank Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 680, height: 480))
        window.minSize = NSSize(width: 580, height: 400)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        settingsWindow = window
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    private func updateMenuBarIcon() {
        let (hours, weekly) = monitor.getSelectedQuotaPercentages()
        let style = monitor.config.menuBarStyle ?? "bars"
        
        // Update Title (Percentage)
        if style == "percentage" || style == "both" {
            // Display worst-case remaining percentage
            if let pct = hours ?? weekly {
                statusItem.button?.title = String(format: "%.0f%%", pct)
            } else {
                statusItem.button?.title = "—%"
            }
        } else {
            statusItem.button?.title = ""
        }
        
        // Update Image (Bars)
        if style == "bars" || style == "both" {
            let image = IconRenderer.generateMenuBarIcon(
                hoursRemainingPercent: hours,
                weeklyRemainingPercent: weekly
            )
            statusItem.button?.image = image
        } else {
            statusItem.button?.image = nil
        }
    }
}

@main
@MainActor
struct AppEntryPoint {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
