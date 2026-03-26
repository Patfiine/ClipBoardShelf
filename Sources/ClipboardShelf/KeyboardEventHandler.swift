import AppKit
import SwiftUI

struct KeyboardEventHandler: NSViewRepresentable {
    let onEvent: (NSEvent) -> Bool

    func makeNSView(context: Context) -> KeyboardHandlingView {
        let view = KeyboardHandlingView()
        view.onEvent = onEvent

        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }

        return view
    }

    func updateNSView(_ nsView: KeyboardHandlingView, context: Context) {
        nsView.onEvent = onEvent

        DispatchQueue.main.async {
            nsView.window?.makeFirstResponder(nsView)
        }
    }
}

final class KeyboardHandlingView: NSView {
    var onEvent: ((NSEvent) -> Bool)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if onEvent?(event) == true {
            return
        }

        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onEvent?(event) == true {
            return true
        }

        return super.performKeyEquivalent(with: event)
    }
}
