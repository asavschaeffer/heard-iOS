import SwiftUI

struct ChatSettingsSection: View {
    @ObservedObject var settings: ChatSettings

    var body: some View {
        Section("Chat") {
            Toggle("Show Read Receipts", isOn: $settings.showReadReceipts)
        }
    }
}
