import CoreGraphics

struct LaunchScreenLayout {
    static let centerYOffset: CGFloat = 0
    static let chefOffsetX: CGFloat = 0
    static let chefOffsetY: CGFloat = 0
    static let bubbleOffsetX: CGFloat = 104
    static let bubbleOffsetY: CGFloat = -145
    static let progressTopSpacing: CGFloat = 18
    static let progressHeight: CGFloat = 2

    private static let chefWidthRange: ClosedRange<CGFloat> = 170...210
    private static let bubbleWidthRange: ClosedRange<CGFloat> = 175...215
    private static let progressWidthRange: ClosedRange<CGFloat> = 200...240

    let chefSize: CGFloat
    let bubbleWidth: CGFloat
    let progressWidth: CGFloat

    init(containerWidth: CGFloat) {
        chefSize = Self.clamped(containerWidth * 0.26, within: Self.chefWidthRange)
        bubbleWidth = Self.clamped(containerWidth * 0.28, within: Self.bubbleWidthRange)
        progressWidth = Self.clamped(containerWidth * 0.34, within: Self.progressWidthRange)
    }

    private static func clamped(_ value: CGFloat, within range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
