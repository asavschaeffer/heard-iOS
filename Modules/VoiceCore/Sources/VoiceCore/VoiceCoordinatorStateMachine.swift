import Foundation

enum VoiceCallOwnership: String, Equatable {
    case direct
    case callKit
}

struct VoiceCallRuntimeContext: Equatable {
    var ownership: VoiceCallOwnership
    var captureAllowed: Bool
    var captureStartedFromCallKit: Bool
    var transportState: VoiceTransportState
    var isMuted: Bool
    var isPlaybackActive: Bool
    var useVoiceProcessingInput: Bool
    var waitingForCallKitActivation: Bool
    var waitingForRouteStabilization: Bool
    var waitingForTransport: Bool
    var speakerPreferred: Bool
}

struct StartContext: Equatable {
    var runtime: VoiceCallRuntimeContext
}

struct ActiveContext: Equatable {
    var runtime: VoiceCallRuntimeContext
}

struct ReconnectContext: Equatable {
    var runtime: VoiceCallRuntimeContext
}

struct StopContext: Equatable {
    var runtime: VoiceCallRuntimeContext
}

struct FailureContext: Equatable {
    var runtime: VoiceCallRuntimeContext
    var message: String
}

enum VoiceCallLifecycleState: Equatable {
    case idle
    case starting(StartContext)
    case active(ActiveContext)
    case reconnecting(ReconnectContext)
    case stopping(StopContext)
    case failed(FailureContext)

    var runtimeContext: VoiceCallRuntimeContext? {
        switch self {
        case .idle:
            return nil
        case .starting(let context):
            return context.runtime
        case .active(let context):
            return context.runtime
        case .reconnecting(let context):
            return context.runtime
        case .stopping(let context):
            return context.runtime
        case .failed(let context):
            return context.runtime
        }
    }

    var transportState: VoiceTransportState {
        runtimeContext?.transportState ?? .disconnected
    }

    var isPresented: Bool {
        if case .idle = self {
            return false
        }
        return true
    }

    var debugLabel: String {
        switch self {
        case .idle:
            return "idle"
        case .starting(let context):
            return "starting(\(context.runtime.phaseLabel))"
        case .active(let context):
            return "active(\(context.runtime.phaseLabel))"
        case .reconnecting(let context):
            return "reconnecting(\(context.runtime.phaseLabel))"
        case .stopping(let context):
            return "stopping(\(context.runtime.phaseLabel))"
        case .failed(let context):
            return "failed(\(context.runtime.phaseLabel), message=\(context.message))"
        }
    }

    func replacingRuntime(_ runtime: VoiceCallRuntimeContext) -> VoiceCallLifecycleState {
        switch self {
        case .idle:
            return .idle
        case .starting:
            return .starting(StartContext(runtime: runtime))
        case .active:
            return .active(ActiveContext(runtime: runtime))
        case .reconnecting:
            return .reconnecting(ReconnectContext(runtime: runtime))
        case .stopping:
            return .stopping(StopContext(runtime: runtime))
        case .failed(let context):
            return .failed(FailureContext(runtime: runtime, message: context.message))
        }
    }
}

extension VoiceCallRuntimeContext {
    var phaseLabel: String {
        var parts: [String] = [ownership.rawValue, transportState.debugLabel]
        if waitingForCallKitActivation {
            parts.append("awaitingCallKit")
        }
        if waitingForRouteStabilization {
            parts.append("awaitingRoute")
        }
        if waitingForTransport {
            parts.append("awaitingTransport")
        }
        if isMuted {
            parts.append("muted")
        }
        if captureStartedFromCallKit {
            parts.append("captureFromCallKit")
        }
        if !useVoiceProcessingInput {
            parts.append("fallbackInput")
        }
        if isPlaybackActive {
            parts.append("playbackActive")
        }
        return parts.joined(separator: ",")
    }
}

struct RouteContext: Equatable {
    var speakerPreferred: Bool
    var lastReasonDescription: String?
    var lastShouldAdapt: Bool
    var lastAdaptationAt: Date?
}

struct RouteAdaptationContext: Equatable {
    var base: RouteContext
    var reasonDescription: String
    var previousRouteDescription: String
    var resumeCapture: Bool
    var resumePlayback: Bool
}

struct InterruptionContext: Equatable {
    var base: RouteContext
    var shouldResume: Bool
}

struct RouteBlockContext: Equatable {
    var base: RouteContext
    var reasonDescription: String
}

enum VoiceRouteLifecycleState: Equatable {
    case stable(RouteContext)
    case adapting(RouteAdaptationContext)
    case interrupted(InterruptionContext)
    case blocked(RouteBlockContext)

    var baseContext: RouteContext {
        switch self {
        case .stable(let context):
            return context
        case .adapting(let context):
            return context.base
        case .interrupted(let context):
            return context.base
        case .blocked(let context):
            return context.base
        }
    }

    var lastAdaptationAt: Date? {
        baseContext.lastAdaptationAt
    }

    var debugLabel: String {
        switch self {
        case .stable(let context):
            return "stable(speaker=\(context.speakerPreferred), reason=\(context.lastReasonDescription ?? "none"))"
        case .adapting(let context):
            return "adapting(reason=\(context.reasonDescription), resumeCapture=\(context.resumeCapture), resumePlayback=\(context.resumePlayback))"
        case .interrupted(let context):
            return "interrupted(shouldResume=\(context.shouldResume))"
        case .blocked(let context):
            return "blocked(reason=\(context.reasonDescription))"
        }
    }
}

