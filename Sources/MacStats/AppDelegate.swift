import AppKit
import SwiftUI

/// Owns the menu bar item.
///
/// It uses AppKit instead of SwiftUI's MenuBarExtra for two reasons:
/// - A fixed-width title. A title that changes width makes macOS animate and lay out
///   the menu bar on every update, which costs more CPU than reading the sensors.
/// - The panel view exists only while the popover is open, so it does no work when closed.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let model = StatsModel()
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon, also when the binary runs outside the .app bundle.
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: titleWidth(StatsModel.widestMenuBarTitle))
        item.button?.font = font
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        statusItem = item

        popover.behavior = .transient
        popover.delegate = self

        updateTitle()
        model.onUpdate = { [weak self] in self?.updateTitle() }
    }

    /// Each title change makes macOS redraw the menu bar item, which is the largest CPU cost
    /// of this app. So skip the update when the text is the same.
    private func updateTitle() {
        guard let button = statusItem?.button else { return }
        let title = model.menuBarTitle
        if button.title != title {
            button.title = title
        }
    }

    private func titleWidth(_ title: String) -> CGFloat {
        let width = (title as NSString).size(withAttributes: [.font: font]).width
        return ceil(width) + 12
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        let controller = NSHostingController(rootView: StatsPanel(model: model))
        controller.sizingOptions = .preferredContentSize
        popover.contentViewController = controller
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidClose(_ notification: Notification) {
        // Drop the SwiftUI view so it stops updating while the popover is closed.
        popover.contentViewController = nil
    }
}
