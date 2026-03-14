import CoreGraphics

struct LaunchScreenLayout {
    static let centerYOffset: CGFloat = 16
    static let chefOffsetX: CGFloat = -25
    static let chefOffsetY: CGFloat = 10
    static let bubbleOffsetX: CGFloat = 104
    static let bubbleOffsetY: CGFloat = -122
    static let progressTopSpacing: CGFloat = 18
    static let progressHeight: CGFloat = 2

    private static let chefWidthRange: ClosedRange<CGFloat> = 170...210
    private static let bubbleWidthRange: ClosedRange<CGFloat> = 145...180
    private static let progressWidthRange: ClosedRange<CGFloat> = 200...240

    let chefSize: CGFloat
    let bubbleWidth: CGFloat
    let progressWidth: CGFloat

    init(containerWidth: CGFloat) {
        chefSize = Self.clamped(containerWidth * 0.26, within: Self.chefWidthRange)
        bubbleWidth = Self.clamped(containerWidth * 0.22, within: Self.bubbleWidthRange)
        progressWidth = Self.clamped(containerWidth * 0.34, within: Self.progressWidthRange)
    }

    private static func clamped(_ value: CGFloat, within range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
