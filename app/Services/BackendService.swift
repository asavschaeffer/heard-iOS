import Foundation
import OSLog

/// Thin HTTP client for the Cloud Run backend.
///
/// Handles text chat via `POST /chat` and provides the backend URL
/// used by `GeminiService` for WebSocket voice relay.
actor BackendService {

    static let shared = BackendService()

    private let logger = Logger(subsystem: "com.heardchef", category: "Backend")

    // MARK: - Configuration

    /// Base URL for the Cloud Run backend (no trailing slash).
    /// Set via `BACKEND_URL` in Secrets.xcconfig → Info.plist.
    nonisolated let baseURL: String = {
        if let url = Bundle.main.infoDictionary?["BACKEND_URL"] as? String, !url.isEmpty {
            return url
        }
        // Fallback for local development
        return "http://localhost:8080"
    }()

    /// WebSocket URL for voice relay (`wss://` or `ws://`).
    nonisolated var voiceURL: String {
        let wsScheme = baseURL.hasPrefix("https") ? "wss" : "ws"
        let hostPart = baseURL
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        return "\(wsScheme)://\(hostPart)/voice"
    }

    // MARK: - Text Chat

    /// Send a text message to the backend and return the reply.
    func sendText(_ text: String, sessionID: String, userID: String = "default") async throws -> String {
        guard let url = URL(string: "\(baseURL)/chat") else {
            throw BackendError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "message": text,
            "session_id": sessionID,
            "user_id": userID,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        logger.debug("[Backend] POST /chat sessionID=\(sessionID) chars=\(text.count)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw BackendError.connectionFailed
        }
        guard (200...299).contains(http.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            logger.error("[Backend] HTTP \(http.statusCode): \(errorBody)")
            throw BackendError.serverError(http.statusCode, errorBody)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let reply = json["reply"] as? String else {
            throw BackendError.invalidResponse
        }

        logger.debug("[Backend] Reply chars=\(reply.count)")
        return reply
    }

    // MARK: - Photo Chat

    /// Send a photo (with optional text) to the backend and return the reply.
    func sendPhoto(_ imageData: Data, text: String? = nil, sessionID: String, userID: String = "default") async throws -> String {
        guard let url = URL(string: "\(baseURL)/chat-with-photo") else {
            throw BackendError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90  // photos take longer

        var body: [String: Any] = [
            "image": imageData.base64EncodedString(),
            "session_id": sessionID,
            "user_id": userID,
        ]
        if let text, !text.isEmpty {
            body["message"] = text
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        logger.debug("[Backend] POST /chat-with-photo sessionID=\(sessionID) imageBytes=\(imageData.count) text=\(text?.count ?? 0)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw BackendError.connectionFailed
        }
        guard (200...299).contains(http.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            logger.error("[Backend] HTTP \(http.statusCode): \(errorBody)")
            throw BackendError.serverError(http.statusCode, errorBody)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let reply = json["reply"] as? String else {
            throw BackendError.invalidResponse
        }

        logger.debug("[Backend] Reply chars=\(reply.count)")
        return reply
    }
}

// MARK: - Errors

enum BackendError: LocalizedError {
    case invalidURL
    case connectionFailed
    case invalidResponse
    case serverError(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid backend URL"
        case .connectionFailed:
            return "Could not connect to backend"
        case .invalidResponse:
            return "Invalid response from backend"
        case .serverError(let code, let body):
            return "Backend error \(code): \(body)"
        }
    }
}
