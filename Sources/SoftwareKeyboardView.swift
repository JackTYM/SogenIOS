import SwiftUI
import UIKit

final class SoftwareKeyboardHostView: UIView, UIKeyInput {
    var onInsertText: ((String) -> Void)?
    var onDeleteBackward: (() -> Void)?

    var hasText: Bool { true }

    func insertText(_ text: String) {
        onInsertText?(text)
    }

    func deleteBackward() {
        onDeleteBackward?()
    }

    override var canBecomeFirstResponder: Bool { true }
}

/// Invisible view whose only job is owning first-responder status, so toggling `isActive` shows
/// or hides iOS's own on-screen keyboard. Delivers WM_CHAR-equivalent UTF-16 code units directly
/// -- this is a separate input path from the hardware-keyboard observer, which sends
/// WM_KEYDOWN/WM_KEYUP instead and relies on the guest's own TranslateMessage for any WM_CHAR it
/// needs.
struct SoftwareKeyboardView: UIViewRepresentable {
    let isActive: Bool
    let onChar: (UInt16) -> Void

    func makeUIView(context: Context) -> SoftwareKeyboardHostView {
        let view = SoftwareKeyboardHostView(frame: .zero)
        configure(view)
        return view
    }

    func updateUIView(_ uiView: SoftwareKeyboardHostView, context: Context) {
        configure(uiView)
        if isActive && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        } else if !isActive && uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    private func configure(_ view: SoftwareKeyboardHostView) {
        view.onInsertText = { text in
            for scalar in text.utf16 {
                onChar(scalar)
            }
        }
        view.onDeleteBackward = {
            onChar(0x08)
        }
    }
}
