import SwiftUI
import AVKit

struct AudioRoutePickerView: UIViewRepresentable {
    var activeTintColor: UIColor = .white
    var tintColor: UIColor = UIColor.white.withAlphaComponent(0.8)

    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(frame: .zero)
        configure(view)
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {
        configure(uiView)
    }

    private func configure(_ view: AVRoutePickerView) {
        view.activeTintColor = activeTintColor
        view.tintColor = tintColor
    }
}
