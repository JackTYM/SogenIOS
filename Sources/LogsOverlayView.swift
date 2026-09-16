import SwiftUI

struct LogsOverlayView: View {
    let logLines: [String]
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Logs").font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                }
            }
            .padding(8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(logLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(6)
                }
                .onChange(of: logLines.count) { count in
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
        }
        .background(Color.black.opacity(0.92))
    }
}
