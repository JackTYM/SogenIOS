import UIKit
import SwiftUI

/// A plain UIView whose backing layer receives guest frames, plus the single tap recognizer
/// that proves the host -> guest input path.
final class EmulatorHostView: UIView {
    var onTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        layer.magnificationFilter = .nearest
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(recognizer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    @objc private func handleTap() {
        onTap?()
    }
}

struct EmulatorView: UIViewRepresentable {
    let onViewReady: (CALayer) -> Void
    let onTap: () -> Void

    func makeUIView(context: Context) -> EmulatorHostView {
        let view = EmulatorHostView(frame: .zero)
        view.onTap = onTap
        onViewReady(view.layer)
        return view
    }

    func updateUIView(_ uiView: EmulatorHostView, context: Context) {
        uiView.onTap = onTap
    }
}
