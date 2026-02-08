import SwiftUI

struct PiPCallOverlayView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var pipCenter: CGPoint
    @Binding var pipDragStart: CGPoint?
    @Binding var pipInitialized: Bool
    let onExpand: () -> Void
    let onToggleVideo: () -> Void
    
    var body: some View {
        GeometryReader { proxy in
            let bounds = proxy.size
            let barWidth = min(bounds.width - 24, 420)
            let barHeight: CGFloat = 56
            let padding: CGFloat = 12
            let topY = padding + barHeight / 2
            let minX = padding + barWidth / 2
            let maxX = bounds.width - padding - barWidth / 2
            let minY = topY
            let maxY = topY + 120
            let snapX = [minX, bounds.width / 2, maxX]

            CallBarView(
                viewModel: viewModel,
                onExpand: onExpand,
                onToggleVideo: onToggleVideo
            )
            .frame(width: barWidth)
            .position(pipInitialized ? pipCenter : CGPoint(x: bounds.width / 2, y: topY))
            .onAppear {
                if !pipInitialized {
                    pipCenter = CGPoint(x: bounds.width / 2, y: topY)
                    pipInitialized = true
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if pipDragStart == nil { pipDragStart = pipCenter }
                        let start = pipDragStart ?? pipCenter
                        let proposed = CGPoint(
                            x: start.x + value.translation.width,
                            y: start.y + value.translation.height
                        )
                        pipCenter = clamp(proposed, minX: minX, maxX: maxX, minY: minY, maxY: maxY)
                    }
                    .onEnded { _ in
                        pipDragStart = nil
                        let closestX = snapX.min(by: { abs($0 - pipCenter.x) < abs($1 - pipCenter.x) }) ?? bounds.width / 2
                        pipCenter = CGPoint(x: closestX, y: topY)
                    }
            )
        }
        .ignoresSafeArea()
    }

    private func clamp(_ point: CGPoint, minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat) -> CGPoint {
        CGPoint(
            x: min(max(point.x, minX), maxX),
            y: min(max(point.y, minY), maxY)
        )
    }
}

private struct CallBarView: View {
    @ObservedObject var viewModel: ChatViewModel
    let onExpand: () -> Void
    let onToggleVideo: () -> Void
    
    var body: some View {
        HStack(spacing: 14) {
            Button {
                onExpand()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.2), in: Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Heard, Chef")
                        .font(.footnote.weight(.semibold))
                    Circle()
                        .fill(viewModel.connectionState == .connected ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                }
                Text(viewModel.connectionState == .connected ? "Call answered" : "Calling...")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .lineLimit(1)

            Spacer()

            AudioRoutePickerView()
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.2), in: Circle())
                .opacity(viewModel.connectionState == .connected ? 1.0 : 0.6)

            Button {
                if viewModel.connectionState == .connected {
                    viewModel.toggleMute()
                }
            } label: {
                Image(systemName: viewModel.callState.isListening ? "mic.slash.fill" : "mic.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.2), in: Circle())
            }
            .disabled(viewModel.connectionState != .connected)

            Button {
                onToggleVideo()
            } label: {
                Image(systemName: viewModel.callState.isVideoStreaming ? "video.slash.fill" : "video.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.2), in: Circle())
            }
            .disabled(viewModel.connectionState != .connected)

            Button {
                viewModel.stopVoiceSession()
            } label: {
                Image(systemName: "phone.down.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.red, in: Circle())
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
        .foregroundStyle(.white)
    }
}
