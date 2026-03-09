import Foundation

enum CallPresentationStyle: String, CaseIterable, Identifiable {
    case fullScreen = "Full Screen"
    case pictureInPicture = "Picture in Picture"

    var id: String { rawValue }
    var label: String { rawValue }
}
