import SwiftUI

struct PiPCallOverlayView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Binding var pipCenter: CGPoint
    @Binding var pipDragStart: CGPoint?
    @Binding var pipInitialized: Bool
    let onExpand: () -> Void
    
    private let pipSize = CGSize(width: 180, height: 240)
    private let pipPadding: CGFloat = 16
    
    var body: some View {
        GeometryReader { proxy in
            let bounds = proxy.size
            let minX = pipSize.width / 2 + pipPadding
            let maxX = bounds.width - pipSize.width / 2 - pipPadding
            let minY = pipSize.height / 2 + pipPadding
            let maxY = bounds.height - pipSize.height / 2 - pipPadding

            CallPiPView(viewModel: viewModel)
                .frame(width: pipSize.width, height: pipSize.height)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .shadow(radius: 10)
                .position(pipInitialized ? pipCenter : CGPoint(x: maxX, y: minY))
                .onAppear {
                    if !pipInitialized {
                        pipCenter = CGPoint(x: maxX, y: minY)
                        pipInitialized = true
                    }
                }
                .onTapGesture {
                    onExpand()
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

private struct CallPiPView: View {
    @ObservedObject var viewModel: ChatViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Heard, Chef")
                    .font(.footnote.weight(.semibold))
                Spacer()
                Circle()
                    .fill(viewModel.connectionState == .connected ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
            }
            
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 70, height: 70)
                    .scaleEffect(viewModel.callState.isSpeaking ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 0.3).repeatForever(), value: viewModel.callState.isSpeaking)
                
                Image("app-icon-template")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40)
            }
            
            Text(viewModel.connectionState == .connected ? "Call answered" : "Calling...")
                .font(.caption2)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 12) {
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
                    viewModel.stopVoiceSession()
                } label: {
                    Image(systemName: "phone.down.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.red, in: Circle())
                }
            }
        }
        .padding(14)
        .foregroundStyle(.white)
    }
}
