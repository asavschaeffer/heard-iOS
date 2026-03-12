import Testing
@testable import VoiceCore

@MainActor
func expectCallLifecycleState(
    _ coordinator: VoiceCallCoordinator,
    equals debugLabel: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(
        coordinator.callLifecycleState.debugLabel == debugLabel,
        sourceLocation: sourceLocation
    )
}

@MainActor
func expectRouteLifecycleState(
    _ coordinator: VoiceCallCoordinator,
    equals debugLabel: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(
        coordinator.routeLifecycleState.debugLabel == debugLabel,
        sourceLocation: sourceLocation
    )
}
