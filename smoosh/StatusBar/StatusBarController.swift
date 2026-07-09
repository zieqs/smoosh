import Cocoa
import SwiftUI

final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private var panel: NSPanel!
    private var hostingController: NSHostingController<AnyView>!
    private let appState = AppState()
    private var bubblePanels: [UUID: BubblePanel] = [:]

    private var escMonitor: Any?
    private var outsideClickMonitor: Any?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(syncBubbles),
            name: .appStateBubbleUpdate,
            object: nil
        )
        setupStatusItem()
        setupPanel()
        setupEscMonitor()
        setupOutsideClickMonitor()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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
                .environment(\.closePanel, { [weak self] in
                    self?.closePanel()
                })
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

    // MARK: - Main Panel

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
        let minHeight: CGFloat = 220
        let maxHeight: CGFloat = 400
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

    // MARK: - Bubbles

    @objc private func syncBubbles() {
        let visible = appState.visibleBubbles
        let visibleIDs = Set(visible.map { $0.id })
        let currentIDs = Set(bubblePanels.keys)

        for id in currentIDs.subtracting(visibleIDs) {
            removeBubblePanel(for: id)
        }

        for item in visible {
            if bubblePanels[item.id] == nil {
                showBubble(for: item)
            } else if let existing = bubblePanels[item.id] {
                updateBubble(existing, for: item)
            }
        }

        positionBubblePanels()
    }

    private func showBubble(for item: OptimizationItem) {
        let bubbleView = ResultBubbleView(
            item: item,
            onDismiss: { [weak self] in
                self?.appState.dismissItem(item.id)
            },
            onAggressive: { [weak self] in
                guard let self, let url = item.sourceURL else { return }
                appState.dismissItem(item.id)
                PDFOptimizationService.shared.optimize(fileAt: url, appState: appState, forceAggressive: true)
            }
        )

        let hosting = NSHostingController(rootView: AnyView(bubbleView))
        hosting.sizingOptions = [.preferredContentSize]

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        panel.contentViewController = hosting
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true

        let size = hosting.preferredContentSize
        panel.setFrame(NSRect(origin: .zero, size: size), display: false)
        panel.alphaValue = 0
        panel.orderFront(nil)

        let bp = BubblePanel(panel: panel, hosting: hosting)
        bubblePanels[item.id] = bp

        positionBubblePanels()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func updateBubble(_ bp: BubblePanel, for item: OptimizationItem) {
        let bubbleView = ResultBubbleView(
            item: item,
            onDismiss: { [weak self] in
                self?.appState.dismissItem(item.id)
            },
            onAggressive: { [weak self] in
                guard let self, let url = item.sourceURL else { return }
                appState.dismissItem(item.id)
                PDFOptimizationService.shared.optimize(fileAt: url, appState: appState, forceAggressive: true)
            }
        )
        bp.hosting.rootView = AnyView(bubbleView)
    }

    private func removeBubblePanel(for id: UUID) {
        guard let bp = bubblePanels.removeValue(forKey: id) else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            bp.panel.animator().alphaValue = 0
        } completionHandler: {
            bp.panel.orderOut(nil)
        }
    }

    private func positionBubblePanels() {
        guard let button = statusItem.button, let screen = button.window?.screen else { return }
        let iconFrame = button.window?.convertToScreen(button.frame) ?? .zero

        let sorted = bubblePanels.sorted { $0.key.uuidString < $1.key.uuidString }
        let spacing: CGFloat = 6
        let margin: CGFloat = 4

        let bottomY = iconFrame.minY - spacing - margin
        let totalHeight = sorted.reduce(0) { $0 + $1.value.panel.frame.height }
        let topY = bottomY - totalHeight - spacing * CGFloat(sorted.count - 1)

        let screenRect = screen.frame
        var y = topY

        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0.25
        NSAnimationContext.current.timingFunction = CAMediaTimingFunction(name: .easeOut)

        for element in sorted {
            let bp = element.value
            var frame = bp.panel.frame
            let clampedX = max(screenRect.minX + margin, min(iconFrame.midX - frame.width / 2, screenRect.maxX - frame.width - margin))
            frame.origin.x = clampedX
            frame.origin.y = y - frame.height
            bp.panel.animator().setFrame(frame, display: true)
            y -= frame.height + spacing
        }

        NSAnimationContext.endGrouping()
    }
}

private struct BubblePanel {
    let panel: NSPanel
    let hosting: NSHostingController<AnyView>
}
