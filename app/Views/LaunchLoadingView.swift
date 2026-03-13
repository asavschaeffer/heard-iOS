import SwiftUI

struct LaunchLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @EnvironmentObject private var warmup: AppWarmup

    private let launchSeedProgress = 0.22
    private let minimumProgressHold: Duration = .milliseconds(900)

    let onDismiss: () -> Void

    @State private var bubbleRotation = Angle.zero
    @State private var displayedProgress = 0.22
    @State private var overlayOpacity = 1.0
    @State private var didStartExit = false
    @State private var progressUpdatesUnlocked = false

    private var isRegularWidth: Bool { horizontalSizeClass == .regular }
    private var chefSize: CGFloat { isRegularWidth ? 280 : 220 }
    private var bubbleWidth: CGFloat { isRegularWidth ? 240 : 190 }
    private var progressWidth: CGFloat { isRegularWidth ? 240 : 200 }
    private var bubbleOffsetX: CGFloat { isRegularWidth ? 112 : 96 }
    private var bubbleOffsetY: CGFloat { isRegularWidth ? -138 : -112 }

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            Image(decorative: "launch-chef")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: chefSize, height: chefSize)
                .offset(y: 16)
                .accessibilityHidden(true)

            Image(decorative: "launch-bubble")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: bubbleWidth)
                .offset(x: bubbleOffsetX, y: 16 + bubbleOffsetY)
                .rotationEffect(bubbleRotation)
                .accessibilityHidden(true)
                .accessibilityIdentifier("launch.bubble")

            ProgressView(value: displayedProgress, total: 1.0)
                .progressViewStyle(.linear)
                .tint(.orange)
                .frame(width: progressWidth)
                .offset(y: 16 + chefSize / 2 + 18)
                .accessibilityIdentifier("launch.progress")
                .accessibilityLabel("Warmup progress")
                .accessibilityValue(Text("\(Int((displayedProgress * 100).rounded())) percent"))
        }
        .opacity(overlayOpacity)
        .accessibilityIdentifier("launch.overlay")
        .task {
            await unlockProgressUpdatesIfNeeded()
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
    private func unlockProgressUpdatesIfNeeded() async {
        guard progressUpdatesUnlocked == false else { return }

        try? await Task.sleep(for: minimumProgressHold)
        progressUpdatesUnlocked = true
        updateDisplayedProgress(to: warmup.progress)
    }

    @MainActor
    private func updateDisplayedProgress(to value: Double) {
        guard progressUpdatesUnlocked || value >= 1.0 else { return }

        let target = max(displayedProgress, min(max(value, launchSeedProgress), 1.0))

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

        progressUpdatesUnlocked = true
        updateDisplayedProgress(to: 1.0)

        guard reduceMotion == false else {
            overlayOpacity = 0
            onDismiss()
            return
        }

        await runCompletionJiggle()
        try? await Task.sleep(nanoseconds: 90_000_000)
        withAnimation(.easeOut(duration: 0.25)) {
            overlayOpacity = 0
        }

        try? await Task.sleep(nanoseconds: 250_000_000)
        onDismiss()
    }

    @MainActor
    private func runCompletionJiggle() async {
        withAnimation(.spring(duration: 0.16, bounce: 0.28)) {
            bubbleRotation = .degrees(2.2)
        }

        try? await Task.sleep(nanoseconds: 120_000_000)
        withAnimation(.spring(duration: 0.16, bounce: 0.28)) {
            bubbleRotation = .degrees(-1.8)
        }

        try? await Task.sleep(nanoseconds: 120_000_000)
        withAnimation(.spring(duration: 0.18, bounce: 0.22)) {
            bubbleRotation = .zero
        }
    }
}
