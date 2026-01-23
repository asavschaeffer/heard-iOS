import SwiftUI
import AVKit

struct AudioRoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView(frame: .zero)
        view.activeTintColor = UIColor.white
        view.tintColor = UIColor.white.withAlphaComponent(0.8)
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
