import SwiftUI
import AppKit

struct ViewFilterField: NSViewRepresentable {
    @Binding var text: String
    var prompt: String
    /// Takes keyboard focus as soon as the field appears in a window.
    var focusOnAppear = false

    func makeNSView(context: Context) -> NSSearchField {
        let field = FocusingSearchField()
        field.focusOnAppear = focusOnAppear
        field.placeholderString = prompt
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        nsView.placeholderString = prompt
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }
    }
}

private final class FocusingSearchField: NSSearchField {
    var focusOnAppear = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard focusOnAppear, let window else { return }
        DispatchQueue.main.async { window.makeFirstResponder(self) }
    }
}
