import Foundation

/// A named, physical-key binding a profile's button or joystick direction can be assigned to.
/// vk/scanCode/extended reuse the exact same real-Windows values HardwareKeyboardObserver's own
/// GCKeyCode mapping table uses for the same physical keys.
struct ArcadeKeyBinding: Identifiable {
    let id: String
    let name: String
    let vk: UInt16
    let scanCode: UInt8
    let extended: Bool

    var action: ArcadeActionKind {
        .key(vk: vk, scanCode: scanCode, extended: extended)
    }
}

let arcadeKeyCatalog: [ArcadeKeyBinding] = [
    ArcadeKeyBinding(id: "w", name: "W", vk: 0x57, scanCode: 0x11, extended: false),
    ArcadeKeyBinding(id: "a", name: "A", vk: 0x41, scanCode: 0x1E, extended: false),
    ArcadeKeyBinding(id: "s", name: "S", vk: 0x53, scanCode: 0x1F, extended: false),
    ArcadeKeyBinding(id: "d", name: "D", vk: 0x44, scanCode: 0x20, extended: false),
    ArcadeKeyBinding(id: "e", name: "E", vk: 0x45, scanCode: 0x12, extended: false),
    ArcadeKeyBinding(id: "q", name: "Q", vk: 0x51, scanCode: 0x10, extended: false),
    ArcadeKeyBinding(id: "r", name: "R", vk: 0x52, scanCode: 0x13, extended: false),
    ArcadeKeyBinding(id: "f", name: "F", vk: 0x46, scanCode: 0x21, extended: false),
    ArcadeKeyBinding(id: "c", name: "C", vk: 0x43, scanCode: 0x2E, extended: false),
    ArcadeKeyBinding(id: "space", name: "Space", vk: 0x20, scanCode: 0x39, extended: false),
    ArcadeKeyBinding(id: "leftShift", name: "Shift", vk: 0x10, scanCode: 0x2A, extended: false),
    ArcadeKeyBinding(id: "leftControl", name: "Ctrl", vk: 0x11, scanCode: 0x1D, extended: false),
    ArcadeKeyBinding(id: "leftAlt", name: "Alt", vk: 0x12, scanCode: 0x38, extended: false),
    ArcadeKeyBinding(id: "tab", name: "Tab", vk: 0x09, scanCode: 0x0F, extended: false),
    ArcadeKeyBinding(id: "returnOrEnter", name: "Enter", vk: 0x0D, scanCode: 0x1C, extended: false),
    ArcadeKeyBinding(id: "escape", name: "Esc", vk: 0x1B, scanCode: 0x01, extended: false),
    ArcadeKeyBinding(id: "upArrow", name: "\u{2191}", vk: 0x26, scanCode: 0x48, extended: true),
    ArcadeKeyBinding(id: "downArrow", name: "\u{2193}", vk: 0x28, scanCode: 0x50, extended: true),
    ArcadeKeyBinding(id: "leftArrow", name: "\u{2190}", vk: 0x25, scanCode: 0x4B, extended: true),
    ArcadeKeyBinding(id: "rightArrow", name: "\u{2192}", vk: 0x27, scanCode: 0x4D, extended: true),
    ArcadeKeyBinding(id: "f1", name: "F1", vk: 0x70, scanCode: 0x3B, extended: false),
    ArcadeKeyBinding(id: "f2", name: "F2", vk: 0x71, scanCode: 0x3C, extended: false),
    ArcadeKeyBinding(id: "f3", name: "F3", vk: 0x72, scanCode: 0x3D, extended: false),
    ArcadeKeyBinding(id: "f4", name: "F4", vk: 0x73, scanCode: 0x3E, extended: false),
    ArcadeKeyBinding(id: "1", name: "1", vk: 0x31, scanCode: 0x02, extended: false),
    ArcadeKeyBinding(id: "2", name: "2", vk: 0x32, scanCode: 0x03, extended: false),
    ArcadeKeyBinding(id: "3", name: "3", vk: 0x33, scanCode: 0x04, extended: false),
    ArcadeKeyBinding(id: "4", name: "4", vk: 0x34, scanCode: 0x05, extended: false),
]
