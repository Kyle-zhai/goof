import Carbon.HIToolbox
import Foundation

/// A key combination for `GlobalHotKey`, in Carbon terms.
struct KeyCombo: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    /// How menus and settings show it.
    let display: String

    /// ⌃⌥⌘K. Chosen to stay clear of common shortcuts: Figma uses ⌥⌘K,
    /// Xcode ⇧⌘K, Rectangle ⌃⌥K, and ⌃⌥Space switches input sources.
    static let composeShortcut = KeyCombo(keyCode: UInt32(kVK_ANSI_K),
                                          modifiers: UInt32(controlKey | optionKey | cmdKey),
                                          display: "⌃⌥⌘K")
}

/// A system-wide shortcut. Carbon's hot key API needs no Accessibility or
/// Input Monitoring permission and works inside the App Sandbox.
final class GlobalHotKey {
    enum Failure: Error {
        case unavailable(OSStatus)
    }

    private let action: @MainActor () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static let signature: OSType = 0x474F_4F46 // "GOOF"

    init(_ combo: KeyCombo, action: @escaping @MainActor () -> Void) throws {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            // Carbon delivers hot key events on the main thread.
            MainActor.assumeIsolated { hotKey.action() }
            return OSStatus(noErr)
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        guard installed == OSStatus(noErr) else { throw Failure.unavailable(installed) }

        let id = EventHotKeyID(signature: Self.signature, id: 1)
        let registered = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registered == OSStatus(noErr) else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            handlerRef = nil
            throw Failure.unavailable(registered)
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
