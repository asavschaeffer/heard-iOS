import UIKit

@MainActor
enum UIInteractionWarmup {
    static func warmTextInput() async {
        print("[Warmup] Text Input — loading")

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else {
            // Retry until a scene is available (up to 500ms)
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(50))
                if UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .contains(where: { $0.activationState == .foregroundActive }) {
                    await warmTextInput()
                    return
                }
            }
            print("[Warmup] Text Input warning: no active scene, skipping keyboard warmup")
            return
        }

        // Use a dedicated off-screen window so the warmup doesn't steal
        // focus from the real UI. windowLevel keeps it behind everything.
        let warmupWindow = UIWindow(windowScene: scene)
        warmupWindow.frame = CGRect(x: -1, y: -1, width: 1, height: 1)
        warmupWindow.windowLevel = .init(rawValue: -1000)
        warmupWindow.isHidden = false

        let vc = UIViewController()
        warmupWindow.rootViewController = vc

        let host = TextInputWarmupHostView()
        vc.view.addSubview(host)

        host.primeTraits()

        // Become first responder WITHOUT a dummy inputView — this triggers
        // the keyboard daemon to launch and primes TextKit 2 / UITextView
        // internals. Resigning immediately prevents visible keyboard flash.
        host.activateEditingSession()
        host.primeEditingCommands()
        host.deactivateEditingSession()

        host.removeFromSuperview()
        warmupWindow.isHidden = true
    }

    static func warmMenuSystem() async {
        print("[Warmup] Menu System — loading")

        let delegate = ContextMenuWarmupDelegate()
        _ = delegate.contextMenuInteraction(
            UIContextMenuInteraction(delegate: delegate),
            configurationForMenuAtLocation: .zero
        )
        _ = UIPasteboard.general
        _ = UIMenuSystem.main
        await Task.yield()
    }

}

private final class TextInputWarmupHostView: UIView {
    // UITextView matches SwiftUI TextField(axis: .vertical)'s internal backing store
    private let textView = UITextView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: -32, y: -32, width: 1, height: 1))
        isUserInteractionEnabled = false
        alpha = 0.01

        // No custom inputView — let the real keyboard infrastructure load
        textView.autocorrectionType = .no
        textView.spellCheckingType = .no
        textView.smartInsertDeleteType = .no
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        addSubview(textView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func primeTraits() {
        _ = textView.textInputMode
        _ = textView.textInputContextIdentifier
        _ = textView.inputAssistantItem.leadingBarButtonGroups
        _ = textView.inputAssistantItem.trailingBarButtonGroups
        _ = textView.tokenizer

        // Prime TextKit 2 layout manager (used by SwiftUI TextField)
        _ = textView.textLayoutManager
        _ = textView.layoutManager
    }

    func activateEditingSession() {
        _ = textView.becomeFirstResponder()
    }

    func primeEditingCommands() {
        textView.insertText("a")
        textView.deleteBackward()
    }

    func deactivateEditingSession() {
        _ = textView.resignFirstResponder()
    }
}

private final class ContextMenuWarmupDelegate: NSObject, UIContextMenuInteractionDelegate {
    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        let copyAction = UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in }
        let shareAction = UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { _ in }

        return UIContextMenuConfiguration(
            identifier: nil,
            previewProvider: { UIViewController() },
            actionProvider: { _ in
                UIMenu(title: "", children: [copyAction, shareAction])
            }
        )
    }
}
