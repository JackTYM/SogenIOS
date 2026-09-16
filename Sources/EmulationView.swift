import SwiftUI
import UIKit

struct EmulationView: View {
    let emulator: SogenEmulator
    @Environment(\.dismiss) private var dismiss

    @State private var mode: MouseMode = .touchscreen
    @State private var frameSize: CGSize = .zero

    var body: some View {
        VStack(spacing: 0) {
            EmulatorView(
                onViewReady: { layer in
                    emulator.attach(layer)
                },
                mode: mode,
                frameSize: frameSize,
                onDeliverMove: { point in emulator.deliverMouseMove(point) },
                onDeliverButton: { point, message in emulator.deliverMouseButton(point, message: message) },
                onDeliverDelta: { dx, dy in emulator.deliverMouseDelta(dx, dy: dy) },
                onDeliverClick: { emulator.deliverTap() },
                onDeliverRightClick: { emulator.deliverRightClick() }
            )
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
        .onAppear {
            emulator.onFrameSize = { size in
                frameSize = size
            }
        }
    }
}
