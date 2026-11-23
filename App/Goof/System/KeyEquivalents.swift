import AppKit

/// While another app is active, a menu bar app's Edit menu is not in play, so
/// ⌘C, ⌘V, ⌘X, ⌘A and ⌘Z would do nothing in Goof's text fields. Goof's
/// windows forward these shortcuts to the focused field themselves.
enum StandardEditKeys {
    @MainActor
    static func handle(_ event: NSEvent, in window: NSWindow) -> Bool {
        guard event.type == .keyDown, let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        let selector: Selector?
        if flags == .command {
            switch key {
            case "x": selector = #selector(NSText.cut(_:))
            case "c": selector = #selector(NSText.copy(_:))
            case "v": selector = #selector(NSText.paste(_:))
            case "a": selector = #selector(NSText.selectAll(_:))
            case "z": selector = Selector(("undo:"))
            default: selector = nil
            }
        } else if flags == [.command, .shift], key == "z" {
            selector = Selector(("redo:"))
        } else {
            selector = nil
        }
        guard let selector else { return false }
        return NSApp.sendAction(selector, to: nil, from: window)
    }
}

enum FieldEditor {
    /// True while an input method (for example Pinyin) is composing text, when
    /// Esc and Return belong to the input method rather than to Goof.
    @MainActor
    static var hasMarkedText: Bool {
        let window = NSApp.keyWindow ?? NSApp.windows.first { $0.isKeyWindow }
        return (window?.firstResponder as? NSTextView)?.hasMarkedText() ?? false
    }
}
