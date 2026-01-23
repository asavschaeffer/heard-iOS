import Foundation

final class ChatSettings: ObservableObject {
    @Published var showReadReceipts: Bool {
        didSet {
            UserDefaults.standard.set(showReadReceipts, forKey: Keys.showReadReceipts)
        }
    }

    init() {
        self.showReadReceipts = UserDefaults.standard.bool(forKey: Keys.showReadReceipts)
    }

    private enum Keys {
        static let showReadReceipts = "showReadReceipts"
    }
}
