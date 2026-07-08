import SwiftUI

private final class WindowConfigView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.hidesOnDeactivate = false
    }
}

struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowConfigView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
