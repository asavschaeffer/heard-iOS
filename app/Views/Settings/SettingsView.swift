import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: ChatSettings

    var body: some View {
        NavigationStack {
            Form {
                Section("Chat") {
                    Toggle("Show Read Receipts", isOn: $settings.showReadReceipts)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView(settings: ChatSettings())
}
