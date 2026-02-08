import Foundation

// TODO: Add ActivityKit Live Activity target for Dynamic Island.
// This stub keeps call lifecycle hooks in one place.
final class LiveActivityManager {
    func startCallActivity(displayName: String) {
        // TODO: Start Live Activity (ActivityKit) for ongoing call.
        _ = displayName
    }

    func updateCallActivity(status: String, duration: TimeInterval) {
        // TODO: Update Live Activity with call status and duration.
        _ = (status, duration)
    }

    func endCallActivity() {
        // TODO: End Live Activity when call finishes.
    }
}
