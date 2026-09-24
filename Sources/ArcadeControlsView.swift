import SwiftUI

/// Renders an ArcadeProfile's buttons and joystick as a play-time touch overlay, translating
/// presses into deliverKeyDown/Up or deliverMouseButton calls. Drawn on top of EmulatorHostView
/// only when EmulationView's mode is .arcade -- EmulatorHostView's own gesture recognizers are
/// disabled in that mode, so there's no conflict with touchscreen/trackpad handling underneath.
struct ArcadeControlsView: View {
    let profile: ArcadeProfile
    let onKeyDown: (UInt16, UInt8, Bool) -> Void
    let onKeyUp: (UInt16, UInt8, Bool) -> Void
    let onMouseButton: (UInt32) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(profile.buttons) { button in
                    ArcadeButtonView(
                        button: button,
                        canvasSize: geometry.size,
                        onKeyDown: onKeyDown,
                        onKeyUp: onKeyUp,
                        onMouseButton: onMouseButton)
                }
                if let joystick = profile.joystick {
                    ArcadeJoystickView(
                        joystick: joystick,
                        canvasSize: geometry.size,
                        onKeyDown: onKeyDown,
                        onKeyUp: onKeyUp)
                }
            }
        }
    }
}

private struct ArcadeButtonView: View {
    let button: ArcadeButton
    let canvasSize: CGSize
    let onKeyDown: (UInt16, UInt8, Bool) -> Void
    let onKeyUp: (UInt16, UInt8, Bool) -> Void
    let onMouseButton: (UInt32) -> Void

    @State private var isPressed = false

    private let wmLButtonDown: UInt32 = 0x0201
    private let wmLButtonUp: UInt32 = 0x0202
    private let wmRButtonDown: UInt32 = 0x0204
    private let wmRButtonUp: UInt32 = 0x0205

    var body: some View {
        Text(button.label)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: button.size.width * canvasSize.width,
                   height: button.size.height * canvasSize.height)
            .background(Color.black.opacity(isPressed ? 0.75 : 0.45))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .position(x: button.position.x * canvasSize.width,
                      y: button.position.y * canvasSize.height)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                            press()
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                        release()
                    }
            )
    }

    private func press() {
        switch button.action {
        case .key(let vk, let scanCode, let extended):
            onKeyDown(vk, scanCode, extended)
        case .mouseClick(let side):
            onMouseButton(side == .left ? wmLButtonDown : wmRButtonDown)
        }
    }

    private func release() {
        switch button.action {
        case .key(let vk, let scanCode, let extended):
            onKeyUp(vk, scanCode, extended)
        case .mouseClick(let side):
            onMouseButton(side == .left ? wmLButtonUp : wmRButtonUp)
        }
    }
}

private struct ArcadeJoystickView: View {
    let joystick: ArcadeJoystick
    let canvasSize: CGSize
    let onKeyDown: (UInt16, UInt8, Bool) -> Void
    let onKeyUp: (UInt16, UInt8, Bool) -> Void

    @State private var knobOffset: CGSize = .zero
    @State private var heldDirections: Set<Direction> = []

    private enum Direction: Hashable {
        case up, down, left, right
    }

    private var center: CGPoint {
        CGPoint(x: joystick.position.x * canvasSize.width, y: joystick.position.y * canvasSize.height)
    }

    private var radius: CGFloat {
        joystick.radius * canvasSize.width
    }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.white.opacity(0.5), lineWidth: 2)
                .frame(width: radius * 2, height: radius * 2)
            Circle()
                .fill(Color.white.opacity(0.7))
                .frame(width: radius * 0.8, height: radius * 0.8)
                .offset(knobOffset)
        }
        .position(center)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let clamped = clampToRadius(value.translation)
                    knobOffset = clamped
                    updateDirections(for: clamped)
                }
                .onEnded { _ in
                    knobOffset = .zero
                    releaseAll()
                }
        )
    }

    private func clampToRadius(_ translation: CGSize) -> CGSize {
        let distance = sqrt(translation.width * translation.width + translation.height * translation.height)
        guard distance > radius, distance > 0 else { return translation }
        let scale = radius / distance
        return CGSize(width: translation.width * scale, height: translation.height * scale)
    }

    // 8 sectors of 45 degrees. SwiftUI drag coordinates: 0=right, 90=down, ±180=left, -90=up.
    // Diagonal sectors satisfy two of the four range checks at once, holding both directions.
    private func updateDirections(for translation: CGSize) {
        let distance = sqrt(translation.width * translation.width + translation.height * translation.height)
        guard distance > radius * 0.2 else {
            if !heldDirections.isEmpty {
                releaseAll()
            }
            return
        }

        let angle = atan2(translation.height, translation.width) * 180 / .pi
        var newDirections: Set<Direction> = []
        if angle > -157.5 && angle < -22.5 { newDirections.insert(.up) }
        if angle > 22.5 && angle < 157.5 { newDirections.insert(.down) }
        if angle > 112.5 || angle < -112.5 { newDirections.insert(.left) }
        if angle > -67.5 && angle < 67.5 { newDirections.insert(.right) }

        for removed in heldDirections.subtracting(newDirections) {
            releaseDirection(removed)
        }
        for added in newDirections.subtracting(heldDirections) {
            pressDirection(added)
        }
        heldDirections = newDirections
    }

    private func releaseAll() {
        for direction in heldDirections {
            releaseDirection(direction)
        }
        heldDirections = []
    }

    private func binding(for direction: Direction) -> ArcadeActionKind? {
        switch direction {
        case .up: return joystick.up
        case .down: return joystick.down
        case .left: return joystick.left
        case .right: return joystick.right
        }
    }

    private func pressDirection(_ direction: Direction) {
        guard case .key(let vk, let scanCode, let extended) = binding(for: direction) else { return }
        onKeyDown(vk, scanCode, extended)
    }

    private func releaseDirection(_ direction: Direction) {
        guard case .key(let vk, let scanCode, let extended) = binding(for: direction) else { return }
        onKeyUp(vk, scanCode, extended)
    }
}
