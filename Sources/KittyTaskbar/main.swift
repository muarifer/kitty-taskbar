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
        observePopoverResize()
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
            alignPopoverUnderMenuBar()
        }
    }

    /// macOS 26'da popover bazen simgenin epey altında açılıyor (issue #1). Konumu
    /// ölçüp yalnızca gözle görülür bir sapma varsa pencereyi menü çubuğunun altına çekiyoruz.
    private func alignPopoverUnderMenuBar() {
        guard popover.isShown,
              let menuBarBottom = statusItem.button?.window?.frame.minY,
              let window = popover.contentViewController?.view.window,
              let originY = PopoverLayout.correctedOriginY(
                  popoverFrame: window.frame,
                  menuBarBottom: menuBarBottom
              )
        else { return }
        var frame = window.frame
        frame.origin.y = originY
        window.setFrame(frame, display: true)
    }

    /// İçerik (kitty listesi) geldiğinde popover yeniden boyutlanıp konumlanıyor;
    /// düzeltmeyi her boyut değişiminden sonra tekrar uyguluyoruz.
    private func observePopoverResize() {
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self,
                      let window = note.object as? NSWindow,
                      window === self.popover.contentViewController?.view.window
                else { return }
                self.alignPopoverUnderMenuBar()
            }
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: L10n.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
