import Foundation

public enum VoiceDiagnostics {
    #if DEBUG
    private static let defaultVerboseLoggingEnabled = true
    #else
    private static let defaultVerboseLoggingEnabled = false
    #endif

    private static var verboseLoggingEnabled = defaultVerboseLoggingEnabled

    public static func setVerboseLoggingEnabled(_ isEnabled: Bool) {
        verboseLoggingEnabled = isEnabled
    }

    public static func audio(_ message: @autoclosure () -> String) {
        verbose(message())
    }

    public static func callKit(_ message: @autoclosure () -> String) {
        verbose(message())
    }

    public static func gemini(_ message: @autoclosure () -> String) {
        verbose(message())
    }

    public static func fault(_ message: @autoclosure () -> String) {
        print(message())
    }

    private static func verbose(_ message: @autoclosure () -> String) {
        guard verboseLoggingEnabled else { return }
        print(message())
    }
}
