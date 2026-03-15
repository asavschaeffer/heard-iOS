import SwiftUI

struct LaunchLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var warmup: AppWarmup

    private let launchSeedProgress = 0.22
    private let minimumProgressHold: Duration = .milliseconds(900)

    let onDismiss: () -> Void

    @State private var bubbleRotation = Angle.zero
    @State private var displayedProgress = 0.22
    @State private var overlayOpacity = 1.0
    @State private var didStartExit = false
    @State private var progressUpdatesUnlocked = false

    var body: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            let cy = geo.size.height / 2
            let layout = LaunchScreenLayout(containerWidth: geo.size.width)
            Color(.systemBackground)

            ChefCharacterView(size: layout.chefSize)
                .position(
                    x: cx + LaunchScreenLayout.chefOffsetX,
                    y: cy + LaunchScreenLayout.centerYOffset + LaunchScreenLayout.chefOffsetY
                )
                .accessibilityHidden(true)

            Image(systemName: "bubble.left.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: layout.bubbleWidth)
                .foregroundStyle(Color(red: 1, green: 0.584, blue: 0).opacity(0.25))
                .rotationEffect(bubbleRotation)
                .position(
                    x: cx + LaunchScreenLayout.bubbleOffsetX,
                    y: cy + LaunchScreenLayout.centerYOffset + LaunchScreenLayout.bubbleOffsetY
                )
                .accessibilityHidden(true)
                .accessibilityIdentifier("launch.bubble")

            Capsule()
                .fill(Color(red: 0.929, green: 0.902, blue: 0.875))
                .frame(width: layout.progressWidth, height: LaunchScreenLayout.progressHeight)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color(red: 1, green: 0.584, blue: 0))
                        .frame(width: layout.progressWidth * displayedProgress)
                }
                .position(
                    x: cx,
                    y: cy
                        + LaunchScreenLayout.centerYOffset
                        + LaunchScreenLayout.chefOffsetY
                        + layout.chefSize / 2
                        + LaunchScreenLayout.progressTopSpacing
                )
                .accessibilityIdentifier("launch.progress")
                .accessibilityLabel("Warmup progress")
                .accessibilityValue(Text("\(Int((displayedProgress * 100).rounded())) percent"))
        }
        .ignoresSafeArea()
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
