import SwiftUI

struct UITestFocusProbe: View {
    let identifier: String
    let isFocused: Bool

    var body: some View {
        if TestSupport.isRunningUITests {
            Text(isFocused ? "focused" : "blurred")
                .font(.caption2)
                .foregroundStyle(.clear)
                .frame(height: 1)
                .accessibilityIdentifier(identifier)
        }
    }
}
