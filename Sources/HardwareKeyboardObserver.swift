import GameController

/// Maps a physical GCKeyCode to the (VK, PS/2 XT scan code, extended-key bit) triple the desktop
/// SDL backend already uses for the same physical keys. GCKeyCode is a layout-independent
/// USB-HID keyboard-page usage code, conceptually identical to SDL_Scancode.
private struct KeyMapping {
    let vk: UInt16
    let scanCode: UInt8
    let extended: Bool
}

private let keyCodeMap: [GCKeyCode: KeyMapping] = [
    // Letters
    .keyA: KeyMapping(vk: 0x41, scanCode: 0x1E, extended: false),
    .keyB: KeyMapping(vk: 0x42, scanCode: 0x30, extended: false),
    .keyC: KeyMapping(vk: 0x43, scanCode: 0x2E, extended: false),
    .keyD: KeyMapping(vk: 0x44, scanCode: 0x20, extended: false),
    .keyE: KeyMapping(vk: 0x45, scanCode: 0x12, extended: false),
    .keyF: KeyMapping(vk: 0x46, scanCode: 0x21, extended: false),
    .keyG: KeyMapping(vk: 0x47, scanCode: 0x22, extended: false),
    .keyH: KeyMapping(vk: 0x48, scanCode: 0x23, extended: false),
    .keyI: KeyMapping(vk: 0x49, scanCode: 0x17, extended: false),
    .keyJ: KeyMapping(vk: 0x4A, scanCode: 0x24, extended: false),
    .keyK: KeyMapping(vk: 0x4B, scanCode: 0x25, extended: false),
    .keyL: KeyMapping(vk: 0x4C, scanCode: 0x26, extended: false),
    .keyM: KeyMapping(vk: 0x4D, scanCode: 0x32, extended: false),
    .keyN: KeyMapping(vk: 0x4E, scanCode: 0x31, extended: false),
    .keyO: KeyMapping(vk: 0x4F, scanCode: 0x18, extended: false),
    .keyP: KeyMapping(vk: 0x50, scanCode: 0x19, extended: false),
    .keyQ: KeyMapping(vk: 0x51, scanCode: 0x10, extended: false),
    .keyR: KeyMapping(vk: 0x52, scanCode: 0x13, extended: false),
    .keyS: KeyMapping(vk: 0x53, scanCode: 0x1F, extended: false),
    .keyT: KeyMapping(vk: 0x54, scanCode: 0x14, extended: false),
    .keyU: KeyMapping(vk: 0x55, scanCode: 0x16, extended: false),
    .keyV: KeyMapping(vk: 0x56, scanCode: 0x2F, extended: false),
    .keyW: KeyMapping(vk: 0x57, scanCode: 0x11, extended: false),
    .keyX: KeyMapping(vk: 0x58, scanCode: 0x2D, extended: false),
    .keyY: KeyMapping(vk: 0x59, scanCode: 0x15, extended: false),
    .keyZ: KeyMapping(vk: 0x5A, scanCode: 0x2C, extended: false),

    // Number row
    .one: KeyMapping(vk: 0x31, scanCode: 0x02, extended: false),
    .two: KeyMapping(vk: 0x32, scanCode: 0x03, extended: false),
    .three: KeyMapping(vk: 0x33, scanCode: 0x04, extended: false),
    .four: KeyMapping(vk: 0x34, scanCode: 0x05, extended: false),
    .five: KeyMapping(vk: 0x35, scanCode: 0x06, extended: false),
    .six: KeyMapping(vk: 0x36, scanCode: 0x07, extended: false),
    .seven: KeyMapping(vk: 0x37, scanCode: 0x08, extended: false),
    .eight: KeyMapping(vk: 0x38, scanCode: 0x09, extended: false),
    .nine: KeyMapping(vk: 0x39, scanCode: 0x0A, extended: false),
    .zero: KeyMapping(vk: 0x30, scanCode: 0x0B, extended: false),

    // Basic keys
    .escape: KeyMapping(vk: 0x1B, scanCode: 0x01, extended: false),
    .deleteOrBackspace: KeyMapping(vk: 0x08, scanCode: 0x0E, extended: false),
    .tab: KeyMapping(vk: 0x09, scanCode: 0x0F, extended: false),
    .returnOrEnter: KeyMapping(vk: 0x0D, scanCode: 0x1C, extended: false),
    .spacebar: KeyMapping(vk: 0x20, scanCode: 0x39, extended: false),

    // Modifiers -- sogen only defines the generic (side-independent) VK_SHIFT/VK_CONTROL/VK_MENU;
    // side information is carried entirely by the scan code + extended bit, matching how the
    // desktop SDL backend handles left/right Ctrl/Alt.
    .leftShift: KeyMapping(vk: 0x10, scanCode: 0x2A, extended: false),
    .rightShift: KeyMapping(vk: 0x10, scanCode: 0x36, extended: false),
    .leftControl: KeyMapping(vk: 0x11, scanCode: 0x1D, extended: false),
    .rightControl: KeyMapping(vk: 0x11, scanCode: 0x1D, extended: true),
    .leftAlt: KeyMapping(vk: 0x12, scanCode: 0x38, extended: false),
    .rightAlt: KeyMapping(vk: 0x12, scanCode: 0x38, extended: true),
    .leftGUI: KeyMapping(vk: 0x5B, scanCode: 0x5B, extended: true),
    .rightGUI: KeyMapping(vk: 0x5C, scanCode: 0x5C, extended: true),
    .application: KeyMapping(vk: 0x5D, scanCode: 0x5D, extended: true),

    // Navigation cluster: extended
    .insert: KeyMapping(vk: 0x2D, scanCode: 0x52, extended: true),
    .deleteForward: KeyMapping(vk: 0x2E, scanCode: 0x53, extended: true),
    .home: KeyMapping(vk: 0x24, scanCode: 0x47, extended: true),
    .end: KeyMapping(vk: 0x23, scanCode: 0x4F, extended: true),
    .pageUp: KeyMapping(vk: 0x21, scanCode: 0x49, extended: true),
    .pageDown: KeyMapping(vk: 0x22, scanCode: 0x51, extended: true),

    // Arrow keys: extended
    .leftArrow: KeyMapping(vk: 0x25, scanCode: 0x4B, extended: true),
    .upArrow: KeyMapping(vk: 0x26, scanCode: 0x48, extended: true),
    .rightArrow: KeyMapping(vk: 0x27, scanCode: 0x4D, extended: true),
    .downArrow: KeyMapping(vk: 0x28, scanCode: 0x50, extended: true),

    // Locks
    .capsLock: KeyMapping(vk: 0x14, scanCode: 0x3A, extended: false),
    .keypadNumLock: KeyMapping(vk: 0x90, scanCode: 0x45, extended: false),
    .scrollLock: KeyMapping(vk: 0x91, scanCode: 0x46, extended: false),
    .pause: KeyMapping(vk: 0x13, scanCode: 0x45, extended: false),

    // Punctuation, US keyboard physical positions
    .graveAccentAndTilde: KeyMapping(vk: 0xC0, scanCode: 0x29, extended: false),
    .hyphen: KeyMapping(vk: 0xBD, scanCode: 0x0C, extended: false),
    .equalSign: KeyMapping(vk: 0xBB, scanCode: 0x0D, extended: false),
    .openBracket: KeyMapping(vk: 0xDB, scanCode: 0x1A, extended: false),
    .closeBracket: KeyMapping(vk: 0xDD, scanCode: 0x1B, extended: false),
    .backslash: KeyMapping(vk: 0xDC, scanCode: 0x2B, extended: false),
    .nonUSPound: KeyMapping(vk: 0xDC, scanCode: 0x2B, extended: false),
    .semicolon: KeyMapping(vk: 0xBA, scanCode: 0x27, extended: false),
    .quote: KeyMapping(vk: 0xDE, scanCode: 0x28, extended: false),
    .comma: KeyMapping(vk: 0xBC, scanCode: 0x33, extended: false),
    .period: KeyMapping(vk: 0xBE, scanCode: 0x34, extended: false),
    .slash: KeyMapping(vk: 0xBF, scanCode: 0x35, extended: false),
    .nonUSBackslash: KeyMapping(vk: 0xE2, scanCode: 0x56, extended: false),

    // Function keys
    .F1: KeyMapping(vk: 0x70, scanCode: 0x3B, extended: false),
    .F2: KeyMapping(vk: 0x71, scanCode: 0x3C, extended: false),
    .F3: KeyMapping(vk: 0x72, scanCode: 0x3D, extended: false),
    .F4: KeyMapping(vk: 0x73, scanCode: 0x3E, extended: false),
    .F5: KeyMapping(vk: 0x74, scanCode: 0x3F, extended: false),
    .F6: KeyMapping(vk: 0x75, scanCode: 0x40, extended: false),
    .F7: KeyMapping(vk: 0x76, scanCode: 0x41, extended: false),
    .F8: KeyMapping(vk: 0x77, scanCode: 0x42, extended: false),
    .F9: KeyMapping(vk: 0x78, scanCode: 0x43, extended: false),
    .F10: KeyMapping(vk: 0x79, scanCode: 0x44, extended: false),
    .F11: KeyMapping(vk: 0x7A, scanCode: 0x57, extended: false),
    .F12: KeyMapping(vk: 0x7B, scanCode: 0x58, extended: false),

    // Keypad
    .keypadSlash: KeyMapping(vk: 0x6F, scanCode: 0x35, extended: true),
    .keypadAsterisk: KeyMapping(vk: 0x6A, scanCode: 0x37, extended: false),
    .keypadHyphen: KeyMapping(vk: 0x6D, scanCode: 0x4A, extended: false),
    .keypadPlus: KeyMapping(vk: 0x6B, scanCode: 0x4E, extended: false),
    .keypadEnter: KeyMapping(vk: 0x0D, scanCode: 0x1C, extended: true),
    .keypad7: KeyMapping(vk: 0x67, scanCode: 0x47, extended: false),
    .keypad8: KeyMapping(vk: 0x68, scanCode: 0x48, extended: false),
    .keypad9: KeyMapping(vk: 0x69, scanCode: 0x49, extended: false),
    .keypad4: KeyMapping(vk: 0x64, scanCode: 0x4B, extended: false),
    .keypad5: KeyMapping(vk: 0x65, scanCode: 0x4C, extended: false),
    .keypad6: KeyMapping(vk: 0x66, scanCode: 0x4D, extended: false),
    .keypad1: KeyMapping(vk: 0x61, scanCode: 0x4F, extended: false),
    .keypad2: KeyMapping(vk: 0x62, scanCode: 0x50, extended: false),
    .keypad3: KeyMapping(vk: 0x63, scanCode: 0x51, extended: false),
    .keypad0: KeyMapping(vk: 0x60, scanCode: 0x52, extended: false),
    .keypadPeriod: KeyMapping(vk: 0x6E, scanCode: 0x53, extended: false),
]

