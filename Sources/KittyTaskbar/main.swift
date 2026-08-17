import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let model = TaskbarModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(
            rootView: ContentView(model: model, close: { [weak self] in
                self?.popover.performClose(nil)
            })
        )

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "cat.fill", accessibilityDescription: "kitty")
                ?? NSImage(systemSymbolName: "terminal", accessibilityDescription: "kitty") {
                img.isTemplate = true
                button.image = img
            } else {
                button.title = "🐱"
            }
            button.action = #selector(statusItemClicked)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
            return
        }
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.refresh()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Çıkış", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        // Geçici menü ataması: performClick menüyü açar, sonrasında temizlenir ki
        // sol tık yeniden popover'ı açabilsin.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory) // Dock'ta değil, sadece menü çubuğunda
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
