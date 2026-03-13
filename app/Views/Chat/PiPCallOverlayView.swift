import SwiftUI
import UIKit

enum CornerPlacement: Equatable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing

    func position(in size: CGSize, barWidth: CGFloat, barHeight: CGFloat, padding: CGFloat, topInset: CGFloat = 0) -> CGPoint {
        let halfW = barWidth / 2
        let halfH = barHeight / 2
        let topY = topInset + padding + halfH
        switch self {
        case .topLeading:
            return CGPoint(x: padding + halfW, y: topY)
        case .topTrailing:
            return CGPoint(x: size.width - padding - halfW, y: topY)
        case .bottomLeading:
            return CGPoint(x: padding + halfW, y: size.height - padding - halfH)
        case .bottomTrailing:
            return CGPoint(x: size.width - padding - halfW, y: size.height - padding - halfH)
        }
    }

    static func nearest(to point: CGPoint, in size: CGSize, barWidth: CGFloat, barHeight: CGFloat, padding: CGFloat, topInset: CGFloat = 0) -> CornerPlacement {
        let corners: [CornerPlacement] = [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing]
        return corners.min(by: { a, b in
            let posA = a.position(in: size, barWidth: barWidth, barHeight: barHeight, padding: padding, topInset: topInset)
            let posB = b.position(in: size, barWidth: barWidth, barHeight: barHeight, padding: padding, topInset: topInset)
            let distA = hypot(point.x - posA.x, point.y - posA.y)
            let distB = hypot(point.x - posB.x, point.y - posB.y)
            return distA < distB
        }) ?? .topTrailing
    }
}

struct PiPCallOverlayView: View {
    @ObservedObject var viewModel: ChatViewModel
    let onExpand: () -> Void
    let onEndCall: () -> Void
    let onToggleVideo: () -> Void

    @State private var placement: CornerPlacement = .topTrailing
    @State private var dragOffset: CGSize = .zero
    @GestureState private var isDragging = false

    var body: some View {
        GeometryReader { proxy in
            let bounds = proxy.size
            let barWidth = min(bounds.width - 24, 420)
            let barHeight: CGFloat = 56
            let padding: CGFloat = 12
            let topInset = proxy.safeAreaInsets.top + 44
            let cornerPos = placement.position(in: bounds, barWidth: barWidth, barHeight: barHeight, padding: padding, topInset: topInset)

            CallBarView(
                viewModel: viewModel,
                onExpand: onExpand,
                onEndCall: onEndCall,
                onToggleVideo: onToggleVideo
            )
            .frame(width: barWidth)
            .position(
                x: cornerPos.x + dragOffset.width,
                y: cornerPos.y + dragOffset.height
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        dragOffset = value.translation
                    }
                    .onEnded { value in
                        let finalPoint = CGPoint(
                            x: cornerPos.x + value.translation.width,
                            y: cornerPos.y + value.translation.height
                        )
                        let nearest = CornerPlacement.nearest(
                            to: finalPoint,
                            in: bounds,
                            barWidth: barWidth,
                            barHeight: barHeight,
                            padding: padding,
                            topInset: topInset
                        )
                        withAnimation(.spring()) {
                            placement = nearest
                            dragOffset = .zero
                        }
                    }
            )
        }
        .ignoresSafeArea()
        .sensoryFeedback(.impact, trigger: placement)
    }
}

private struct CallBarView: View {
    @ObservedObject var viewModel: ChatViewModel
    let onExpand: () -> Void
    let onEndCall: () -> Void
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

            AudioRoutePickerView(
                activeTintColor: .label,
                tintColor: .secondaryLabel
            )
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.2), in: Circle())
                .opacity(viewModel.connectionState == .connected ? 1.0 : 0.6)

            Button {
                if viewModel.connectionState == .connected {
                    viewModel.toggleMute()
                }
            } label: {
                Image(systemName: viewModel.isMicrophoneMuted ? "mic.fill" : "mic.slash.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.2), in: Circle())
            }
            .disabled(viewModel.connectionState != .connected)

            Button {
                if viewModel.connectionState == .connected {
                    viewModel.toggleSpeaker()
                }
            } label: {
                Image(systemName: viewModel.isSpeakerPreferred ? "speaker.wave.3.fill" : "speaker.slash.fill")
                    .font(.caption)
                    .foregroundStyle(viewModel.isSpeakerPreferred ? .black : .white)
                    .frame(width: 28, height: 28)
                    .background(viewModel.isSpeakerPreferred ? Color.white : Color.white.opacity(0.2), in: Circle())
            }
            .disabled(viewModel.connectionState != .connected)

            Button {
                onEndCall()
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
        .shadow(color: Color.black.opacity(0.3), radius: 12, x: 0, y: 6)
        .foregroundStyle(.white)
    }
}
