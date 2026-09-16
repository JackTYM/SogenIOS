import UIKit
import SwiftUI

enum MouseMode {
    case touchscreen
    case trackpad
}

/// Hosts the guest's CALayer and translates touch gestures into guest mouse input, per the
/// active MouseMode. See docs/superpowers/specs/2026-09-16-ios-input-ux-design.md for the
/// touchscreen-vs-trackpad rationale (Steam Link's Direct-Cursor/Trackpad modes are the direct
/// inspiration).
final class EmulatorHostView: UIView {
    // UIPanGestureRecognizer's move-to-.began threshold is much shorter than
    // UILongPressGestureRecognizer's minimumPressDuration, so leaving pan enabled in
    // touchscreen mode lets it win recognition over a press-and-hold-drag, silently
    // dropping the drag (handlePan is a no-op there). Disabling it outside trackpad mode
    // removes it from the recognition race entirely.
    var mode: MouseMode = .touchscreen {
        didSet {
            panRecognizer.isEnabled = mode == .trackpad
        }
    }
    var frameSize: CGSize = .zero
    var onDeliverMove: ((CGPoint) -> Void)?
    var onDeliverButton: ((CGPoint, UInt32) -> Void)?
    var onDeliverDelta: ((CGFloat, CGFloat) -> Void)?
    var onDeliverClick: (() -> Void)?
    var onDeliverRightClick: (() -> Void)?

    private let wmLButtonDown: UInt32 = 0x0201
    private let wmLButtonUp: UInt32 = 0x0202
    private let wmRButtonDown: UInt32 = 0x0204
    private let wmRButtonUp: UInt32 = 0x0205

    private let panRecognizer = UIPanGestureRecognizer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        layer.magnificationFilter = .nearest

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap))
        twoFingerTap.numberOfTouchesRequired = 2
        addGestureRecognizer(twoFingerTap)

        panRecognizer.addTarget(self, action: #selector(handlePan))
        panRecognizer.isEnabled = mode == .trackpad
        addGestureRecognizer(panRecognizer)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        longPress.minimumPressDuration = 0.35
        addGestureRecognizer(longPress)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Transforms a point in this view's own coordinate space into guest-frame pixel space,
    /// accounting for the aspect-fit letterbox scale/offset between the two.
    private func toGuestPoint(_ viewPoint: CGPoint) -> CGPoint {
        guard frameSize.width > 0, frameSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return viewPoint
        }
        let scale = min(bounds.width / frameSize.width, bounds.height / frameSize.height)
        let displayedWidth = frameSize.width * scale
        let displayedHeight = frameSize.height * scale
        let offsetX = (bounds.width - displayedWidth) / 2
        let offsetY = (bounds.height - displayedHeight) / 2
        let guestX = (viewPoint.x - offsetX) / scale
        let guestY = (viewPoint.y - offsetY) / scale
        return CGPoint(x: guestX, y: guestY)
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        switch mode {
        case .touchscreen:
            let guestPoint = toGuestPoint(recognizer.location(in: self))
            onDeliverMove?(guestPoint)
            onDeliverButton?(guestPoint, wmLButtonDown)
            onDeliverButton?(guestPoint, wmLButtonUp)
        case .trackpad:
            onDeliverClick?()
        }
    }

    @objc private func handleTwoFingerTap(_ recognizer: UITapGestureRecognizer) {
        switch mode {
        case .touchscreen:
            let guestPoint = toGuestPoint(recognizer.location(in: self))
            onDeliverButton?(guestPoint, wmRButtonDown)
            onDeliverButton?(guestPoint, wmRButtonUp)
        case .trackpad:
            onDeliverRightClick?()
        }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        guard mode == .trackpad else { return }
        let translation = recognizer.translation(in: self)
        onDeliverDelta?(translation.x, translation.y)
        recognizer.setTranslation(.zero, in: self)
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        let point = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            switch mode {
            case .touchscreen:
                let guestPoint = toGuestPoint(point)
                onDeliverMove?(guestPoint)
                onDeliverButton?(guestPoint, wmLButtonDown)
            case .trackpad:
                onDeliverClick?()
            }
        case .changed:
            if mode == .touchscreen {
                onDeliverMove?(toGuestPoint(point))
            }
        case .ended, .cancelled:
            if mode == .touchscreen {
                onDeliverButton?(toGuestPoint(point), wmLButtonUp)
            }
        default:
            break
        }
    }
}

struct EmulatorView: UIViewRepresentable {
    let onViewReady: (CALayer) -> Void
    let mode: MouseMode
    let frameSize: CGSize
    let onDeliverMove: (CGPoint) -> Void
    let onDeliverButton: (CGPoint, UInt32) -> Void
    let onDeliverDelta: (CGFloat, CGFloat) -> Void
    let onDeliverClick: () -> Void
    let onDeliverRightClick: () -> Void

    func makeUIView(context: Context) -> EmulatorHostView {
        let view = EmulatorHostView(frame: .zero)
        configure(view)
        onViewReady(view.layer)
        return view
    }

    func updateUIView(_ uiView: EmulatorHostView, context: Context) {
        configure(uiView)
    }

    private func configure(_ view: EmulatorHostView) {
        view.mode = mode
        view.frameSize = frameSize
        view.onDeliverMove = onDeliverMove
        view.onDeliverButton = onDeliverButton
        view.onDeliverDelta = onDeliverDelta
        view.onDeliverClick = onDeliverClick
        view.onDeliverRightClick = onDeliverRightClick
    }
}
