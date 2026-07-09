import Cocoa
import SwiftUI

final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var hostingController: NSHostingController<AnyView>!
    private let appState = AppState()

    private var escMonitor: Any?
    private var outsideClickMonitor: Any?

    override init() {
        super.init()
        setupStatusItem()
        setupPanel()
        setupEscMonitor()
        setupOutsideClickMonitor()
    }

    deinit {
        if let m = escMonitor { NSEvent.removeMonitor(m) }
        if let m = outsideClickMonitor { NSEvent.removeMonitor(m) }
        hostingController.removeObserver(self, forKeyPath: "preferredContentSize")
    }

    // MARK: - Setup

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let button = statusItem.button
        button?.image = NSImage(systemSymbolName: "rectangle.compress.vertical", accessibilityDescription: "Smoosh")
        button?.action = #selector(togglePanel)
        button?.target = self

        let overlay = DragOverlayView(frame: button?.bounds ?? .zero)
        overlay.autoresizingMask = [.width, .height]
        overlay.onDragEntered = { [weak self] in
            guard let self, !panel.isVisible else { return }
            openPanel(activateApp: false)
        }
        button?.addSubview(overlay)
    }

    private func setupPanel() {
        hostingController = NSHostingController(rootView: AnyView(
            ContentView()
                .environment(appState)
                .environment(Preferences.shared)
        ))
        hostingController.sizingOptions = [.preferredContentSize]

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        panel.contentViewController = hostingController
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true

        hostingController.addObserver(self, forKeyPath: "preferredContentSize", options: [.new], context: nil)
    }

    private func setupEscMonitor() {
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, panel.isVisible, event.keyCode == 53 else { return event }
            closePanel()
            return nil
        }
    }

    private func setupOutsideClickMonitor() {
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, panel.isVisible else { return }

            let clickLocation = event.locationInWindow

            if let button = statusItem.button, let buttonWindow = button.window {
                let buttonFrame = buttonWindow.convertToScreen(button.frame)
                if buttonFrame.contains(clickLocation) { return }
            }

            if !panel.frame.contains(clickLocation) {
                closePanel()
            }
        }
    }

    // MARK: - Panel

    @objc private func togglePanel() {
        if panel.isVisible {
            closePanel()
        } else {
            openPanel(activateApp: true)
        }
    }

    private func openPanel(activateApp: Bool) {
        guard let button = statusItem.button, let screen = button.window?.screen else { return }

        let idealSize = hostingController.preferredContentSize
        let panelSize = clampPanelSize(idealSize)

        let iconFrame = button.window?.convertToScreen(button.frame) ?? .zero
        var origin = CGPoint(
            x: iconFrame.midX - panelSize.width / 2,
            y: iconFrame.minY - panelSize.height - 6
        )
        let screenRect = screen.frame
        origin.x = max(screenRect.minX, min(origin.x, screenRect.maxX - panelSize.width))
        origin.y = max(screenRect.minY, min(origin.y, screenRect.maxY - panelSize.height))

        let fullFrame = NSRect(origin: origin, size: panelSize)

        let smallHeight = panelSize.height * 0.55
        let smallWidth = panelSize.width * 0.85
        let smallFrame = NSRect(
            x: fullFrame.midX - smallWidth / 2,
            y: fullFrame.maxY - smallHeight,
            width: smallWidth,
            height: smallHeight
        )

        panel.setFrame(smallFrame, display: false)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(fullFrame, display: true)
            panel.animator().alphaValue = 1
        }

        if activateApp {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func closePanel() {
        guard panel.isVisible else { return }
        let currentFrame = panel.frame
        let smallHeight = currentFrame.height * 0.55
        let smallWidth = currentFrame.width * 0.85
        let smallFrame = NSRect(
            x: currentFrame.midX - smallWidth / 2,
            y: currentFrame.maxY - smallHeight,
            width: smallWidth,
            height: smallHeight
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(smallFrame, display: true)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self else { return }
            panel.orderOut(nil)
            panel.alphaValue = 1
            panel.setFrame(currentFrame, display: false)
        }
    }

    // MARK: - Sizing

    private func clampPanelSize(_ size: NSSize) -> NSSize {
        let minHeight: CGFloat = 250
        let maxHeight: CGFloat = 500
        return NSSize(width: 300, height: min(max(size.height, minHeight), maxHeight))
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "preferredContentSize", let newSize = change?[.newKey] as? NSSize {
            let clamped = clampPanelSize(newSize)
            panel.contentMinSize = clamped
            panel.contentMaxSize = clamped

            var frame = panel.frame
            let oldHeight = frame.height
            frame.size = clamped
            frame.origin.y += oldHeight - clamped.height
            panel.setFrame(frame, display: true, animate: true)
        }
    }
}
