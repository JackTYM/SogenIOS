import SwiftUI
import UIKit

struct EmulationView: View {
    let emulator: SogenEmulator
    let logLines: [String]
    @Environment(\.dismiss) private var dismiss

    @State private var mode: MouseMode = .touchscreen
    @State private var frameSize: CGSize = .zero
    @State private var showLogs = false
    @State private var showKeyboard = false
    @State private var cursorVisible = true
    @State private var cursorPosition: CGPoint = .zero

    private var guestAspectRatio: CGFloat {
        guard frameSize.width > 0, frameSize.height > 0 else { return 320.0 / 180.0 }
        return frameSize.width / frameSize.height
    }

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height

            ZStack(alignment: .top) {
                if isLandscape {
                    guestView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        guestView
                            .aspectRatio(guestAspectRatio, contentMode: .fit)
                            .frame(maxWidth: .infinity)
                        Color.clear
                            .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 220)
                    }
                }

                if mode == .trackpad && cursorVisible {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 14, height: 14)
                        .shadow(radius: 2)
                        .position(cursorPosition)
                        .allowsHitTesting(false)
                }

                topBar
                    .padding(8)
                    .background(isLandscape ? Color.black.opacity(0.4) : Color.clear)

                if showLogs {
                    LogsOverlayView(logLines: logLines, onClose: { showLogs = false })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .background(Color.black)
        .onAppear {
            emulator.onFrameSize = { size in
                frameSize = size
            }
            emulator.onCursorVisibilityChange = { visible in
                cursorVisible = visible
            }
        }
    }

    private var guestView: some View {
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
            onDeliverRightClick: { emulator.deliverRightClick() },
            onCursorPositionChange: { point in cursorPosition = point }
        )
    }

    private var topBar: some View {
        HStack {
            Button(action: {
                emulator.stop()
                dismiss()
            }) {
                Image(systemName: "chevron.left")
                    .padding(6)
                    .background(Color.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Spacer()

            HStack(spacing: 6) {
                Button(action: {
                    mode = (mode == .touchscreen) ? .trackpad : .touchscreen
                }) {
                    Image(systemName: mode == .touchscreen ? "hand.tap" : "cursorarrow.motionlines")
                        .padding(6)
                        .background(Color.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Button(action: { showLogs.toggle() }) {
                    Image(systemName: "doc.text")
                        .padding(6)
                        .background(Color.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Button(action: { showKeyboard.toggle() }) {
                    Image(systemName: "keyboard")
                        .padding(6)
                        .background(Color.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }
}