/// Observes GameController.framework's coalesced hardware keyboard and translates key events into
/// the same (vk, scanCode, extended, wasDown, altContext) shape windows_emulator::deliver_key_down/
/// deliver_key_up expect. Not the input path for the software on-screen keyboard.
final class HardwareKeyboardObserver {
    var onKeyDown: ((UInt16, UInt8, Bool, Bool, Bool) -> Void)?
    var onKeyUp: ((UInt16, UInt8, Bool, Bool) -> Void)?

    private var heldKeys: Set<GCKeyCode> = []
    private var connectToken: NSObjectProtocol?
    private var disconnectToken: NSObjectProtocol?

    init() {
        connectToken = NotificationCenter.default.addObserver(
            forName: .GCKeyboardDidConnect, object: nil, queue: .main
        ) { [weak self] notification in
            guard let keyboard = notification.object as? GCKeyboard else { return }
            self?.attach(keyboard)
        }
        disconnectToken = NotificationCenter.default.addObserver(
            forName: .GCKeyboardDidDisconnect, object: nil, queue: .main
        ) { [weak self] _ in
            self?.heldKeys.removeAll()
        }
        if let keyboard = GCKeyboard.coalesced {
            attach(keyboard)
        }
    }

    deinit {
        if let connectToken { NotificationCenter.default.removeObserver(connectToken) }
        if let disconnectToken { NotificationCenter.default.removeObserver(disconnectToken) }
    }

    private func attach(_ keyboard: GCKeyboard) {
        keyboard.keyboardInput?.keyChangedHandler = { [weak self] _, _, keyCode, pressed in
            self?.handleKeyChange(keyCode: keyCode, pressed: pressed, input: keyboard.keyboardInput)
        }
    }

    private func handleKeyChange(keyCode: GCKeyCode, pressed: Bool, input: GCKeyboardInput?) {
        guard let mapping = keyCodeMap[keyCode] else { return }

        let altHeld = (input?.button(forKeyCode: .leftAlt)?.isPressed ?? false)
            || (input?.button(forKeyCode: .rightAlt)?.isPressed ?? false)
        let altContext = altHeld && keyCode != .leftAlt && keyCode != .rightAlt

        if pressed {
            let wasDown = heldKeys.contains(keyCode)
            heldKeys.insert(keyCode)
            onKeyDown?(mapping.vk, mapping.scanCode, mapping.extended, wasDown, altContext)
        } else {
            heldKeys.remove(keyCode)
            onKeyUp?(mapping.vk, mapping.scanCode, mapping.extended, altContext)
        }
    }
}
