import Foundation
import CoreGraphics

enum MouseButton: String, Codable {
    case left
    case right
}

/// A single control's action. Reuses the exact real-Windows WM_KEYDOWN/WM_KEYUP vk/scanCode/
/// extended triple deliverKeyDown/deliverKeyUp already expect -- see HardwareKeyboardObserver
/// for the reference desktop-parity values these are drawn from.
enum ArcadeActionKind {
    case key(vk: UInt16, scanCode: UInt8, extended: Bool)
    case mouseClick(button: MouseButton)
}

extension ArcadeActionKind: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, vk, scanCode, extended, button
    }

    private enum Kind: String, Codable {
        case key
        case mouseClick
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .type)
        switch kind {
        case .key:
            let vk = try container.decode(UInt16.self, forKey: .vk)
            let scanCode = try container.decode(UInt8.self, forKey: .scanCode)
            let extended = try container.decode(Bool.self, forKey: .extended)
            self = .key(vk: vk, scanCode: scanCode, extended: extended)
        case .mouseClick:
            let button = try container.decode(MouseButton.self, forKey: .button)
            self = .mouseClick(button: button)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .key(let vk, let scanCode, let extended):
            try container.encode(Kind.key, forKey: .type)
            try container.encode(vk, forKey: .vk)
            try container.encode(scanCode, forKey: .scanCode)
            try container.encode(extended, forKey: .extended)
        case .mouseClick(let button):
            try container.encode(Kind.mouseClick, forKey: .type)
            try container.encode(button, forKey: .button)
        }
    }
}

struct ArcadeButton: Codable, Identifiable {
    var id: UUID
    var label: String
    var position: CGPoint   // normalized 0...1 within the canvas
    var size: CGSize        // normalized 0...1 within the canvas
    var action: ArcadeActionKind
}

/// Direction bindings are ArcadeActionKind for type reuse with ArcadeButton, but only the
/// `.key` case is ever presented in the editor for these -- a joystick direction mapping to a
/// mouse click doesn't make sense.
struct ArcadeJoystick: Codable {
    var position: CGPoint   // normalized 0...1 within the canvas (center)
    var radius: CGFloat     // normalized 0...1, relative to canvas width
    var up: ArcadeActionKind?
    var down: ArcadeActionKind?
    var left: ArcadeActionKind?
    var right: ArcadeActionKind?
}

struct ArcadeProfile: Codable, Identifiable {
    var id: UUID
    var name: String
    var buttons: [ArcadeButton]
    var joystick: ArcadeJoystick?   // at most one per profile
}
