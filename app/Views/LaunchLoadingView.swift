import SwiftUI

struct LaunchLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var warmup: AppWarmup

    let onDismiss: () -> Void

    @State private var bubbleVisible = false
    @State private var progressVisible = false
    @State private var displayedProgress = 0.0
    @State private var overlayOpacity = 1.0
    @State private var didStartEntrance = false
    @State private var didStartExit = false

    var body: some View {
        GeometryReader { geometry in
            let isRegularWidth = horizontalSizeClass == .regular
            let chefSize = isRegularWidth ? 300.0 : 220.0
            let bubbleWidth = isRegularWidth ? 260.0 : 200.0
            let progressWidth = isRegularWidth ? 220.0 : 180.0
            let chefCenterX = (geometry.size.width / 2) - 28
            let chefCenterY = (geometry.size.height / 2) + 16
            let bubbleCenterX = chefCenterX + (isRegularWidth ? 118 : 88)
            let bubbleCenterY = chefCenterY - (isRegularWidth ? 146 : 108)
            let progressY = chefCenterY + (chefSize / 2) + 18

            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                Image(decorative: "launch-chef")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: chefSize, height: chefSize)
                    .position(x: chefCenterX, y: chefCenterY)
                    .accessibilityHidden(true)

                Image(decorative: "launch-bubble")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: bubbleWidth)
                    .position(x: bubbleCenterX, y: bubbleCenterY)
                    .scaleEffect(reduceMotion ? 1.0 : (bubbleVisible ? 1.0 : 0.92))
                    .offset(
                        x: reduceMotion ? 0 : (bubbleVisible ? 0 : 10),
                        y: reduceMotion ? 0 : (bubbleVisible ? 0 : -8)
                    )
                    .opacity(bubbleVisible ? 1.0 : 0.0)
                    .accessibilityHidden(true)
                    .accessibilityIdentifier("launch.bubble")

                ProgressView(value: displayedProgress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(.orange)
                    .frame(width: progressWidth)
                    .position(x: chefCenterX, y: progressY)
                    .opacity(progressVisible ? 1.0 : 0.0)
                    .offset(y: reduceMotion ? 0 : (progressVisible ? 0 : 8))
                    .accessibilityIdentifier("launch.progress")
                    .accessibilityLabel("Warmup progress")
                    .accessibilityValue(Text("\(Int((displayedProgress * 100).rounded())) percent"))
            }
            .opacity(overlayOpacity)
            .accessibilityIdentifier("launch.overlay")
        }
        .task {
            await runEntranceSequenceIfNeeded()
        }
        .onChange(of: warmup.progress, initial: true) { _, newValue in
            updateDisplayedProgress(to: newValue)
        }
        .onChange(of: warmup.isFinished) { _, isFinished in
            guard isFinished else { return }

            Task {
                await completeAndDismissIfNeeded()
            }
        }
    }

    @MainActor
    private func runEntranceSequenceIfNeeded() async {
        guard didStartEntrance == false else { return }
        didStartEntrance = true

        if reduceMotion {
            bubbleVisible = true
            progressVisible = true
            return
        }

        try? await Task.sleep(nanoseconds: 120_000_000)
        withAnimation(.spring(duration: 0.45, bounce: 0.22)) {
            bubbleVisible = true
        }

        try? await Task.sleep(nanoseconds: 80_000_000)
        withAnimation(.easeOut(duration: 0.2)) {
            progressVisible = true
        }
    }

    @MainActor
    private func updateDisplayedProgress(to value: Double) {
        let target = max(displayedProgress, min(value, 1.0))

        if reduceMotion {
            displayedProgress = target
            return
        }

        withAnimation(.easeOut(duration: 0.18)) {
            displayedProgress = target
        }
    }

    @MainActor
    private func completeAndDismissIfNeeded() async {
        guard didStartExit == false else { return }
        didStartExit = true

        if bubbleVisible == false {
            bubbleVisible = true
        }

        if progressVisible == false {
            progressVisible = true
        }

        updateDisplayedProgress(to: 1.0)

        guard reduceMotion == false else {
            overlayOpacity = 0
            onDismiss()
            return
        }

        try? await Task.sleep(nanoseconds: 120_000_000)
        withAnimation(.easeOut(duration: 0.25)) {
            overlayOpacity = 0
        }

        try? await Task.sleep(nanoseconds: 250_000_000)
        onDismiss()
    }
}
