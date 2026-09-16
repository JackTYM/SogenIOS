import SwiftUI
import UIKit

/// The emulation screen shell. Chrome (back button styling, icon row, mouse-mode switching,
/// gestures) and the real live guest layer are added in later tasks of this same plan -- this
/// task only wires navigation and shows a placeholder.
struct EmulationView: View {
    let emulator: SogenEmulator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Color.black
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: {
                    emulator.stop()
                    dismiss()
                }) {
                    Image(systemName: "chevron.left")
                }
            }
        }
    }
}