enum VoiceCoordinatorEvent: Equatable {
    case intentStartCall
    case intentStopCall
    case intentToggleMute(isMuted: Bool)
    case intentToggleSpeaker(preferSpeaker: Bool)
    case transportWillConnect
    case transportConnected
    case transportDisconnected
    case transportFailed(message: String)
    case callKitDidActivate
    case callKitDidDeactivate
    case callKitMuteChanged(isMuted: Bool)
    case callKitTransactionFailed(details: String, disablesCallKit: Bool)
    case routeChanged(reason: String, previousRouteDescription: String, shouldAdapt: Bool)
    case routeAdaptationStarted(resumeCapture: Bool, resumePlayback: Bool)
    case routeAdaptationFinished
    case routeAdaptationSkipped(reason: String)
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    case voiceProcessingFallbackRequested
    case captureStarted
    case captureStopped
    case playbackStarted
    case playbackStopped
    case stateTransition(from: VoiceCallLifecycleState, to: VoiceCallLifecycleState)
    case routeStateTransition(from: VoiceRouteLifecycleState, to: VoiceRouteLifecycleState)

    var debugLabel: String {
        switch self {
        case .intentStartCall:
            return "intentStartCall"
        case .intentStopCall:
            return "intentStopCall"
        case .intentToggleMute(let isMuted):
            return "intentToggleMute(\(isMuted))"
        case .intentToggleSpeaker(let preferSpeaker):
            return "intentToggleSpeaker(\(preferSpeaker))"
        case .transportWillConnect:
            return "transportWillConnect"
        case .transportConnected:
            return "transportConnected"
        case .transportDisconnected:
            return "transportDisconnected"
        case .transportFailed(let message):
            return "transportFailed(\(message))"
        case .callKitDidActivate:
            return "callKitDidActivate"
        case .callKitDidDeactivate:
            return "callKitDidDeactivate"
        case .callKitMuteChanged(let isMuted):
            return "callKitMuteChanged(\(isMuted))"
        case .callKitTransactionFailed(let details, let disablesCallKit):
            return "callKitTransactionFailed(details=\(details), disablesCallKit=\(disablesCallKit))"
        case .routeChanged(let reason, _, let shouldAdapt):
            return "routeChanged(reason=\(reason), shouldAdapt=\(shouldAdapt))"
        case .routeAdaptationStarted(let resumeCapture, let resumePlayback):
            return "routeAdaptationStarted(capture=\(resumeCapture), playback=\(resumePlayback))"
        case .routeAdaptationFinished:
            return "routeAdaptationFinished"
        case .routeAdaptationSkipped(let reason):
            return "routeAdaptationSkipped(\(reason))"
        case .interruptionBegan:
            return "interruptionBegan"
        case .interruptionEnded(let shouldResume):
            return "interruptionEnded(\(shouldResume))"
        case .voiceProcessingFallbackRequested:
            return "voiceProcessingFallbackRequested"
        case .captureStarted:
            return "captureStarted"
        case .captureStopped:
            return "captureStopped"
        case .playbackStarted:
            return "playbackStarted"
        case .playbackStopped:
            return "playbackStopped"
        case .stateTransition(let from, let to):
            return "callStateTransition(\(from.debugLabel) -> \(to.debugLabel))"
        case .routeStateTransition(let from, let to):
            return "routeStateTransition(\(from.debugLabel) -> \(to.debugLabel))"
        }
    }
}

enum VoiceCoordinatorEffect: Equatable {
    case startCallKitCall(displayName: String)
    case endCallKitCall
    case reportCallConnected
    case configureCallKitSession(preferSpeaker: Bool?)
    case configureFallbackSession(preferSpeaker: Bool)
    case applyOutputOverride(preferSpeaker: Bool)
    case startCapture
    case stopCapture
    case restartCaptureForFallback
    case stopPlayback(clearQueue: Bool)
    case preparePlayback
    case resetIdlePlaybackGraph(reason: String)
    case performRouteAdaptation(RouteAdaptationContext)
    case disableCallKit
    case notifyDelegateCallKitEnabled(Bool)
    case completeStop
}

@MainActor
protocol VoiceCoordinatorEventSink: AnyObject {
    func record(_ event: VoiceCoordinatorEvent)
}

@MainActor
final class VoiceDiagnosticsEventSink: VoiceCoordinatorEventSink {
    func record(_ event: VoiceCoordinatorEvent) {
        switch event {
        case .stateTransition(let from, let to):
            VoiceDiagnostics.audio("[Audio] call-state \(from.debugLabel) -> \(to.debugLabel)")
        case .routeStateTransition(let from, let to):
            VoiceDiagnostics.audio("[Audio] route-state \(from.debugLabel) -> \(to.debugLabel)")
        case .routeAdaptationStarted(let resumeCapture, let resumePlayback):
            VoiceDiagnostics.audio("[Audio] route adaptation started resumeCapture=\(resumeCapture) resumePlayback=\(resumePlayback)")
        case .routeAdaptationFinished:
            VoiceDiagnostics.audio("[Audio] route adaptation finished")
        case .routeAdaptationSkipped(let reason):
            VoiceDiagnostics.audio("[Audio] route adaptation skipped reason=\(reason)")
        case .transportConnected:
            VoiceDiagnostics.audio("[Audio] transport connected")
        case .transportDisconnected:
            VoiceDiagnostics.audio("[Audio] transport disconnected")
        case .transportFailed(let message):
            VoiceDiagnostics.audio("[Audio] transport failed message=\(message)")
        case .callKitTransactionFailed(let details, let disablesCallKit):
            VoiceDiagnostics.audio("[Audio] callkit transaction failed details=\(details) disablesCallKit=\(disablesCallKit)")
        default:
            VoiceDiagnostics.audio("[Audio] event \(event.debugLabel)")
        }
    }
}
