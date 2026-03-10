import Foundation
import SwiftData

enum UITestScenario: String {
    case editorFlows = "editor_flows"
    case keyboardDismiss = "keyboard_dismiss"
    case searchFiltering = "search_filtering"
    case emptyState = "empty_state"
    case attachmentsBasic = "attachments_basic"
}

enum UITestSupport {
    static var isEnabled: Bool { TestSupport.isRunningUITests }

    static var scenario: UITestScenario? {
        guard isEnabled else { return nil }
        guard let rawValue = ProcessInfo.processInfo.environment["UITEST_SCENARIO"] else {
            return nil
        }
        return UITestScenario(rawValue: rawValue)
    }

    static func configure(container: ModelContainer) {
        guard isEnabled else { return }
        UITestScenarioFixtures.seed(scenario ?? .editorFlows, into: container.mainContext)
    }

    static func identifierSlug(_ value: String) -> String {
        let slug = value.lowercased().unicodeScalars.map { scalar -> String in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "_"
        }.joined()
        let collapsed = slug.replacingOccurrences(
            of: "_+",
            with: "_",
            options: .regularExpression
        )
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
}
